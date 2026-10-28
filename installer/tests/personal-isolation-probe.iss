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
#include "../interactive_user.iss"
#include "../personal_isolation.iss"

function InitializeSetup: Boolean;
var
  Value: String;
begin
  if not InteractiveUserInfo(PersonalInteractiveSid, PersonalInteractiveLocalData) then
    Value := 'blocked'
  else
  begin
    if ExpandConstant('{param:INTERACTIVELOCAL|}') <> '' then
      PersonalInteractiveLocalData := ExpandConstant('{param:INTERACTIVELOCAL|}');
    if OverlapsUpstreamData(ExpandConstant('{param:TARGET|}')) then
      Value := 'blocked'
    else
      Value := 'allowed';
  end;
  if not SaveStringToFile(ExpandConstant('{param:RESULT|}'), Value, False) then
    RaiseException('Cannot write probe result');
  { Exit before installation: this probe only exercises the shared path policy. }
  Result := False;
end;
