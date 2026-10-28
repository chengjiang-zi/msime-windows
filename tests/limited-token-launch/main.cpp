#include <Windows.h>

#include <iostream>
#include <string>
#include <vector>

namespace {
int Fail(const char *stage) {
  std::cerr << stage << " failed with Windows error " << GetLastError() << '\n';
  return 1;
}
bool HostedRunner() {
  wchar_t value[64]{};
  if (!GetEnvironmentVariableW(L"GITHUB_ACTIONS", value, 64) || std::wstring(value) != L"true") return false;
  if (!GetEnvironmentVariableW(L"RUNNER_ENVIRONMENT", value, 64) || std::wstring(value) != L"github-hosted") return false;
  return GetEnvironmentVariableW(L"RUNNER_OS", value, 64) && std::wstring(value) == L"Windows";
}
}

// CI-only: same desktop SID, but deny Administrators and lower the integrity
// level. This approximates a limited token; it is not a separate standard user.
int wmain(int argc, wchar_t **argv) {
  if (!HostedRunner() || argc < 4) return 1;
  const bool detach = std::wstring(argv[1]) == L"--detach";
  if (!detach && std::wstring(argv[1]) != L"--wait") return 1;
  HANDLE source = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY |
                        TOKEN_ADJUST_DEFAULT | TOKEN_ADJUST_PRIVILEGES, &source))
    return Fail("OpenProcessToken");
  TOKEN_PRIVILEGES privilege{};
  privilege.PrivilegeCount = 1;
  if (!LookupPrivilegeValueW(nullptr, SE_IMPERSONATE_NAME, &privilege.Privileges[0].Luid)) return Fail("LookupPrivilegeValue");
  privilege.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
  SetLastError(ERROR_SUCCESS);
  if (!AdjustTokenPrivileges(source, FALSE, &privilege, 0, nullptr, nullptr) || GetLastError() != ERROR_SUCCESS)
    return Fail("AdjustTokenPrivileges");
  BYTE adminBuffer[SECURITY_MAX_SID_SIZE]{};
  DWORD adminBytes = sizeof(adminBuffer);
  if (!CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr, adminBuffer, &adminBytes)) return Fail("Create admin SID");
  SID_AND_ATTRIBUTES disabled{adminBuffer, 0};
  HANDLE limited = nullptr;
  if (!CreateRestrictedToken(source, DISABLE_MAX_PRIVILEGE, 1, &disabled, 0, nullptr, 0, nullptr, &limited))
    return Fail("CreateRestrictedToken");
  CloseHandle(source);
  BYTE mediumBuffer[SECURITY_MAX_SID_SIZE]{};
  DWORD mediumBytes = sizeof(mediumBuffer);
  if (!CreateWellKnownSid(WinMediumLabelSid, nullptr, mediumBuffer, &mediumBytes)) return Fail("Create medium SID");
  TOKEN_MANDATORY_LABEL label{};
  label.Label.Sid = mediumBuffer;
  label.Label.Attributes = SE_GROUP_INTEGRITY;
  if (!SetTokenInformation(limited, TokenIntegrityLevel, &label,
                           sizeof(label) + GetLengthSid(mediumBuffer))) return Fail("Set medium integrity");
  DWORD labelBytes = 0;
  GetTokenInformation(limited, TokenIntegrityLevel, nullptr, 0, &labelBytes);
  std::vector<BYTE> labelData(labelBytes);
  if (!labelBytes || !GetTokenInformation(limited, TokenIntegrityLevel, labelData.data(), labelBytes, &labelBytes))
    return Fail("Query integrity");
  const auto *actualLabel = reinterpret_cast<const TOKEN_MANDATORY_LABEL *>(labelData.data());
  if (!EqualSid(actualLabel->Label.Sid, mediumBuffer)) {
    std::cerr << "Token integrity is not medium.\n";
    CloseHandle(limited);
    return 1;
  }
  TOKEN_ELEVATION elevation{};
  DWORD returned = 0;
  if (!GetTokenInformation(limited, TokenElevation, &elevation, sizeof(elevation), &returned)) return Fail("Query elevation");
  HANDLE impersonation = nullptr;
  if (!DuplicateToken(limited, SecurityIdentification, &impersonation)) return Fail("Duplicate impersonation token");
  BOOL adminEnabled = TRUE;
  const BOOL checked = CheckTokenMembership(impersonation, adminBuffer, &adminEnabled);
  CloseHandle(impersonation);
  if (!checked || adminEnabled) {
    std::cerr << "Restricted token still has enabled administrator membership.\n";
    CloseHandle(limited);
    return 1;
  }
  std::cout << "Restricted token: medium integrity, administrator group disabled, elevation flag="
            << elevation.TokenIsElevated << ".\n";
  std::wstring command;
  for (int index = 3; index < argc; ++index) {
    const std::wstring value = argv[index];
    if (value.find(L'"') != std::wstring::npos || (!value.empty() && value.back() == L'\\')) return 1;
    if (!command.empty()) command += L' ';
    command += L'"' + value + L'"';
  }
  STARTUPINFOW startup{sizeof(startup)};
  SECURITY_ATTRIBUTES attributes{sizeof(attributes), nullptr, TRUE};
  HANDLE nullStream = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  &attributes, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (nullStream == INVALID_HANDLE_VALUE) return Fail("Open standard stream");
  HANDLE output = CreateFileW(argv[2], GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                              &attributes, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output == INVALID_HANDLE_VALUE) return Fail("Open output log");
  startup.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  startup.wShowWindow = SW_HIDE;
  startup.hStdInput = nullStream;
  startup.hStdOutput = startup.hStdError = output;
  PROCESS_INFORMATION process{};
  const std::wstring program = argv[3];
  const auto separator = program.find_last_of(L"\\/");
  const std::wstring directory = separator == std::wstring::npos ? L"" : program.substr(0, separator);
  // A restricted version of the caller's primary token is eligible for
  // CreateProcessAsUser without assigning an unrelated user's token.
  const BOOL started = CreateProcessAsUserW(limited, argv[3], command.data(), nullptr, nullptr, TRUE,
                                             0, nullptr, directory.empty() ? nullptr : directory.c_str(), &startup, &process);
  const DWORD error = GetLastError();
  CloseHandle(nullStream);
  CloseHandle(output);
  CloseHandle(limited);
  if (!started) { SetLastError(error); return Fail("CreateProcessAsUserW"); }
  std::cout << "PASS: launched with a medium-integrity restricted token.\n";
  if (detach) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
  }
  const DWORD wait = WaitForSingleObject(process.hProcess, 360000);
  DWORD result = 1;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &result);
  else { TerminateProcess(process.hProcess, 1); std::cerr << "Limited probe timed out.\n"; }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return static_cast<int>(result);
}
