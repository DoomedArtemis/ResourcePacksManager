[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
. (Join-Path $PSScriptRoot 'combined-pack-dependencies.ps1')
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Builder syntax errors.' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $statement.Extent.Text }
}
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('build-performance-test-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory $fixture
try {
    # Retain the original parser, including its empty-key support and limits.
    Add-Type -AssemblyName System.Web.Extensions
    $referenceValidator = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $cases = @('{}', '{"variants":{"":{"model":"demo:block/a"}}}', 'null', '[1,true,"hello"]',
        '{broken', '{"a":', '', ('{"large":"' + ('x' * 2097152) + '"}'), '{}')
    foreach ($raw in $cases) {
        foreach ($bom in @($false, $true)) {
            $file = Join-Path $fixture 'input [1] #%.json'
            [IO.File]::WriteAllText($file, $raw, [Text.UTF8Encoding]::new($bom))
            $expected = $true; $actual = $true
            try { $null = $referenceValidator.DeserializeObject((Get-Content -LiteralPath $file -Raw -Encoding UTF8)) } catch { $expected = $false }
            try { Assert-ValidJsonFile $file } catch { $actual = $false }
            if ($actual -ne $expected) { throw "JSON acceptance changed (length=$($raw.Length), BOM=$bom, expected=$expected, actual=$actual)." }
        }
    }
    Push-Location $fixture
    try { Assert-ValidJsonFile '.\input [1] #%.json' }
    finally { Pop-Location }
    $missingRejected = $false
    try { Assert-ValidJsonFile (Join-Path $fixture 'missing.json') } catch { $missingRejected = $true }
    if (-not $missingRejected) { throw 'Missing JSON file accepted.' }

    $nested = Join-Path $fixture ('nested [1] # % ' + [char]0x00E4)
    Ensure-Directory $nested
    $file = Join-Path $nested 'a #%.json'
    [IO.File]::WriteAllText($file, '{}')
    foreach ($base in @($fixture, ($fixture + '\'), $nested)) {
        $referenceBase = [Uri]::new(((Resolve-Path -LiteralPath $base).Path.TrimEnd('\') + '\'))
        $referenceFile = [Uri]::new((Resolve-Path -LiteralPath $file).Path)
        $expected = ([Uri]::UnescapeDataString($referenceBase.MakeRelativeUri($referenceFile).ToString()) -replace '\\', '/').TrimStart('./')
        $actual = Get-NormalizedRelativePath -BasePath $base -FullPath $file -BaseUri (New-RelativePathBaseUri $base)
        if ($actual -cne $expected) { throw 'Relative path encoding changed.' }
    }

    # Explicit option reuse must behave like a normal read, and subsequent calls
    # without supplied options must still read edits in this same process.
    Set-Content (Join-Path $fixture 'pack.build.psd1') "@{ Versions = @('old') }"
    $directory = Get-Item $fixture
    $config = @{ PackBuildConfigFile = 'pack.build.psd1'; Versions = @(@{ Id = 'old' }, @{ Id = 'new' }) }
    $options = Get-PackBuildOptions $directory $config
    $selected = @(Get-PackSelectedVersions $directory $config $config.Versions -PackOptions $options)
    if ($selected.Count -ne 1 -or $selected[0].Id -ne 'old') { throw 'Supplied options ignored.' }
    Set-Content (Join-Path $fixture 'pack.build.psd1') "@{ Versions = @('new') }"
    $selected = @(Get-PackSelectedVersions $directory $config $config.Versions)
    if ($selected.Count -ne 1 -or $selected[0].Id -ne 'new') { throw 'Configuration edits cached across calls.' }

    # Count real hashes: shared texture/sidecar reads are reused, providers remain
    # separate, and a fresh combine context rereads changed content.
    $script:hashCalls = 0
    function Get-FileHash {
        param($LiteralPath, $Algorithm)
        $script:hashCalls++
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
    }
    $sidecar = Join-Path $fixture 'texture.png.mcmeta'
    [IO.File]::WriteAllText($sidecar, '{"animation":{}}')
    $components = @{ a = @{ Files = @{ texture = $file; metadata = $sidecar } }; b = @{ Files = @{ texture = $sidecar } } }
    $context = @{ Components = $components; FileHashes = @{} }
    $first = Get-CombinedFileHash $context 'a' 'texture'
    $null = Get-CombinedFileHash $context 'a' 'texture'
    $null = Get-CombinedFileHash $context 'a' 'metadata'
    $other = Get-CombinedFileHash $context 'b' 'texture'
    if ($script:hashCalls -ne 2 -or $first -eq $other) { throw 'Hash reuse or provider isolation failed.' }
    [IO.File]::WriteAllText($file, '{"changed":true}')
    $newContext = @{ Components = $components; FileHashes = @{} }
    if ((Get-CombinedFileHash $newContext 'a' 'texture') -eq $first) { throw 'Hashes leaked across builds.' }
    Remove-Item Function:\Get-FileHash

    $script:uiCalls = New-Object System.Collections.Generic.List[object]
    function Write-Progress {
        param($Id, $Activity, $Status, $PercentComplete, [switch]$Completed)
        $script:uiCalls.Add(@{ Status = $Status; Completed = $Completed.IsPresent; Percent = $PercentComplete })
    }
    Show-BuildProgress -Id 99 -Activity 'Fixture' -Stage 'Copy' -Completed 0 -Total 1000
    for ($i = 1; $i -lt 100; $i++) { Show-BuildProgress -Id 99 -Activity 'Fixture' -Stage 'Copy' -Completed $i -Total 1000 }
    if ($script:uiCalls.Count -ge 100) { throw 'Progress was not throttled.' }
    $script:BuildProgressLog[99].UiTime = [DateTime]::UtcNow.AddSeconds(-1)
    $count = $script:uiCalls.Count
    Show-BuildProgress -Id 99 -Activity 'Fixture' -Stage 'Copy' -Completed 500 -Total 1000
    if ($script:uiCalls.Count -ne $count + 1) { throw 'Periodic progress update missing.' }
    Show-BuildProgress -Id 99 -Activity 'Fixture' -Stage 'Validate'
    Show-BuildProgress -Id 99 -Activity 'Fixture' -Stage 'Validate' -Completed 1000 -Total 1000
    if ($script:uiCalls[-1].Percent -ne 100) { throw 'Final progress missing.' }
    Close-BuildProgress -Id 99 -Activity 'Fixture'
    if (-not $script:uiCalls[-1].Completed -or $script:BuildProgressLog.ContainsKey(99)) { throw 'Progress cleanup failed.' }
    Remove-Item Function:\Write-Progress
    Write-Output 'Passed JSON/parser limits, BOM and literal paths, configuration refresh, hash reuse/isolation, and throttled progress with stage/final updates.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'build-performance-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
