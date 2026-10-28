// Grant only the identified desktop account, rather than every local user,
// access to the data copied by elevated Setup. Existing inherited permissions
// are preserved; a user-selected shared directory can still be shared.
function PersonalGrantDataAccess(const Path, Sid: String): Boolean;
var
  Index: Integer;
  ResultCode: Integer;
begin
  Result := False;
  if (Trim(Path) = '') or (Pos('"', Path) <> 0) or
    (Copy(Sid, 1, 4) <> 'S-1-') or (Length(Sid) > 184) then
    exit;
  for Index := 5 to Length(Sid) do
    if ((Sid[Index] < '0') or (Sid[Index] > '9')) and (Sid[Index] <> '-') then
      exit;
  ResultCode := -1;
  if not Exec(ExpandConstant('{sys}\icacls.exe'),
    '"' + Path + '" /grant *' + Sid + ':(OI)(CI)M /T /C /Q', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
    exit;
  ResultCode := -1;
  Result := Exec(ExpandConstant('{sys}\icacls.exe'),
    '"' + Path + '" /setintegritylevel (OI)(CI)M /T /C /Q', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;
