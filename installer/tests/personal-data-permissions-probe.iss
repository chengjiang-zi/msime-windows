[Setup]
AppName=Chengjiang data permission probe
AppVersion=1
DefaultDirName={tmp}\chengjiang-data-permissions-probe
PrivilegesRequired=admin
CreateAppDir=no
Uninstallable=no
OutputBaseFilename=personal-data-permissions-probe

[Code]
#include "..\personal_data_permissions.iss"

function InitializeSetup: Boolean;
var
  Value: String;
begin
  Value := 'failed';
  if PersonalGrantDataAccess(ExpandConstant('{param:DATA|}'), ExpandConstant('{param:SID|}')) then
    Value := 'granted';
  if not SaveStringToFile(ExpandConstant('{param:RESULT|}'), Value, False) then
    RaiseException('Cannot write permission probe result.');
  Result := False;
end;
