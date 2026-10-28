// Read-only lookup of the account owning the shell on this desktop. Failure is
// intentionally distinct from the elevated account: callers must not guess.
function PersonalGetShellWindow: HWND;
  external 'GetShellWindow@user32.dll stdcall';
function PersonalGetWindowThreadProcessId(Window: HWND; var ProcessId: Cardinal): Cardinal;
  external 'GetWindowThreadProcessId@user32.dll stdcall';
function PersonalGetCurrentProcessId: Cardinal;
  external 'GetCurrentProcessId@kernel32.dll stdcall';

var
  PersonalInteractiveSid: String;
  PersonalInteractiveLocalData: String;
  PersonalUninstallSameUser: Boolean;

function ProcessUserSid(ProcessId: Cardinal; var Sid: String): Boolean;
var
  Locator: Variant;
  Service: Variant;
  ResultObject: Variant;
begin
  Result := False;
  Sid := '';
  if ProcessId = 0 then
    exit;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\cimv2');
    ResultObject := Service.ExecMethod('Win32_Process.Handle="' + IntToStr(ProcessId) + '"', 'GetOwnerSid');
    if ResultObject.ReturnValue <> 0 then
      exit;
    Sid := ResultObject.Sid;
  except
    exit;
  end;
  if (Copy(Sid, 1, 4) <> 'S-1-') or (Length(Sid) > 184) then
    exit;
  Result := True;
end;

function InteractiveUserInfo(var Sid, LocalData: String): Boolean;
var
  Shell: HWND;
  ProcessId: Cardinal;
  ProfilePath: String;
  RawLocalData: String;
begin
  Result := False;
  Sid := '';
  LocalData := '';
  Shell := PersonalGetShellWindow;
  if Shell = 0 then
    exit;
  ProcessId := 0;
  PersonalGetWindowThreadProcessId(Shell, ProcessId);
  if not ProcessUserSid(ProcessId, Sid) then
    exit;
  ProfilePath := '';
  if not RegQueryStringValue(HKLM, 'Software\Microsoft\Windows NT\CurrentVersion\ProfileList\' + Sid,
    'ProfileImagePath', ProfilePath) then
    exit;
  RawLocalData := '';
  if not RegQueryStringValue(HKU, Sid + '\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
    'Local AppData', RawLocalData) then
    exit;
  StringChangeEx(RawLocalData, '%USERPROFILE%', ProfilePath, True);
  if (Trim(RawLocalData) = '') or (Pos('%', RawLocalData) <> 0) then
    exit;
  LocalData := RemoveBackslashUnlessRoot(ExpandFileName(RawLocalData));
  Result := True;
end;
