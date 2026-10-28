param([Parameter(Mandatory)][string]$DesktopResult, [Parameter(Mandatory)][string]$LogPath)
$ErrorActionPreference = 'Stop'
try {
    & (Join-Path $PSScriptRoot 'tsf-interactive-smoke.ps1') -DesktopResult $DesktopResult -UseExistingBuild *> $LogPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $output = [IO.File]::ReadAllText($LogPath)
    if (-not $output.Contains('PASS: personal TSF committed Chinese text') -or $output.Contains('SKIP:')) {
        throw 'Limited desktop input was skipped or did not commit Chinese text.'
    }
    exit 0
} catch {
    [IO.File]::AppendAllText($LogPath, "`nERROR: $($_.Exception.Message)`n")
    exit 1
}
