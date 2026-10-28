// Uses the Windows ScheduledTasks module to register an interactive-token
// task without retaining any account password. The helper is extracted to
// Setup's protected temporary directory and receives only validated values.
function RegisterPersonalWatchdogTask(const Sid, TaskName, Executable: String): Boolean;
var
  Index: Integer;
  ResultCode: Integer;
  Params: String;
begin
  Result := False;
  if (Copy(Sid, 1, 4) <> 'S-1-') or (Length(Sid) > 184) or
     (Trim(TaskName) = '') or (Pos('"', TaskName) <> 0) or
     (Trim(Executable) = '') or (Pos('"', Executable) <> 0) then
    exit;
  for Index := 5 to Length(Sid) do
    if ((Sid[Index] < '0') or (Sid[Index] > '9')) and (Sid[Index] <> '-') then
      exit;
  ExtractTemporaryFile('register-personal-watchdog.ps1');
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\register-personal-watchdog.ps1') + '" -UserSid "' + Sid +
    '" -TaskName "' + TaskName + '" -Executable "' + Executable + '"';
  ResultCode := -1;
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params,
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then
    Log('Could not register the personal watchdog task; helper exit code: ' + IntToStr(ResultCode));
end;
