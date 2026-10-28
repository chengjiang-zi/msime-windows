#include <Windows.h>
#include <userenv.h>

#include <iostream>
#include <string>
#include <vector>

namespace {
std::wstring Environment(const wchar_t *name) {
  DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0)
    return {};
  std::vector<wchar_t> value(size);
  const DWORD written = GetEnvironmentVariableW(name, value.data(), size);
  return written > 0 && written < size ? std::wstring(value.data(), written)
                                       : std::wstring{};
}

int Fail(const char *stage) {
  std::cerr << stage << " failed with Windows error " << GetLastError() << "\n";
  return 1;
}

bool EnableImpersonationPrivilege() {
  HANDLE self = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &self))
    return false;
  TOKEN_PRIVILEGES privileges{};
  privileges.PrivilegeCount = 1;
  const BOOL found = LookupPrivilegeValueW(nullptr, SE_IMPERSONATE_NAME,
                                           &privileges.Privileges[0].Luid);
  privileges.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
  SetLastError(ERROR_SUCCESS);
  const BOOL adjusted =
      found && AdjustTokenPrivileges(self, FALSE, &privileges,
                                     sizeof(privileges), nullptr, nullptr);
  const DWORD status = GetLastError();
  CloseHandle(self);
  SetLastError(status);
  return adjusted && status == ERROR_SUCCESS;
}
} // namespace

// CI-only: create a process using a temporary standard user's token in the
// runner's existing desktop session. Passwords come from the process
// environment, never command-line arguments or output.
int wmain(int argc, wchar_t **argv) {
  if (Environment(L"GITHUB_ACTIONS") != L"true" ||
      Environment(L"RUNNER_ENVIRONMENT") != L"github-hosted" ||
      Environment(L"RUNNER_OS") != L"Windows" || argc < 2) {
    std::cerr << "This probe is restricted to a disposable GitHub-hosted "
                 "Windows runner.\n";
    return 1;
  }
  std::wstring user = Environment(L"CHENGJIANG_TEST_USERNAME");
  std::wstring password = Environment(L"CHENGJIANG_TEST_PASSWORD");
  if (user.empty() || password.empty())
    return 1;
  if (!EnableImpersonationPrivilege())
    return Fail("Enable SeImpersonatePrivilege");
  HANDLE token = nullptr;
  const BOOL loggedOn =
      LogonUserW(user.c_str(), L".", password.c_str(),
                 LOGON32_LOGON_INTERACTIVE, LOGON32_PROVIDER_DEFAULT, &token);
  SecureZeroMemory(password.data(), password.size() * sizeof(wchar_t));
  if (!loggedOn)
    return Fail("LogonUserW");
  DWORD bytes = 0;
  TOKEN_ELEVATION elevation{};
  if (!GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                           &bytes) ||
      elevation.TokenIsElevated) {
    std::cerr << "Temporary standard-user token is elevated.\n";
    CloseHandle(token);
    return 1;
  }
  BYTE adminBuffer[SECURITY_MAX_SID_SIZE]{};
  DWORD adminBytes = sizeof(adminBuffer);
  if (!CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, adminBuffer, &adminBytes)) return Fail("Create admin SID");
  HANDLE impersonation = nullptr;
  if (!DuplicateToken(token, SecurityIdentification, &impersonation)) return Fail("Duplicate token");
  BOOL isAdmin = TRUE;
  const BOOL checked = CheckTokenMembership(impersonation, adminBuffer, &isAdmin);
  CloseHandle(impersonation);
  if (!checked || isAdmin) {
    std::cerr << "Temporary account has administrator membership.\n";
    CloseHandle(token);
    return 1;
  }
  std::cout << "PASS: temporary user is non-elevated and not an administrator.\n";
  HANDLE primary = nullptr;
  if (!DuplicateTokenEx(token, MAXIMUM_ALLOWED, nullptr, SecurityIdentification,
                        TokenPrimary, &primary)) {
    const DWORD error = GetLastError();
    CloseHandle(token);
    SetLastError(error);
    return Fail("DuplicateTokenEx");
  }
  CloseHandle(token);
  token = primary;
  std::wstring command;
  for (int index = 1; index < argc; ++index) {
    const std::wstring value = argv[index];
    if (value.find(L'"') != std::wstring::npos ||
        (!value.empty() && value.back() == L'\\')) {
      std::cerr << "Unsupported quoted or trailing-backslash argument.\n";
      CloseHandle(token);
      return 1;
    }
    if (!command.empty())
      command += L' ';
    command += L'"' + value + L'"';
  }
  LPVOID environment = nullptr;
  if (!CreateEnvironmentBlock(&environment, token, FALSE)) {
    CloseHandle(token);
    return Fail("CreateEnvironmentBlock");
  }
  STARTUPINFOW startup{sizeof(startup)};
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process{};
  const BOOL started = CreateProcessWithTokenW(
      token, LOGON_WITH_PROFILE, argv[1], command.data(),
      CREATE_UNICODE_ENVIRONMENT, environment, nullptr, &startup, &process);
  const DWORD startError = started ? ERROR_SUCCESS : GetLastError();
  DestroyEnvironmentBlock(environment);
  CloseHandle(token);
  if (!started) {
    SetLastError(startError);
    return Fail("CreateProcessWithTokenW");
  }
  CloseHandle(process.hThread);
  const DWORD wait = WaitForSingleObject(process.hProcess, 360000);
  if (wait != WAIT_OBJECT_0) {
    TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hProcess);
    std::cerr << "Standard user desktop process timed out.\n";
    return 1;
  }
  DWORD exitCode = 1;
  GetExitCodeProcess(process.hProcess, &exitCode);
  CloseHandle(process.hProcess);
  std::cout << "Standard user process exited: " << exitCode << "\n";
  return static_cast<int>(exitCode);
}
