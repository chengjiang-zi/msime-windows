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
  Stage: String;
begin
  Result := False;
  if (Copy(Sid, 1, 4) <> 'S-1-') or (Trim(TaskName) = '') or (Trim(Executable) = '') then
    exit;
  try
    Stage := 'create scheduler';
    Service := CreateOleObject('Schedule.Service');
    Stage := 'connect';
    Service.Connect;
    Stage := 'open root';
    Folder := Service.GetFolder('\');
    Stage := 'create definition';
    Definition := Service.NewTask(0);
    Stage := 'set principal';
    Principal := Definition.Principal;
    Principal.UserId := Sid;
    Principal.LogonType := 3; { TASK_LOGON_INTERACTIVE_TOKEN }
    Principal.RunLevel := 0; { TASK_RUNLEVEL_LUA }
    Stage := 'set settings';
    Settings := Definition.Settings;
    Settings.Enabled := True;
    Settings.StartWhenAvailable := True;
    Stage := 'set trigger';
    Trigger := Definition.Triggers.Create(9); { TASK_TRIGGER_LOGON }
    Trigger.UserId := Sid;
    Trigger.Enabled := True;
    Stage := 'set action';
    Action := Definition.Actions.Create(0); { TASK_ACTION_EXEC }
    Action.Path := Executable;
    Stage := 'register task';
    Registered := Folder.RegisterTask(TaskName, Definition.XmlText, 6, Sid, '', 3);
    Result := not VarIsNull(Registered);
  except
    Log('Could not register the personal watchdog task at ' + Stage + ': ' + GetExceptionMessage);
  end;
end;
