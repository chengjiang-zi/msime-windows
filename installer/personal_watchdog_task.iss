// Register the fixed task for a specified interactive user, without a stored
// password. The caller must supply a validated SID belonging to the desktop.
function RegisterPersonalWatchdogTask(const Sid, TaskName, Executable: String): Boolean;
var
  Service: Variant;
  Folder: Variant;
  Definition: Variant;
  Principal: Variant;
  Settings: Variant;
  Trigger: Variant;
  Action: Variant;
  Registered: Variant;
begin
  Result := False;
  if (Copy(Sid, 1, 4) <> 'S-1-') or (Trim(TaskName) = '') or (Trim(Executable) = '') then
    exit;
  try
    Service := CreateOleObject('Schedule.Service');
    Service.Connect;
    Folder := Service.GetFolder('\');
    Definition := Service.NewTask(0);
    Principal := Definition.Principal;
    Principal.UserId := Sid;
    Principal.LogonType := 3; { TASK_LOGON_INTERACTIVE_TOKEN }
    Principal.RunLevel := 0; { TASK_RUNLEVEL_LUA }
    Settings := Definition.Settings;
    Settings.Enabled := True;
    Settings.StartWhenAvailable := True;
    Trigger := Definition.Triggers.Create(9); { TASK_TRIGGER_LOGON }
    Trigger.UserId := Sid;
    Trigger.Enabled := True;
    Action := Definition.Actions.Create(0); { TASK_ACTION_EXEC }
    Action.Path := Executable;
    Registered := Folder.RegisterTaskDefinition(TaskName, Definition, 6, Sid, Null, 3, Null);
    Result := not VarIsNull(Registered);
  except
    Log('Could not register the personal watchdog task: ' + GetExceptionMessage);
  end;
end;
