[Setup]
AppId=ChengjiangImeIsolationProbe
AppName=Chengjiang IME isolation probe
AppVersion=1
DefaultDirName={localappdata}\ChengjiangImeIsolationProbe
PrivilegesRequired=lowest
CreateUninstallRegKey=no
Uninstallable=no
OutputBaseFilename=personal-isolation-probe
Compression=none

[Code]
#include "../personal_isolation.iss"

function InitializeSetup: Boolean;
var
  Value: String;
begin
  if OverlapsUpstreamData(ExpandConstant('{param:TARGET|}')) then
    Value := 'blocked'
  else
    Value := 'allowed';
  if not SaveStringToFile(ExpandConstant('{param:RESULT|}'), Value, False) then
    RaiseException('Cannot write probe result');
  { Exit before installation: this probe only exercises the shared path policy. }
  Result := False;
end;
