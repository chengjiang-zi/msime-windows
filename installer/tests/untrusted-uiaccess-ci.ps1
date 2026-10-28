param(
    [Parameter(Mandatory)][string]$PersonalInstaller,
    [Parameter(Mandatory)][string]$DevCertificate,
    [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Untrusted-certificate testing requires a disposable GitHub-hosted Windows runner.'
}

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($DevCertificate)
$signature = Get-AuthenticodeSignature -LiteralPath $PersonalInstaller
if ($certificate.Subject -ne 'CN=Chengjiang IME Personal Dev Build Code Signing' -or
    -not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'Unexpected personal installer signature.'
}
function Assert-NotTrusted {
    foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\LocalMachine\TrustedPublisher',
                         'Cert:\CurrentUser\Root', 'Cert:\CurrentUser\TrustedPublisher')) {
        if (Get-ChildItem -LiteralPath $store | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }) {
            throw 'The development certificate is already present in a trust store.'
        }
    }
}
Assert-NotTrusted
if ($signature.Status -eq 'Valid') { throw 'The test installer is unexpectedly trusted.' }

$outcome = 'inconclusive'
$detail = 'The desktop was unavailable.'
try {
    $desktopResult = Join-Path $env:RUNNER_TEMP 'untrusted-desktop.txt'
    & pwsh -STA -File (Join-Path $PSScriptRoot 'interactive-desktop-probe.ps1') -ResultPath $desktopResult
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $desktopResult) -or
        [IO.File]::ReadAllText($desktopResult).Trim() -ne 'interactive') {
        return
    }
    $languages = Get-WinUserLanguageList
    if (-not ($languages | Where-Object { $_.LanguageTag -like 'zh-*' })) {
        $languages.Add('zh-Hans-CN')
        Set-WinUserLanguageList -LanguageList $languages -Force
    }
    $log = Join-Path $env:RUNNER_TEMP 'untrusted-setup.log'
    $process = Start-Process -FilePath $PersonalInstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES',
        '/NORESTART', "/LOG=`"$log`"") -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $outcome = 'unavailable'
        $detail = 'The installer did not finish without trusting the certificate.'
        return
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) {
        $outcome = 'unavailable'
        $detail = "The installer returned $($process.ExitCode) without trusting the certificate."
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Select-Object -Last 35 | Write-Host }
        return
    }
    $smokeLog = Join-Path $env:RUNNER_TEMP 'untrusted-smoke.log'
    $smokeError = Join-Path $env:RUNNER_TEMP 'untrusted-smoke-error.log'
    $smokeScript = Join-Path $PSScriptRoot 'tsf-interactive-smoke.ps1'
    $smoke = Start-Process -FilePath (Get-Command pwsh -CommandType Application).Source -ArgumentList @(
        '-NoProfile', '-File', "`"$smokeScript`"", '-DesktopResult', "`"$desktopResult`"") `
        -RedirectStandardOutput $smokeLog -RedirectStandardError $smokeError -WindowStyle Hidden -PassThru
    if (-not $smoke.WaitForExit(180000)) {
        Stop-Process -Id $smoke.Id -Force -ErrorAction SilentlyContinue
        $outcome = 'unavailable'
        $detail = 'The interactive input probe timed out without certificate trust.'
        return
    }
    $smoke.Refresh()
    $smokeCode = $smoke.ExitCode
    $smokeOutput = [IO.File]::ReadAllText($smokeLog) + [IO.File]::ReadAllText($smokeError)
    Write-Host $smokeOutput
    if ($smokeCode -eq 0 -and $smokeOutput.Contains('PASS: personal TSF committed Chinese text')) {
        $outcome = 'ordinary-input-worked'
        $detail = 'Personal IME committed Chinese text in a normal test field without importing the certificate.'
    } elseif ($smokeOutput.Contains('SKIP:')) {
        $detail = 'The interactive input probe was skipped.'
    } else {
        $outcome = 'unavailable'
        $detail = "The interactive input probe failed without certificate trust (exit $smokeCode)."
    }
} finally {
    Assert-NotTrusted
    if ((Get-AuthenticodeSignature -LiteralPath $PersonalInstaller).Status -eq 'Valid') {
        throw 'The installer unexpectedly became trusted during the diagnostic.'
    }
    $message = "Outcome: $outcome`n$detail`nNo personal development certificate was imported into a trust store."
    [IO.File]::WriteAllText($ResultPath, $message)
    Write-Host $message
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $message }
    $global:LASTEXITCODE = 0
}
