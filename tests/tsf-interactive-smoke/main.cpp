#include <Windows.h>
#include <msctf.h>

#include <chrono>
#include <iostream>
#include <string>
#include <thread>

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
} // namespace

int main() {
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)))
    return 1;
  HWND window = CreateWindowExW(0, L"STATIC", L"Personal IME interactive smoke",
                                WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT,
                                CW_USEDEFAULT, 640, 300, nullptr, nullptr,
                                GetModuleHandleW(nullptr), nullptr);
  HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
                              WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_MULTILINE,
                              10, 10, 600, 220, window, nullptr,
                              GetModuleHandleW(nullptr), nullptr);
  if (!window || !edit) {
    std::cerr << "Could not create the disposable test window.\n";
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
  DestroyWindow(window);
  CoUninitialize();
  if (!hasCjk) {
    std::cerr << "No Chinese text was committed.\n";
    return 1;
  }
  std::cout << "PASS: personal TSF committed Chinese text in a focused Edit "
               "control.\n";
  return 0;
}
