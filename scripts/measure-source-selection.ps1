[CmdletBinding()]
param(
    [string]$BuilderPath = 'scripts/build-texture-packs.ps1',
    [string]$Pack = 'alternative_ores',
    [string[]]$Version = @('1.21.1'),
    [string]$OutputPath
)
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
$directory = Get-Item (Join-Path (Join-Path $repoRoot $config.PackRoot) $Pack)
$measurements = @()
foreach ($versionId in $Version) {
    $versionConfig = @($config.Versions | Where-Object { $_.Id -eq $versionId })
    if ($versionConfig.Count -ne 1) { throw "Unknown version: $versionId" }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $files = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $versionConfig[0])
    $timer.Stop()
    $measurements += [pscustomobject]@{ Pack = $Pack; Version = $versionId; Seconds = $timer.Elapsed.TotalSeconds; Files = $files }
    Write-Host ('{0} {1}: {2:N3}s, {3} selected files' -f $Pack, $versionId, $timer.Elapsed.TotalSeconds, $files.Count)
}
if ($OutputPath) {
    [IO.File]::WriteAllText((Join-Path $repoRoot $OutputPath), (ConvertTo-Json -InputObject @($measurements) -Depth 20), (New-Object Text.UTF8Encoding($false)))
}
