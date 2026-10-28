param([string]$IsccPath = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsccPath) {
    $compiler = Get-Command ISCC.exe -CommandType Application -ErrorAction Stop
    $IsccPath = $compiler.Source
}
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('chengjiang-isolation-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testRoot = (Resolve-Path -LiteralPath $testRoot).Path
if (-not $testRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Probe root is outside the temporary directory.'
}
$junction = Join-Path $testRoot 'junction'
$substitutedDrive = ''
try {
    $probe = Join-Path $testRoot 'personal-isolation-probe.exe'
    & $IsccPath '/Qp' "/O$testRoot" (Join-Path $PSScriptRoot 'personal-isolation-probe.iss')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $probe -PathType Leaf)) {
        throw 'Could not compile the isolation probe.'
    }
    $upstream = Join-Path $testRoot 'upstream'
    $personal = Join-Path $testRoot 'personal'
    $otherLocal = Join-Path $testRoot 'other-user-local'
    New-Item -ItemType Directory -Path $upstream, $personal, $otherLocal | Out-Null
    New-Item -ItemType Junction -Path $junction -Target $upstream | Out-Null
    $env:METASEQUOIA_IME_DATA_DIR = $upstream
    $cases = @(
        @{ Name = 'same'; Path = $upstream; Expect = 'blocked' },
        @{ Name = 'child'; Path = (Join-Path $upstream 'child'); Expect = 'blocked' },
        @{ Name = 'parent'; Path = $testRoot; Expect = 'blocked' },
        @{ Name = 'normalized'; Path = (Join-Path $personal '..\upstream\child'); Expect = 'blocked' },
        @{ Name = 'junction'; Path = (Join-Path $junction 'child'); Expect = 'blocked' },
        @{ Name = 'short-name'; Path = (Join-Path $testRoot 'UPSTRE~1'); Expect = 'blocked' },
        @{ Name = 'network'; Path = '\\example.invalid\share\data'; Expect = 'blocked' },
        @{ Name = 'upstream-default'; Path = (Join-Path $env:LOCALAPPDATA 'metasequoiaime'); Expect = 'blocked' },
        @{ Name = 'other-user-default'; Path = (Join-Path $otherLocal 'metasequoiaime\child');
           InteractiveLocal = $otherLocal; Expect = 'blocked' },
        @{ Name = 'upstream-program'; Path = (Join-Path $env:ProgramFiles 'metasequoiaime\server'); Expect = 'blocked' },
        @{ Name = 'upstream-system'; Path = (Join-Path $env:SystemRoot 'System32\IME\MetasequoiaIME'); Expect = 'blocked' },
        @{ Name = 'independent'; Path = $personal; Expect = 'allowed' }
    )
    # Never create drive mappings on the developer's machine.
    if ($env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted') {
        foreach ($letter in @('Z', 'Y', 'X', 'W')) {
            if (-not (Test-Path "${letter}:\")) {
                $substitutedDrive = "${letter}:"
                break
            }
        }
        if (-not $substitutedDrive) { throw 'No free drive letter for SUBST test.' }
        & "$env:SystemRoot\System32\subst.exe" $substitutedDrive $upstream
        if ($LASTEXITCODE -ne 0) { throw 'Could not create test SUBST mapping.' }
        $cases += @{ Name = 'subst'; Path = "$substitutedDrive\child"; Expect = 'blocked' }
    }
    foreach ($case in $cases) {
        $result = Join-Path $testRoot ($case.Name + '.txt')
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
            "/TARGET=`"$($case.Path)`"", "/RESULT=`"$result`"")
        if ($case.ContainsKey('InteractiveLocal')) {
            $arguments += "/INTERACTIVELOCAL=`"$($case.InteractiveLocal)`""
        }
        $process = Start-Process -FilePath $probe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if (-not (Test-Path -LiteralPath $result -PathType Leaf)) {
            throw "Probe $($case.Name) produced no result (exit $($process.ExitCode))."
        }
        $actual = [IO.File]::ReadAllText($result).Trim()
        if ($actual -ne $case.Expect) {
            throw "Probe $($case.Name): expected $($case.Expect), got $actual."
        }
        Write-Host "PASS $($case.Name): $actual"
    }
}
finally {
    if ($substitutedDrive) {
        & "$env:SystemRoot\System32\subst.exe" $substitutedDrive /d
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove test SUBST mapping.' }
    }
    # Remove the junction itself before recursively removing the verified test root.
    if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
