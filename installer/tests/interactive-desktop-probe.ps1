param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# This opens a window and changes focus. Never run it on the user's desktop.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or
    $env:RUNNER_OS -ne 'Windows') {
    throw 'The desktop probe requires a disposable GitHub-hosted Windows runner.'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PersonalDesktopProbe {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@

$result = 'unavailable'
$form = $null
try {
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'Chengjiang IME disposable desktop probe'
    $form.Width = 500
    $form.Height = 250
    $box = [Windows.Forms.TextBox]::new()
    $box.Dock = [Windows.Forms.DockStyle]::Fill
    $box.Multiline = $true
    $form.Controls.Add($box)
    $form.Show()
    $form.Activate()
    $box.Focus() | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        if ([PersonalDesktopProbe]::GetForegroundWindow() -eq $form.Handle -and $box.Focused) {
            $result = 'interactive'
            break
        }
        Start-Sleep -Milliseconds 100
    }
} catch {
    Write-Host "Desktop probe could not open a window: $($_.Exception.Message)"
} finally {
    if ($form) {
        $form.Close()
        $form.Dispose()
    }
}
[IO.File]::WriteAllText($ResultPath, $result)
Write-Host "Disposable runner desktop: $result"
