[Setup]
AppId=ChengjiangInteractiveUserProbe
AppName=Chengjiang interactive user probe
AppVersion=1
DefaultDirName={localappdata}\ChengjiangInteractiveUserProbe
PrivilegesRequired=lowest
CreateUninstallRegKey=no
Uninstallable=no
OutputBaseFilename=interactive-user-probe
Compression=none

[Code]
#include "../interactive_user.iss"

function InitializeSetup: Boolean;
var
  Sid: String;
  LocalData: String;
  Lines: TArrayOfString;
begin
  SetArrayLength(Lines, 2);
  if InteractiveUserInfo(Sid, LocalData) then
  begin
    Lines[0] := Sid;
    Lines[1] := LocalData;
  end
  else
  begin
    Lines[0] := 'unavailable';
    Lines[1] := '';
  end;
  if not SaveStringsToFile(ExpandConstant('{param:RESULT|}'), Lines, False) then
    RaiseException('Cannot write probe result');
  Result := False;
end;
