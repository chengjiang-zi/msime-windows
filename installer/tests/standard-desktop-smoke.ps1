param(
    [Parameter(Mandatory)][string]$ExpectedSid,
    [Parameter(Mandatory)][string]$SmokeExe,
    [Parameter(Mandatory)][string]$ResultDir,
    [Parameter(Mandatory)][string]$CertificateThumbprint
)
$ErrorActionPreference = 'Stop'
$log = Join-Path $ResultDir 'standard-input.log'
try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $ExpectedSid) {
        throw 'The process is not running as the temporary standard user.'
    }
    foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\LocalMachine\TrustedPublisher',
                         'Cert:\CurrentUser\Root', 'Cert:\CurrentUser\TrustedPublisher')) {
        if (Get-ChildItem -LiteralPath $store | Where-Object Thumbprint -eq $CertificateThumbprint) {
            throw 'The development certificate is trusted.'
        }
    }
    $languages = Get-WinUserLanguageList
    if (-not ($languages | Where-Object { $_.LanguageTag -like 'zh-*' })) {
        $languages.Add('zh-Hans-CN')
        Set-WinUserLanguageList -LanguageList $languages -Force
    }
    $state = Get-ItemProperty -LiteralPath 'HKLM:\Software\Chengjiang\PersonalIME'
    $settings = Join-Path (Split-Path -Parent $state.ServerPath) 'ChengjiangImeSettings.exe'
    $register = Start-Process -FilePath $settings -ArgumentList '--register-profile' -WindowStyle Hidden -Wait -PassThru
    if ($register.ExitCode -ne 0) { throw "Profile registration failed: $($register.ExitCode)" }
    $server = Start-Process -FilePath $state.ServerPath -ArgumentList '--watchdog-managed' `
        -WorkingDirectory (Split-Path -Parent $state.ServerPath) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    $server.Refresh()
    if ($server.HasExited) { throw "Standard-user Server exited: $($server.ExitCode)" }
    $errorLog = Join-Path $ResultDir 'standard-input-error.log'
    $smoke = Start-Process -FilePath $SmokeExe -RedirectStandardOutput $log -RedirectStandardError $errorLog `
        -WindowStyle Hidden -Wait -PassThru
    $result = $smoke.ExitCode
    $output = [IO.File]::ReadAllText($log) + [IO.File]::ReadAllText($errorLog)
    if ($result -ne 0 -or $output.Contains('SKIP:') -or
        -not $output.Contains('PASS: personal TSF committed Chinese text')) {
        throw "Standard-user input did not pass ($result)."
    }
    [IO.File]::AppendAllText($log, "`nPASS: actual standard user committed Chinese text without certificate trust.`n")
    exit 0
} catch {
    [IO.File]::AppendAllText($log, "`nERROR: $($_.Exception.Message)`n")
    exit 1
}
