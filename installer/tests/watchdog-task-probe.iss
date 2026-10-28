[Setup]
AppId=ChengjiangWatchdogTaskProbe
AppName=Chengjiang watchdog task probe
AppVersion=1
DefaultDirName={localappdata}\ChengjiangWatchdogTaskProbe
PrivilegesRequired=admin
CreateUninstallRegKey=no
Uninstallable=no
OutputBaseFilename=watchdog-task-probe
Compression=none

[Code]
#include "../personal_watchdog_task.iss"

function InitializeSetup: Boolean;
var
  Value: String;
begin
  if RegisterPersonalWatchdogTask(ExpandConstant('{param:SID|}'), ExpandConstant('{param:TASK|}'),
    ExpandConstant('{sys}\notepad.exe')) then
    Value := 'registered'
  else
    Value := 'failed';
  if not SaveStringToFile(ExpandConstant('{param:RESULT|}'), Value, False) then
    RaiseException('Cannot write probe result');
  Result := False;
end;
