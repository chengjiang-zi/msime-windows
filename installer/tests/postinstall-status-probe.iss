[Setup]
AppName=Chengjiang Postinstall Status Probe
AppVersion=1
DefaultDirName={tmp}\chengjiang-postinstall-probe
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputBaseFilename=postinstall-status-probe

[Code]
#include "..\personal_postinstall_status.iss"

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    PersonalPostInstallStarted := True;
    if Pos('/FAILPOSTINSTALL', Uppercase(GetCmdTail)) > 0 then
      RaiseException('Intentional post-install failure for the disposable-runner test.');
    PersonalPostInstallCompleted := True;
  end;
end;
