#include <Windows.h>
#include <msctf.h>
#include <richedit.h>
#include <windowsx.h>

#include <chrono>
#include <cwchar>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr CLSID kPersonalClsid = {
    0x56a47253,
    0xa7c1,
    0x53ac,
    {0x90, 0x28, 0x72, 0x97, 0x20, 0x7b, 0xd9, 0x72}};
constexpr GUID kPersonalProfile = {
    0x1cac6601,
    0x4479,
    0x55c1,
    {0xbc, 0xa3, 0x2b, 0x46, 0xb9, 0xaf, 0xd3, 0x75}};

void PumpFor(DWORD milliseconds) {
  const ULONGLONG end = GetTickCount64() + milliseconds;
  while (GetTickCount64() < end) {
    MSG msg{};
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
}

bool SendKey(WORD key) {
  INPUT input[2]{};
  input[0].type = INPUT_KEYBOARD;
  input[0].ki.wVk = key;
  input[1] = input[0];
  input[1].ki.dwFlags = KEYEVENTF_KEYUP;
  return SendInput(2, input, sizeof(INPUT)) == 2;
}

class MouseTrackerProbe final : public ITfMouseSink {
public:
  STDMETHODIMP QueryInterface(REFIID iid, void **object) override {
    if (!object)
      return E_INVALIDARG;
    *object = nullptr;
    if (iid == IID_IUnknown || iid == __uuidof(ITfMouseSink)) {
      *object = static_cast<ITfMouseSink *>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
  STDMETHODIMP_(ULONG) Release() override {
    const ULONG remaining = --references_;
    if (!remaining)
      delete this;
    return remaining;
  }
  STDMETHODIMP OnMouseEvent(ULONG edge, ULONG quadrant, DWORD buttons,
                           BOOL *eaten) override {
    if (!eaten)
      return E_INVALIDARG;
    *eaten = FALSE;
    ++events;
    std::cout << "MOUSE_TRACKER_EVENT: edge=" << edge << " quadrant=" << quadrant
              << " buttons=" << buttons << "\n";
    return S_OK;
  }
  unsigned events = 0;

private:
  ULONG references_ = 1;
};

// The test app observes, but never consumes, mouse events over the current
// TSF composition. Failure is diagnostic: a host need not expose a tracker.
bool AttachMouseTracker(MouseTrackerProbe *probe, ITfMouseTracker **tracker,
                        DWORD *cookie) {
  *tracker = nullptr;
  *cookie = TF_INVALID_COOKIE;
  using GetThreadMgr = HRESULT(WINAPI *)(ITfThreadMgr **);
  const HMODULE module = GetModuleHandleW(L"msctf.dll");
  const auto getThreadMgr = module ? reinterpret_cast<GetThreadMgr>(
                                        GetProcAddress(module, "TF_GetThreadMgr"))
                                   : nullptr;
  ITfThreadMgr *manager = nullptr;
  ITfDocumentMgr *document = nullptr;
  ITfContext *context = nullptr;
  ITfContextComposition *compositions = nullptr;
  IEnumITfCompositionView *enumerator = nullptr;
  ITfCompositionView *view = nullptr;
  ITfRange *range = nullptr;
  HRESULT hr = getThreadMgr ? getThreadMgr(&manager) : E_NOINTERFACE;
  if (SUCCEEDED(hr) && manager)
    hr = manager->GetFocus(&document);
  if (SUCCEEDED(hr) && document)
    hr = document->GetTop(&context);
  if (SUCCEEDED(hr) && context)
    hr = context->QueryInterface(__uuidof(ITfContextComposition),
                                 reinterpret_cast<void **>(&compositions));
  if (SUCCEEDED(hr) && compositions)
    hr = compositions->EnumCompositions(&enumerator);
  ULONG fetched = 0;
  if (SUCCEEDED(hr) && enumerator)
    hr = enumerator->Next(1, &view, &fetched);
  if (hr == S_OK && fetched == 1 && view)
    hr = view->GetRange(&range);
  else if (SUCCEEDED(hr))
    hr = E_FAIL;
  if (SUCCEEDED(hr) && context)
    hr = context->QueryInterface(__uuidof(ITfMouseTracker),
                                 reinterpret_cast<void **>(tracker));
  if (SUCCEEDED(hr) && *tracker && range)
    hr = (*tracker)->AdviseMouseSink(range, probe, cookie);
  if (range) range->Release();
  if (view) view->Release();
  if (enumerator) enumerator->Release();
  if (compositions) compositions->Release();
  if (context) context->Release();
  if (document) document->Release();
  if (manager) manager->Release();
  if (FAILED(hr) && *tracker) {
    (*tracker)->Release();
    *tracker = nullptr;
  }
  std::cout << "MOUSE_TRACKER_ATTACH: hr=0x" << std::hex
            << static_cast<unsigned long>(hr) << std::dec << "\n";
  return SUCCEEDED(hr) && *tracker && *cookie != TF_INVALID_COOKIE;
}

struct MouseTrackerRegistration {
  MouseTrackerProbe *probe = new MouseTrackerProbe;
  ITfMouseTracker *tracker = nullptr;
  DWORD cookie = TF_INVALID_COOKIE;
  void Detach() {
    if (tracker && cookie != TF_INVALID_COOKIE)
      tracker->UnadviseMouseSink(cookie);
    cookie = TF_INVALID_COOKIE;
    if (tracker) {
      tracker->Release();
      tracker = nullptr;
    }
    if (probe) {
      probe->Release();
      probe = nullptr;
    }
  }
  ~MouseTrackerRegistration() { Detach(); }
};

// Disposable-VM experiment: remove the top padding from the candidate HWND's
// region and restore it at scope exit. This changes visuals as well as hits.
struct CandidateRegionExperiment {
  HWND window = nullptr;
  bool applied = false;
  ~CandidateRegionExperiment() {
    if (applied && IsWindow(window))
      SetWindowRgn(window, nullptr, TRUE);
  }
};

// Capture only the disposable test candidate window for visual review.
bool CaptureCandidate(HWND window, HWND background, const wchar_t *name) {
  wchar_t directory[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"CHENGJIANG_SMOKE_SCREENSHOT_DIR", directory,
                               MAX_PATH))
    return false;
  RECT bounds{};
  RECT safeBounds{};
  if (!GetWindowRect(window, &bounds) ||
      !GetWindowRect(background, &safeBounds) ||
      GetForegroundWindow() != GetAncestor(background, GA_ROOT) ||
      bounds.left < safeBounds.left || bounds.top < safeBounds.top ||
      bounds.right > safeBounds.right || bounds.bottom > safeBounds.bottom)
    return false;
  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  if (width <= 0 || height <= 0 || width > 4096 || height > 4096)
    return false;
  HDC screen = GetDC(nullptr);
  HDC memory = screen ? CreateCompatibleDC(screen) : nullptr;
  HBITMAP bitmap =
      memory ? CreateCompatibleBitmap(screen, width, height) : nullptr;
  if (!bitmap) {
    if (memory)
      DeleteDC(memory);
    if (screen)
      ReleaseDC(nullptr, screen);
    return false;
  }
  HGDIOBJ old = SelectObject(memory, bitmap);
  const BOOL copied = BitBlt(memory, 0, 0, width, height, screen, bounds.left,
                             bounds.top, SRCCOPY | CAPTUREBLT);
  SelectObject(memory, old);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  const DWORD bytes = static_cast<DWORD>(width * height * 4);
  std::vector<unsigned char> pixels(bytes);
  const bool read =
      copied && GetDIBits(memory, bitmap, 0, height, pixels.data(), &info,
                          DIB_RGB_COLORS) == height;
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  if (!read)
    return false;
  const std::wstring path = std::wstring(directory) + L"\\" + name + L".bmp";
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE)
    return false;
  BITMAPFILEHEADER header{};
  header.bfType = 0x4d42;
  header.bfOffBits = sizeof(header) + sizeof(info.bmiHeader);
  header.bfSize = header.bfOffBits + bytes;
  DWORD written = 0;
  bool ok = WriteFile(file, &header, sizeof(header), &written, nullptr) &&
            written == sizeof(header);
  ok = ok &&
       WriteFile(file, &info.bmiHeader, sizeof(info.bmiHeader), &written,
                 nullptr) &&
       written == sizeof(info.bmiHeader);
  ok = ok && WriteFile(file, pixels.data(), bytes, &written, nullptr) &&
       written == bytes;
  CloseHandle(file);
  return ok;
}
} // namespace

