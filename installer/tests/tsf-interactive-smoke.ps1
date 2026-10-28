param(
    [Parameter(Mandatory)][string]$DesktopResult,
    [switch]$ProbeMouseCaret
)
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
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$build = Join-Path $env:RUNNER_TEMP 'personal-tsf-interactive-smoke'
cmake -S (Join-Path $repoRoot 'tests/tsf-interactive-smoke') -B $build -A x64
if ($LASTEXITCODE -ne 0) { throw 'TSF smoke configuration failed.' }
cmake --build $build --config Release --parallel
if ($LASTEXITCODE -ne 0) { throw 'TSF smoke build failed.' }
$scenarios = @(
    @{ Name = 'vertical'; Layout = 'vertical'; PageSize = 6 }
    @{ Name = 'horizontal-3'; Layout = 'horizontal'; PageSize = 3 }
    @{ Name = 'horizontal-6'; Layout = 'horizontal'; PageSize = 6 }
    @{ Name = 'horizontal-9'; Layout = 'horizontal'; PageSize = 9 }
)
if ($ProbeMouseCaret) {
    $scenarios += @{ Name = 'mouse-caret'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-richedit'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-region-no-sink'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-region-down'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-region-consume'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-region-keep'; Layout = 'vertical'; PageSize = 6 }
    $scenarios += @{ Name = 'mouse-caret-region'; Layout = 'vertical'; PageSize = 6 }
}
foreach ($scenario in $scenarios) {
    $layout = $scenario.Layout
    $pageSize = $scenario.PageSize
    Get-Process -Name 'ChengjiangImeServer' -ErrorAction SilentlyContinue | Stop-Process -Force
    $settings = @{
        'candidate_translations' = 'true'
        'candidate_window_layout' = '"' + $layout + '"'
        'candidate_window_fit_content' = 'false'
        'candidate_window_follow_cursor' = 'false'
        'candidate_horizontal_arrow_navigation' = 'true'
        'paging_page_up_down' = 'true'
        'page_size' = [string]$pageSize
        'cloud_candidates' = 'false'
    }
    $layoutConfig = $config
    foreach ($entry in $settings.GetEnumerator()) {
        $pattern = '(?m)^[ \t]*' + [regex]::Escape($entry.Key) + '[ \t]*=[ \t]*[^\r\n#]*'
        if (-not [regex]::IsMatch($layoutConfig, $pattern)) { throw "Missing smoke test setting: $($entry.Key)" }
        $layoutConfig = [regex]::Replace($layoutConfig, $pattern, "$($entry.Key) = $($entry.Value)")
    }
    # Keep the candidate order stable while comparing Page Down with right
    # presses; otherwise selecting the reference candidate can promote it.
    $frequencyPattern = '(?m)(^\[frequency_adjustment\][ \t]*\r?\n(?:[^\[]*?)^mode[ \t]*=[ \t]*)[^\r\n#]*'
    if (-not [regex]::IsMatch($layoutConfig, $frequencyPattern)) { throw 'Missing frequency mode.' }
    $layoutConfig = [regex]::Replace($layoutConfig, $frequencyPattern, '${1}"disabled"')
    [IO.File]::WriteAllText($configPath, $layoutConfig, [Text.UTF8Encoding]::new($false))
    $server = Start-Process -FilePath $state.ServerPath -ArgumentList '--watchdog-managed' `
        -WorkingDirectory (Split-Path -Parent $state.ServerPath) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    $server.Refresh()
    if ($server.HasExited) { throw "Personal UI Server exited: $($server.ExitCode)" }
    $env:CHENGJIANG_SMOKE_SCREENSHOT_DIR = Join-Path (Join-Path $env:RUNNER_TEMP 'personal-tsf-screenshots') $scenario.Name
    New-Item -ItemType Directory -Path $env:CHENGJIANG_SMOKE_SCREENSHOT_DIR -Force | Out-Null
    # Keep this an array even for one argument: splatting a bare string passes
    # its characters separately instead of the complete switch.
    $arguments = @(if ($layout -eq 'horizontal') { "--horizontal-navigation=$pageSize" }
        elseif ($scenario.Name -eq 'mouse-caret') { '--mouse-caret-diagnostic' }
        elseif ($scenario.Name -eq 'mouse-caret-richedit') { '--mouse-caret-richedit' }
        elseif ($scenario.Name -eq 'mouse-caret-region-no-sink') { '--mouse-caret-region-no-sink' }
        elseif ($scenario.Name -eq 'mouse-caret-region-down') { '--mouse-caret-region-down' }
        elseif ($scenario.Name -eq 'mouse-caret-region-consume') { '--mouse-caret-region-consume' }
        elseif ($scenario.Name -eq 'mouse-caret-region') { '--mouse-caret-region' }
        elseif ($scenario.Name -eq 'mouse-caret-region-keep') { '--mouse-caret-region-keep' })
    & (Join-Path $build 'Release/personal-tsf-interactive-smoke.exe') @arguments |
        Tee-Object -Variable smokeLines | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -eq 77) {
        Write-Host "SKIP: focus was unavailable for $($scenario.Name); no real-input test was performed."
    } elseif ($LASTEXITCODE -ne 0) {
        throw "Interactive TSF smoke failed for $($scenario.Name): $LASTEXITCODE"
    } elseif ($layout -eq 'horizontal' -and
              -not (($smokeLines -join "`n").Contains("PASS: $pageSize right keys"))) {
        throw 'The horizontal navigation scenario did not run.'
    } elseif ($scenario.Name -like 'mouse-caret*' -and
              -not (($smokeLines -join "`n").Contains('MOUSE_CARET:'))) {
        throw 'The mouse caret diagnostic did not run.'
    }
}
