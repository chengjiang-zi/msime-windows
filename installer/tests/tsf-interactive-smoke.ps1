param([Parameter(Mandatory)][string]$DesktopResult)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
    throw 'Interactive TSF testing requires a disposable GitHub-hosted Windows runner.'
}
if (-not (Test-Path -LiteralPath $DesktopResult -PathType Leaf) -or
    [IO.File]::ReadAllText($DesktopResult).Trim() -ne 'interactive') {
    Write-Host 'SKIP: no interactive desktop; no real-input test was performed.'
    exit 0
}

# The preceding IPC-only test starts the Server without its candidate window.
# Replace it with the actual UI Server in this disposable VM before typing.
Get-Process -Name 'ChengjiangImeServer' -ErrorAction SilentlyContinue | Stop-Process -Force
$state = Get-ItemProperty -LiteralPath 'HKLM:\Software\Chengjiang\PersonalIME'
$configPath = Join-Path $state.DataDir 'config.toml'
$config = [IO.File]::ReadAllText($configPath)
$settings = @{
    'candidate_translations' = 'true'
    'candidate_window_layout' = '"vertical"'
    'candidate_window_fit_content' = 'false'
    'candidate_window_follow_cursor' = 'false'
    'cloud_candidates' = 'false'
}
foreach ($entry in $settings.GetEnumerator()) {
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($entry.Key) + '[ \t]*=[ \t]*[^\r\n#]*'
    if (-not [regex]::IsMatch($config, $pattern)) { throw "Missing smoke test setting: $($entry.Key)" }
    $config = [regex]::Replace($config, $pattern, "$($entry.Key) = $($entry.Value)")
}
[IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
$server = Start-Process -FilePath $state.ServerPath -ArgumentList '--watchdog-managed' `
    -WorkingDirectory (Split-Path -Parent $state.ServerPath) -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
$server.Refresh()
if ($server.HasExited) { throw "Personal UI Server exited: $($server.ExitCode)" }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$build = Join-Path $env:RUNNER_TEMP 'personal-tsf-interactive-smoke'
cmake -S (Join-Path $repoRoot 'tests/tsf-interactive-smoke') -B $build -A x64
if ($LASTEXITCODE -ne 0) { throw 'TSF smoke configuration failed.' }
cmake --build $build --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'TSF smoke build failed.' }
$env:CHENGJIANG_SMOKE_SCREENSHOT_DIR = Join-Path $env:RUNNER_TEMP 'personal-tsf-screenshots'
New-Item -ItemType Directory -Path $env:CHENGJIANG_SMOKE_SCREENSHOT_DIR -Force | Out-Null
& (Join-Path $build 'Release/personal-tsf-interactive-smoke.exe')
if ($LASTEXITCODE -eq 77) {
    Write-Host 'SKIP: focus was unavailable; no real-input test was performed.'
} elseif ($LASTEXITCODE -ne 0) {
    throw "Interactive TSF smoke failed: $LASTEXITCODE"
}