int main(int argc, char **argv) {
  const std::string argument = argc == 2 ? argv[1] : "";
  if (argc > 2 || (argc == 2 && argument != "--horizontal-navigation=3" &&
                   argument != "--horizontal-navigation=6" &&
                   argument != "--horizontal-navigation=9" &&
                   argument != "--mouse-caret-diagnostic" &&
                   argument != "--mouse-caret-richedit" &&
                   argument != "--mouse-caret-region")) {
    std::cerr << "Unexpected interactive smoke-test arguments.\n";
    return 1;
  }
  const bool testRegion = argument == "--mouse-caret-region";
  const bool richEdit = argument == "--mouse-caret-richedit" || testRegion;
  const bool testMouseCaret = argument == "--mouse-caret-diagnostic" || richEdit;
  const bool testHorizontalNavigation = argc == 2 && !testMouseCaret;
  const int pageSize = testHorizontalNavigation ? argument.back() - '0' : 0;
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)))
    return 1;
  HWND window = CreateWindowExW(0, L"STATIC", L"Personal IME interactive smoke",
                                WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT,
                                CW_USEDEFAULT, 640, 300, nullptr, nullptr,
                                GetModuleHandleW(nullptr), nullptr);
  if (richEdit && !LoadLibraryW(L"Msftedit.dll")) {
    std::cerr << "Could not load the disposable Rich Edit control.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, richEdit ? MSFTEDIT_CLASS : L"EDIT", L"",
                              WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_MULTILINE,
                              10, 10, 600, 220, window, nullptr,
                              GetModuleHandleW(nullptr), nullptr);
  if (!window || !edit) {
    std::cerr << "Could not create the disposable test window.\n";
    return 1;
  }
  ShowWindow(window, SW_MAXIMIZE);
  RECT client{};
  if (!GetClientRect(window, &client) || client.right <= 200 ||
      client.bottom <= 160 ||
      !MoveWindow(edit, 100, 80, client.right - 200, client.bottom - 160,
                  TRUE)) {
    std::cerr << "Could not size the disposable test background.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  SetForegroundWindow(window);
  SetFocus(edit);
  PumpFor(1000);
  if (GetForegroundWindow() != window || GetFocus() != edit) {
    std::cout << "SKIP: desktop did not grant input focus.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 77;
  }

  if (!LoadKeyboardLayoutW(L"00000804", KLF_ACTIVATE))
    std::cerr << "Could not explicitly activate the Simplified Chinese "
                 "keyboard layout.\n";
  ITfInputProcessorProfileMgr *profiles = nullptr;
  HRESULT hr = CoCreateInstance(
      CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
      IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&profiles));
  if (SUCCEEDED(hr)) {
    hr =
        profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0804,
                                  kPersonalClsid, kPersonalProfile, nullptr,
                                  TF_IPPMF_FORSESSION | TF_IPPMF_ENABLEPROFILE |
                                      TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
    profiles->Release();
  }
  if (hr != S_OK) {
    std::cerr << "Could not activate personal TSF profile: 0x" << std::hex
              << static_cast<unsigned long>(hr) << "\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  PumpFor(1500);
  if (GetForegroundWindow() != window || GetFocus() != edit) {
    std::cerr << "The test window lost input focus after profile activation.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  for (const WORD key :
       {WORD('N'), WORD('I'), WORD('H'), WORD('A'), WORD('O')}) {
    if (!SendKey(key)) {
      std::cerr << "Could not inject test keystrokes.\n";
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(250);
  }
  PumpFor(1500);
  const HWND candidate =
      FindWindowW(L"chengjiangime_windows", L"chengjiangimecandwnd");
  RECT before{};
  if (!candidate || !IsWindowVisible(candidate) ||
      !GetWindowRect(candidate, &before)) {
    std::cerr << "The personal candidate window did not appear.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  if (!CaptureCandidate(candidate, window, L"candidate-before"))
    std::cerr << "Could not capture the candidate before backspace.\n";
  if (!SendKey(VK_BACK)) {
    std::cerr << "Could not inject the backspace key.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  PumpFor(1000);
  RECT after{};
  if (!IsWindowVisible(candidate) || !GetWindowRect(candidate, &after)) {
    std::cerr << "The candidate window disappeared while the composition "
                 "continued.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  if (!CaptureCandidate(candidate, window, L"candidate-after"))
    std::cerr << "Could not capture the candidate after backspace.\n";
  std::cout << "Candidate bounds before backspace: " << before.left << ','
            << before.top << ' ' << before.right - before.left << 'x'
            << before.bottom - before.top << "; after: " << after.left << ','
            << after.top << ' ' << after.right - after.left << 'x'
            << after.bottom - after.top << "\n";
  if (after.right - after.left < before.right - before.left ||
      after.bottom - after.top < before.bottom - before.top ||
      after.left != before.left || after.top != before.top) {
    std::cerr << "Candidate size or fixed position was not preserved after "
                 "backspace.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  for (const WORD key : {WORD('O'), WORD(VK_SPACE)}) {
    if (!SendKey(key)) {
      std::cerr << "Could not finish the test composition.\n";
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(500);
  }
  PumpFor(1000);
  wchar_t text[256]{};
  GetWindowTextW(edit, text, static_cast<int>(sizeof(text) / sizeof(text[0])));
  bool hasCjk = false;
  for (const wchar_t *p = text; *p; ++p)
    hasCjk = hasCjk || (*p >= 0x4e00 && *p <= 0x9fff);
  std::wcout << L"Edit text after nihao + space: " << text << L"\n";
  if (!hasCjk) {
    std::cerr << "No Chinese text was committed.\n";
    DestroyWindow(window);
    CoUninitialize();
    return 1;
  }
  if (testHorizontalNavigation) {
    // One right press per candidate should move from the first item to the
    // first item on the next page, matching a direct Page Down.
    auto typeShi = [&]() {
      SetWindowTextW(edit, L"");
      for (const WORD key : {WORD('S'), WORD('H'), WORD('I')}) {
        if (!SendKey(key))
          return false;
        PumpFor(250);
      }
      PumpFor(1500);
      return true;
    };
    if (!typeShi() || !SendKey(VK_SPACE)) {
      std::cerr << "Could not enter the first navigation reference.\n";
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(1000);
    wchar_t first[256]{};
    GetWindowTextW(edit, first, static_cast<int>(sizeof(first) / sizeof(first[0])));
    if (!typeShi()) {
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    if (!SendKey(VK_NEXT)) {
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(1000);
    if (!SendKey(VK_SPACE)) {
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(1000);
    wchar_t nextPage[256]{};
    GetWindowTextW(edit, nextPage, static_cast<int>(sizeof(nextPage) / sizeof(nextPage[0])));
    if (!typeShi()) {
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    for (int i = 0; i < pageSize; ++i) {
      if (!SendKey(VK_RIGHT)) {
        DestroyWindow(window);
        CoUninitialize();
        return 1;
      }
      PumpFor(300);
    }
    if (!SendKey(VK_SPACE)) {
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    PumpFor(1000);
    wchar_t moved[256]{};
    GetWindowTextW(edit, moved, static_cast<int>(sizeof(moved) / sizeof(moved[0])));
    std::wcout << L"First candidate: " << first << L"; next page: " << nextPage
               << L"; after right keys: " << moved << L"\n";
    if (!*first || !*nextPage || !*moved || std::wstring(first) == nextPage ||
        std::wstring(nextPage) != moved) {
      std::cerr << "Horizontal navigation did not select the first candidate on the next page.\n";
      DestroyWindow(window);
      CoUninitialize();
      return 1;
    }
    std::cout << "PASS: " << pageSize << " right keys select the first candidate on the next page.\n";
  }
  if (testMouseCaret) {
    // Diagnostic only: inspect how a standard Edit host reacts to a real mouse
    // click inside its inline preedit. Do not treat unsupported hosts as pass.
    SetWindowTextW(edit, L"");
    for (const WORD key : {WORD('N'), WORD('I'), WORD('H'), WORD('A'), WORD('O')}) {
      if (!SendKey(key)) {
        DestroyWindow(window);
        CoUninitialize();
        return 1;
      }
      PumpFor(250);
    }
    PumpFor(1000);
    wchar_t preedit[256]{};
    GetWindowTextW(edit, preedit, static_cast<int>(sizeof(preedit) / sizeof(preedit[0])));
    POINT firstPoint{};
    POINT secondPoint{};
    LRESULT first = -1;
    LRESULT second = -1;
    if (richEdit) {
      POINTL position0{};
      POINTL position1{};
      first = SendMessageW(edit, EM_POSFROMCHAR, reinterpret_cast<WPARAM>(&position0), 0);
      second = SendMessageW(edit, EM_POSFROMCHAR, reinterpret_cast<WPARAM>(&position1), 1);
      firstPoint = {position0.x, position0.y};
      secondPoint = {position1.x, position1.y};
    } else {
      first = SendMessageW(edit, EM_POSFROMCHAR, 0, 0);
      second = SendMessageW(edit, EM_POSFROMCHAR, 1, 0);
      firstPoint = {GET_X_LPARAM(first), GET_Y_LPARAM(first)};
      secondPoint = {GET_X_LPARAM(second), GET_Y_LPARAM(second)};
    }
    if (!CaptureCandidate(window, window, L"mouse-caret-test-window"))
      std::cerr << "Could not capture the disposable mouse test window.\n";
    MouseTrackerRegistration mouseTracker;
    if (richEdit)
      AttachMouseTracker(mouseTracker.probe, &mouseTracker.tracker, &mouseTracker.cookie);
    CandidateRegionExperiment region;
    if (testRegion) {
      region.window = FindWindowW(L"chengjiangime_windows", L"chengjiangimecandwnd");
      RECT bounds{};
      if (region.window && GetWindowRect(region.window, &bounds) && bounds.bottom - bounds.top > 25) {
        HRGN cut = CreateRectRgn(0, 25, bounds.right - bounds.left, bounds.bottom - bounds.top);
        if (cut) {
          region.applied = SetWindowRgn(region.window, cut, TRUE) != 0;
          if (!region.applied)
            DeleteObject(cut);
        }
      }
      std::cout << "MOUSE_REGION_APPLIED: " << region.applied << "\n";
      PumpFor(500);
      if (!CaptureCandidate(window, window, L"mouse-caret-region-window"))
        std::cerr << "Could not capture the disposable region experiment.\n";
    }
    if (!*preedit || first == -1 || second == -1) {
      std::cout << "MOUSE_CARET: inconclusive; inline preedit positions unavailable"
                << " (length=" << std::wcslen(preedit) << ", first=" << first
                << ", second=" << second << ").\n";
    } else {
      POINT point{secondPoint.x + 1, firstPoint.y + 6};
      POINTL richPoint{point.x, point.y};
      const LRESULT target = richEdit
                                 ? SendMessageW(edit, EM_CHARFROMPOS, 0, reinterpret_cast<LPARAM>(&richPoint))
                                 : LOWORD(SendMessageW(edit, EM_CHARFROMPOS, 0, MAKELPARAM(point.x, point.y)));
      std::cout << "MOUSE_CARET_TARGET: first=" << firstPoint.x << ',' << firstPoint.y
                << " second=" << secondPoint.x << ',' << secondPoint.y << " target="
                << point.x << ',' << point.y << " nearest=" << target << "\n";
      ClientToScreen(edit, &point);
      HWND hit = WindowFromPoint(point);
      wchar_t hitClass[128]{};
      if (hit)
        GetClassNameW(hit, hitClass, static_cast<int>(sizeof(hitClass) / sizeof(hitClass[0])));
      std::cout << "MOUSE_CARET_WINDOW: screen=" << point.x << ',' << point.y
                << " is_edit=" << (hit == edit) << " class_codepoints=";
      for (const wchar_t *p = hitClass; *p; ++p)
        std::cout << std::hex << static_cast<unsigned int>(*p) << ',';
      std::cout << std::dec << "\n";
      if (!SetCursorPos(point.x, point.y)) {
        std::cout << "MOUSE_CARET: inconclusive; could not move test pointer.\n";
      } else {
        INPUT click[2]{};
        click[0].type = INPUT_MOUSE;
        click[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
        click[1] = click[0];
        click[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        if (SendInput(2, click, sizeof(INPUT)) != 2) {
          mouseTracker.Detach();
          DestroyWindow(window);
          CoUninitialize();
          return 1;
        }
        PumpFor(500);
        std::cout << "MOUSE_TRACKER_COUNT: " << mouseTracker.probe->events << "\n";
        DWORD selectionStart = 0;
        DWORD selectionEnd = 0;
        SendMessageW(edit, EM_GETSEL, reinterpret_cast<WPARAM>(&selectionStart),
                     reinterpret_cast<LPARAM>(&selectionEnd));
        wchar_t clicked[256]{};
        GetWindowTextW(edit, clicked, static_cast<int>(sizeof(clicked) / sizeof(clicked[0])));
        if (!SendKey(WORD('X'))) {
          mouseTracker.Detach();
          DestroyWindow(window);
          CoUninitialize();
          return 1;
        }
        PumpFor(500);
        if (!SendKey(VK_RETURN)) {
          mouseTracker.Detach();
          DestroyWindow(window);
          CoUninitialize();
          return 1;
        }
        PumpFor(1000);
        wchar_t result[256]{};
        GetWindowTextW(edit, result, static_cast<int>(sizeof(result) / sizeof(result[0])));
        std::cout << "MOUSE_CARET: before=";
        for (const wchar_t *p = preedit; *p; ++p)
          std::cout << std::hex << static_cast<unsigned int>(*p) << ',';
        std::cout << " after_click=";
        for (const wchar_t *p = clicked; *p; ++p)
          std::cout << std::hex << static_cast<unsigned int>(*p) << ',';
        std::cout << std::dec << " selection=" << selectionStart << ':' << selectionEnd;
        std::cout << " after=";
        for (const wchar_t *p = result; *p; ++p)
          std::cout << std::hex << static_cast<unsigned int>(*p) << ',';
        std::cout << std::dec << " (UTF-16 code units)\n";
      }
    }
    if (richEdit) {
      // The pass-through experiment must not make actual candidate rows
      // unclickable. Use the default vertical skin in the disposable desktop.
      mouseTracker.Detach();
      if (region.applied && IsWindow(region.window)) {
        SetWindowRgn(region.window, nullptr, TRUE);
        region.applied = false;
      }
      SetWindowTextW(edit, L"");
      for (const WORD key : {WORD('N'), WORD('I'), WORD('H'), WORD('A'), WORD('O')}) {
        if (!SendKey(key)) {
          mouseTracker.Detach();
          DestroyWindow(window);
          CoUninitialize();
          return 1;
        }
        PumpFor(250);
      }
      PumpFor(1000);
      const HWND cardWindow = FindWindowW(L"chengjiangime_windows", L"chengjiangimecandwnd");
      RECT cardBounds{};
      if (!cardWindow || !GetWindowRect(cardWindow, &cardBounds) ||
          !SetCursorPos(cardBounds.left + 60, cardBounds.top + 69)) {
        std::cerr << "Could not target a candidate row.\n";
        mouseTracker.Detach();
        DestroyWindow(window);
        CoUninitialize();
        return 1;
      }
      INPUT click[2]{};
      click[0].type = INPUT_MOUSE;
      click[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
      click[1] = click[0];
      click[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
      if (SendInput(2, click, sizeof(INPUT)) != 2) {
        mouseTracker.Detach();
        DestroyWindow(window);
        CoUninitialize();
        return 1;
      }
      PumpFor(1000);
      wchar_t clickedCandidate[256]{};
      GetWindowTextW(edit, clickedCandidate,
                     static_cast<int>(sizeof(clickedCandidate) / sizeof(clickedCandidate[0])));
      bool committed = false;
      for (const wchar_t *p = clickedCandidate; *p; ++p)
        committed = committed || (*p >= 0x4e00 && *p <= 0x9fff);
      if (!committed) {
        std::cerr << "Clicking the first candidate did not commit Chinese text.\n";
        mouseTracker.Detach();
        DestroyWindow(window);
        CoUninitialize();
        return 1;
      }
      std::cout << "PASS: clicking a candidate row still commits text.\n";
    }
  }
  DestroyWindow(window);
  CoUninitialize();
  std::cout << "PASS: personal TSF committed Chinese text in a focused Edit "
               "control.\n";
  return 0;
}
