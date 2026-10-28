var
  PersonalPostInstallStarted: Boolean;
  PersonalPostInstallCompleted: Boolean;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and PersonalPostInstallStarted and (not PersonalPostInstallCompleted) then
  begin
    WizardForm.FinishedHeadingLabel.Caption := '个人版安装未完成';
    WizardForm.FinishedLabel.Caption :=
      '个人版未能完成安装。请检查前面的错误提示或安装日志，然后重新运行安装程序。';
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  { Inno continues to the finish page after a script exception in
    ssPostInstall. Do not report success to unattended callers in that case. }
  if PersonalPostInstallStarted and (not PersonalPostInstallCompleted) then
    Result := 20;
end;
