// Shared by the installer and isolated regression probe.
function IsPathInside(const Child, Parent: String): Boolean;
begin
  Result :=
    (CompareText(Child, Parent) = 0) or
    (CompareText(
       Copy(AddBackslash(Child), 1, Length(AddBackslash(Parent))),
       AddBackslash(Parent)) = 0);
end;

function PersonalGetFileAttributes(const FileName: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function PersonalQueryDosDevice(const DeviceName, TargetPath: String;
  MaxChars: Cardinal): Cardinal;
  external 'QueryDosDeviceW@kernel32.dll stdcall';

{ Only accept ordinary local volumes and long paths. SUBST, network mappings,
  short DOS names and device paths can otherwise disguise an overlapping path. }
function HasUnsafePathAlias(const Directory: String): Boolean;
var
  Target: String;
begin
  Result := True;
  if (Length(Directory) < 3) or (Directory[2] <> ':') or
     (Directory[3] <> '\') or (Pos('~', Directory) <> 0) then
    exit;
  SetLength(Target, 1024);
  if PersonalQueryDosDevice(Copy(Directory, 1, 2), Target, Length(Target)) = 0 then
    exit;
  if CompareText(Copy(Target, 1, 22), '\Device\HarddiskVolume') <> 0 then
    exit;
  Result := False;
end;

{ Distinct drive letters can name the same volume; compare the underlying
  device name as well as the path below that volume. }
function VolumePath(const Directory: String): String;
var
  Target: String;
  Size: Cardinal;
  Terminator: Integer;
begin
  SetLength(Target, 1024);
  Size := PersonalQueryDosDevice(Copy(Directory, 1, 2), Target, Length(Target));
  if Size = 0 then
    RaiseException('Cannot resolve data directory volume');
  Terminator := Pos(#0, Target);
  if Terminator > 0 then
    SetLength(Target, Terminator - 1);
  Result := Target + Copy(Directory, 3, Length(Directory));
end;

{ A junction or symbolic-link ancestor can make unrelated-looking paths point
  to the same directory. Until we support resolving those aliases reliably,
  reject paths that pass through a reparse point rather than risking deletion. }
function HasReparsePointAncestor(const Directory: String): Boolean;
var
  Current: String;
  Parent: String;
  Attributes: Cardinal;
begin
  Result := True;
  if Trim(Directory) = '' then
    exit;
  Current := RemoveBackslashUnlessRoot(ExpandFileName(Directory));
  while Current <> '' do
  begin
    Attributes := PersonalGetFileAttributes(Current);
    if (Attributes <> $FFFFFFFF) and ((Attributes and $400) <> 0) then
      exit;
    Parent := RemoveBackslashUnlessRoot(ExtractFileDir(Current));
    if (Parent = '') or (CompareText(Parent, Current) = 0) then
      break;
    Current := Parent;
  end;
  Result := False;
end;

{ Protect both the original default and any original custom data directory.
  This only reads the upstream registry; it never migrates or adopts that data. }
function OverlapsUpstreamData(const Directory: String): Boolean;
var
  Candidate: String;
  Upstream: array[0..7] of String;
  Index: Integer;
begin
  Result := True;
  if Trim(Directory) = '' then
    exit;
  Candidate := RemoveBackslashUnlessRoot(ExpandFileName(Directory));
  if HasUnsafePathAlias(Candidate) or HasReparsePointAncestor(Candidate) then
    exit;
  Upstream[0] := ExpandConstant('{localappdata}\metasequoiaime');
  Upstream[1] := '';
  RegQueryStringValue(HKLM, 'Software\Metasequoia\MetasequoiaIME', 'DataDir', Upstream[1]);
  Upstream[2] := Trim(ExpandConstant('{%METASEQUOIA_IME_DATA_DIR|}'));
  Upstream[3] := ExpandConstant('{commonpf64}\metasequoiaime');
  Upstream[4] := ExpandConstant('{commonpf32}\metasequoiaime');
  Upstream[5] := ExpandConstant('{commonappdata}\metasequoiaime');
  Upstream[6] := ExpandConstant('{sys}\IME\MetasequoiaIME');
  Upstream[7] := ExpandConstant('{syswow64}\IME\MetasequoiaIME');
  for Index := 0 to 7 do
    if Trim(Upstream[Index]) <> '' then
    begin
      Upstream[Index] := RemoveBackslashUnlessRoot(ExpandFileName(Upstream[Index]));
      if HasUnsafePathAlias(Upstream[Index]) or HasReparsePointAncestor(Upstream[Index]) then
        exit;
      if IsPathInside(VolumePath(Candidate), VolumePath(Upstream[Index])) or
         IsPathInside(VolumePath(Upstream[Index]), VolumePath(Candidate)) then
        exit;
    end;
  Result := False;
end;
