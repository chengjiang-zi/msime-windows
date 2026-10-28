#include <Windows.h>
#include <wincrypt.h>

#include <string>

namespace {
void Log(HANDLE file, const char *line) {
  DWORD written = 0;
  WriteFile(file, line, static_cast<DWORD>(std::char_traits<char>::length(line)), &written, nullptr);
}
bool Launch(const wchar_t *program, const wchar_t *argument, HANDLE log, PROCESS_INFORMATION *process) {
  std::wstring command = L"\"" + std::wstring(program) + L"\"";
  if (argument && *argument) command += L" " + std::wstring(argument);
  const std::wstring path = program;
  const auto separator = path.find_last_of(L"\\/");
  const std::wstring directory = separator == std::wstring::npos ? L"" : path.substr(0, separator);
  STARTUPINFOW startup{sizeof(startup)};
  startup.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  startup.wShowWindow = SW_HIDE;
  startup.hStdInput = startup.hStdOutput = startup.hStdError = log;
  return CreateProcessW(program, command.data(), nullptr, nullptr, TRUE, 0, nullptr,
                        directory.empty() ? nullptr : directory.c_str(), &startup, process) != FALSE;
}
bool WaitSuccess(PROCESS_INFORMATION &process, DWORD timeout) {
  const DWORD wait = WaitForSingleObject(process.hProcess, timeout);
  DWORD code = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &code);
  else TerminateProcess(process.hProcess, 1);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return wait == WAIT_OBJECT_0 && code == 0;
}
bool UserStoreIsClear(const wchar_t *storeName, const wchar_t *expected) {
  HCERTSTORE store = CertOpenStore(CERT_STORE_PROV_SYSTEM_W, 0, 0, CERT_SYSTEM_STORE_CURRENT_USER, storeName);
  if (!store) return false;
  static constexpr wchar_t hex[] = L"0123456789ABCDEF";
  PCCERT_CONTEXT cert = nullptr;
  bool clear = true;
  while ((cert = CertEnumCertificatesInStore(store, cert)) != nullptr) {
    BYTE digest[20]{};
    DWORD size = sizeof(digest);
    if (!CertGetCertificateContextProperty(cert, CERT_HASH_PROP_ID, digest, &size) || size != sizeof(digest)) {
      clear = false;
      break;
    }
    std::wstring actual;
    for (BYTE byte : digest) { actual += hex[byte >> 4]; actual += hex[byte & 15]; }
    if (actual == expected) { clear = false; break; }
  }
  if (cert) CertFreeCertificateContext(cert);
  CertCloseStore(store, 0);
  return clear;
}
}

int wmain(int argc, wchar_t **argv) {
  if (argc != 6) return 1;
  SECURITY_ATTRIBUTES attributes{sizeof(attributes), nullptr, TRUE};
  HANDLE log = CreateFileW(argv[4], GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &attributes,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (log == INVALID_HANDLE_VALUE) return 1;
  Log(log, "STAGE: native standard-user probe started\r\n");
  if (!UserStoreIsClear(L"Root", argv[5]) || !UserStoreIsClear(L"TrustedPublisher", argv[5])) {
    Log(log, "ERROR: user certificate store could not be verified or contained the test certificate\r\n");
    CloseHandle(log);
    return 1;
  }
  Log(log, "STAGE: user trust stores checked\r\n");
  PROCESS_INFORMATION registration{};
  if (!Launch(argv[1], L"--register-profile", log, &registration) || !WaitSuccess(registration, 45000)) {
    Log(log, "ERROR: standard-user profile registration failed or timed out\r\n");
    CloseHandle(log);
    return 1;
  }
  Log(log, "STAGE: profile registered\r\n");
  PROCESS_INFORMATION server{};
  if (!Launch(argv[2], L"--watchdog-managed", log, &server)) {
    Log(log, "ERROR: standard-user server did not start\r\n");
    CloseHandle(log);
    return 1;
  }
  CloseHandle(server.hThread);
  Sleep(3000);
  if (WaitForSingleObject(server.hProcess, 0) != WAIT_TIMEOUT) {
    Log(log, "ERROR: standard-user server exited\r\n");
    CloseHandle(server.hProcess);
    CloseHandle(log);
    return 1;
  }
  Log(log, "STAGE: server started\r\n");
  PROCESS_INFORMATION smoke{};
  const bool launched = Launch(argv[3], nullptr, log, &smoke);
  const bool passed = launched && WaitSuccess(smoke, 90000);
  TerminateProcess(server.hProcess, 0);
  CloseHandle(server.hProcess);
  Log(log, passed ? "STAGE: input probe exited successfully\r\n" : "ERROR: input probe failed or timed out\r\n");
  CloseHandle(log);
  return passed ? 0 : 1;
}
