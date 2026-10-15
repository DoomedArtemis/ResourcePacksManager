[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('archive-pack-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/scripts", "$fixture/resource_packs/example", "$fixture/artemis_enhanced_visuals", "$fixture/build/example/reports", "$fixture/build/combined/reports" -Force | Out-Null
try {
    foreach ($name in @('archive-pack.ps1', 'build-texture-packs.ps1', 'combined-pack-support.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination "$fixture/scripts/$name"
    }
    Set-Content -LiteralPath "$fixture/config.psd1" -Value "@{ PackRoot = 'resource_packs'; PackBuildConfigFile = 'pack.build.psd1'; BuildRoot = 'build'; PackageNameTemplate = '{PackName}-{VersionId}'; Versions = @(@{ Id = '1.17'; Enabled = `$true; PackFormat = 7 }, @{ Id = '1.18'; Enabled = `$true; PackFormat = 8 }) }"
    Set-Content -LiteralPath "$fixture/resource_packs/example/pack.build.psd1" -Value "@{ PackMetadata = @{ name = 'Custom Example' }; Modrinth = @{ Enabled = `$false } }"
    Set-Content -LiteralPath "$fixture/artemis_enhanced_visuals/combined.psd1" -Value "@{ Name = 'combined'; DisplayName = 'Combined'; MinVersion = '1.18' }"
    function New-FixtureZip {
        param([string]$Path, [string]$Contents = '{}', [string]$Entry = 'pack.mcmeta')
        $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $writer = New-Object IO.StreamWriter($zip.CreateEntry($Entry).Open())
            try { $writer.Write($Contents) } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
    }
    $script = "$fixture/scripts/archive-pack.ps1"
    $source = "$fixture/build/example/example-1.17.zip"
    $report = "$fixture/build/example/reports/example-1.17.report.json"
    $destination = "$fixture/archive/example/1.0.0/Custom Example 1.0.0 MC1.17.zip"
    New-FixtureZip $source
    New-FixtureZip "$fixture/build/combined/combined-1.18.zip"
    New-FixtureZip "$fixture/build/combined/combined-1.17.zip"
    Set-Content -LiteralPath $report -Value '{}'
    Set-Content -LiteralPath "$fixture/build/example/reports/unrelated.report.json" -Value '{}'
    & $script -ConfigPath config.psd1 -Pack all -Version all -ReleaseVersion 1.0.0 -WhatIf
    if (-not (Test-Path $source) -or (Test-Path "$fixture/archive")) { throw 'WhatIf mutated files.' }
    & $script -ConfigPath config.psd1 -Pack all -Version '1.17..1.18' -ReleaseVersion 1.0.0
    if ((Test-Path $source) -or (Test-Path $report) -or -not (Test-Path $destination)) { throw 'Move, naming, or report cleanup failed.' }
    if (-not (Test-Path "$fixture/archive/combined/1.0.0/Combined 1.0.0 MC1.18.zip")) { throw 'Combined pack was not archived.' }
    if (-not (Test-Path "$fixture/build/combined/combined-1.17.zip")) { throw 'Unsupported combined version was archived.' }
    if (-not (Test-Path "$fixture/build/example/reports/unrelated.report.json")) { throw 'Unrelated report removed.' }
    Copy-Item -LiteralPath $destination -Destination $source
    & $script -ConfigPath config.psd1 -Pack example -Version 1.17 -ReleaseVersion 1.0.0
    if ((Test-Path $source) -or @(Get-ChildItem "$fixture/archive/example/1.0.0/*.zip").Count -ne 1) { throw 'Identical duplicate handling failed.' }
    New-FixtureZip $source '{"different":true}'
    & $script -ConfigPath config.psd1 -Pack example -Version 1.17 -ReleaseVersion 1.0.0
    if ((Test-Path $source) -or @(Get-ChildItem "$fixture/archive/example/1.0.0/*-uploaded-*.zip").Count -ne 1) { throw 'Different-content collision handling failed.' }
    New-FixtureZip $source
    New-FixtureZip "$fixture/build/example/example-1.18.zip" '{}' 'invalid.txt'
    $failed = $false
    try { & $script -ConfigPath config.psd1 -Pack example -Version all -ReleaseVersion 2.0.0 } catch { $failed = $true }
    if (-not $failed -or -not (Test-Path $source) -or (Test-Path "$fixture/archive/example/2.0.0")) { throw 'Invalid ZIP did not stop the entire selection before moves.' }
    $failed = $false
    try { & $script -ConfigPath config.psd1 -Pack example -Version 1.17 -ReleaseVersion '../escape' } catch { $failed = $true }
    if (-not $failed -or -not (Test-Path $source)) { throw 'Invalid release version accepted.' }
    $script:answers = New-Object 'Collections.Generic.Queue[string]'
    foreach ($answer in @('example', '1.17', '3.0.0')) { $script:answers.Enqueue($answer) }
    function Read-Host { param([string]$Prompt) return $answers.Dequeue() }
    & $script -ConfigPath config.psd1
    if ($script:answers.Count -ne 0 -or -not (Test-Path "$fixture/archive/example/3.0.0/Custom Example 3.0.0 MC1.17.zip")) { throw 'Interactive selection failed.' }
    Write-Output 'Archive pack tests passed.'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
