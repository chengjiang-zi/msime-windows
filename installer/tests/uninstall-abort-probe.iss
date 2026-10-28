[Setup]
AppId=ChengjiangUninstallAbortProbe
AppName=Chengjiang uninstall abort probe
AppVersion=1
DefaultDirName={localappdata}\ChengjiangUninstallAbortProbe
PrivilegesRequired=lowest
CreateUninstallRegKey=no
OutputBaseFilename=uninstall-abort-probe
Compression=none

[Files]
Source: "uninstall-abort-probe-payload.txt"; DestDir: "{app}"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RaiseException('Intentional uninstall abort test');
end;
