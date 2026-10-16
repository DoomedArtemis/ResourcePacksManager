[CmdletBinding()]
param(
    [string]$BuilderPath = 'scripts/build-texture-packs.ps1',
    [string]$OutputRoot = 'cache/build-performance/current',
    [string]$CompareManifest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
$repoRoot = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $BuilderPath), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Builder syntax errors.' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $statement.Extent.Text }
}
$config = Import-PowerShellDataFile (Join-Path $repoRoot 'config/texture-pack.build.psd1')
$matrix = Import-PowerShellDataFile (Join-Path $repoRoot $config.VersionMatrixPath)
$config.Versions = @($matrix.Versions | ForEach-Object { Normalize-VersionConfig $_ })
$config.BuildRoot = Resolve-FullPath -BasePath $repoRoot -Path $OutputRoot
Ensure-Directory $config.BuildRoot
# Isolate staging and route caches from normal builds. No vanilla download is
# necessary for these packs, whose assets already have canonical paths.
function Get-TemporaryBuildRoot { return Join-Path $config.BuildRoot 'staging' }
function Get-PackRouteCachePath {
    param($RepoRoot, $Config, $PackDirectory, $VersionConfig)
    return Join-Path $config.BuildRoot "routes/$($PackDirectory.Name)/$($VersionConfig.Id).json"
}
$cases = @(
    @{ Pack = 'alternative_ores'; Version = '1.13' }
    @{ Pack = 'alternative_ores'; Version = '1.15.2' }
    @{ Pack = 'alternative_ores'; Version = '1.21.1' }
    @{ Pack = 'alternative_ores'; Version = '26.3' }
    @{ Pack = 'better_candles'; Version = '1.20.1' }
    @{ Pack = 'better_candles'; Version = '1.21.1' }
    @{ Pack = 'better_candles'; Version = '26.3' }
)
$measurements = @()
$optionsByPack = @{}
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($case in $cases) {
    $directory = Get-Item (Join-Path $repoRoot "$($config.PackRoot)/$($case.Pack)")
    $versionConfig = @($config.Versions | Where-Object { $_.Id -eq $case.Version })[0]
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $arguments = @{ RepoRoot = $repoRoot; Config = $config; PackDirectory = $directory; VersionConfig = $versionConfig }
    if ((Get-Command Build-PackVersion).Parameters.ContainsKey('PackOptions')) {
        if (-not $optionsByPack.ContainsKey($case.Pack)) { $optionsByPack[$case.Pack] = Get-PackBuildOptions $directory $config }
        $arguments.PackOptions = $optionsByPack[$case.Pack]
    }
    $result = Build-PackVersion @arguments
    $timer.Stop()
    $entries = @{}
    $archive = [IO.Compression.ZipFile]::OpenRead($result.ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $entries[$entry.FullName] = [BitConverter]::ToString($sha.ComputeHash($stream)) }
            finally { $stream.Dispose(); $sha.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    $measurements += @{ Pack = $case.Pack; Version = $case.Version; Seconds = $timer.Elapsed.TotalSeconds; Entries = $entries; WarningCount = $result.WarningCount }
    Write-Host ('{0} {1}: {2:N3}s, {3} entries' -f $case.Pack, $case.Version, $timer.Elapsed.TotalSeconds, $entries.Count)
}
$manifestPath = Join-Path $config.BuildRoot 'manifest.json'
[IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject @($measurements) -Depth 10))
if ($CompareManifest) {
    $before = Get-Content -LiteralPath $CompareManifest -Raw | ConvertFrom-Json
    if ($before.Count -ne $measurements.Count) { throw 'Build count changed.' }
    foreach ($actual in $measurements) {
        $expected = @($before | Where-Object { $_.Pack -eq $actual.Pack -and $_.Version -eq $actual.Version })
        if ($expected.Count -ne 1) { throw 'Missing baseline build.' }
        $expectedEntries = @($expected[0].Entries.PSObject.Properties)
        if ($expectedEntries.Count -ne $actual.Entries.Count -or $expected[0].WarningCount -ne $actual.WarningCount) { throw 'Entry/warning count changed.' }
        foreach ($entry in $expectedEntries) {
            if ($actual.Entries[$entry.Name] -cne $entry.Value) { throw "ZIP content changed: $($actual.Pack) $($actual.Version) $($entry.Name)" }
        }
    }
    Write-Host 'All ZIP entry names, contents and warning counts match the baseline.'
}
