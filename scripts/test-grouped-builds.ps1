[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('group-build-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/scripts", "$fixture/resource_packs/example/assets/minecraft/textures/block" -Force | Out-Null
try {
    foreach ($name in @('build-texture-packs.ps1', 'combined-pack-support.ps1', 'archive-pack.ps1', 'publish-modrinth.ps1', 'publish-curseforge.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination "$fixture/scripts/$name"
    }
    @'
@{
 PackRoot = 'resource_packs'; PackIconFile = 'pack.png'; PackBuildConfigFile = 'pack.build.psd1'
 CanonicalAssetsFolder = 'assets'; AutoSortFolder = 'drop'; AutoSortMappings = @()
 BuildRoot = 'build'; BaseDescription = 'Example'; PackageNameTemplate = '{PackName}-{VersionId}'
 VanillaCatalogCacheRoot = 'cache'
 Validation = @{ RequireLowercasePaths = $true; ParseJsonFiles = $true; ParseMcmetaFiles = $true; RequireTextureForTextureMcmeta = $false }
 Versions = @(
  @{ Id = '1.13'; Enabled = $true; PackFormat = 4 }
  @{ Id = '1.13.1'; Enabled = $true; PackFormat = 4 }
  @{ Id = '1.13.2'; Enabled = $true; PackFormat = 4 }
  @{ Id = '1.14'; Enabled = $true; PackFormat = 5 }
 )
}
'@ | Set-Content -LiteralPath "$fixture/config.psd1"
    Set-Content -LiteralPath "$fixture/resource_packs/example/assets/minecraft/textures/block/example.png" -Value 'fixture'
    Set-Content -LiteralPath "$fixture/resource_packs/example/pack.build.psd1" -Value "@{ Modrinth = @{ ProjectId = 'example'; ReleaseVersion = '1.0.0' }; CurseForge = @{ ProjectId = '123'; ReleaseVersion = '1.0.0' } }"
    & "$fixture/scripts/build-texture-packs.ps1" -ConfigPath config.psd1 -Pack example -Version all
    $root = "$fixture/build/example"
    $groupZip = "$root/example-1.13.x.zip"
    if (@(Get-ChildItem $root -Filter '*.zip').Count -ne 2 -or -not (Test-Path $groupZip)) { throw 'Identical builds were not grouped.' }
    if (@(Get-PackZipVersions $groupZip).Count -ne 3) { throw 'Exact membership lost.' }
    $config = Import-PowerShellDataFile "$fixture/config.psd1"
    if ((Get-PackVersionLabel -Versions @('1.13', '1.13.1') -Config $config) -ne '1.13-1.13.1') { throw 'Partial family range was mislabeled.' }
    # Entry order and ZIP timestamps are packaging details, not pack contents.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $reorderedPath = "$fixture/reordered.zip"
    $inputZip = [IO.Compression.ZipFile]::OpenRead($groupZip)
    $outputZip = [IO.Compression.ZipFile]::Open($reorderedPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entry in $inputZip.Entries | Sort-Object FullName -Descending) {
            $newEntry = $outputZip.CreateEntry($entry.FullName)
            $newEntry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $inputStream = $entry.Open(); $outputStream = $newEntry.Open()
            try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
        }
    }
    finally { $inputZip.Dispose(); $outputZip.Dispose() }
    if ((Get-PackZipContentHash $groupZip) -ne (Get-PackZipContentHash $reorderedPath)) { throw 'ZIP metadata affected identity.' }
    foreach ($platform in @('modrinth', 'curseforge')) {
        $output = (& "$fixture/scripts/publish-$platform.ps1" -ConfigPath config.psd1 -Pack example -Version '1.13..1.13.2' -ReleaseVersion 1.0.0 -SkipBuild 6>&1 | Out-String)
        if (($output | Select-String 'Dry run: would publish' -AllMatches).Matches.Count -ne 1 -or $output -notmatch '1\.13\.x') { throw "Grouped publishing failed: $platform $output" }
    }
    # Rebuilding one member must preserve the other members with their old content.
    Set-Content -LiteralPath "$fixture/resource_packs/example/assets/minecraft/textures/block/example.png" -Value 'changed'
    & "$fixture/scripts/build-texture-packs.ps1" -ConfigPath config.psd1 -Pack example -Version 1.13.1
    if (@(Get-ChildItem $root -Filter '*.zip').Count -ne 3) { throw 'Partial rebuild did not split content groups.' }
    $original = Find-PackBuildZip -BuildZipPath "$root/example-1.13.zip" -MinecraftVersion 1.13
    if (@(Get-PackZipVersions $original).Count -ne 2) { throw 'Partial rebuild lost untouched versions.' }
    & "$fixture/scripts/archive-pack.ps1" -ConfigPath config.psd1 -Pack example -Version 1.13 -ReleaseVersion 1.0.0
    $archive = Get-ReleaseArchiveZip -Directory "$fixture/archive/example/1.0.0" -PackName example -ReleaseVersion 1.0.0 -MinecraftVersion 1.13.2
    if ($null -eq $archive -or @(Get-PackZipVersions $archive.FullName).Count -ne 2) { throw 'Archive membership lookup failed.' }
    if (Test-Path $original) { throw 'Grouped archive did not move ZIP.' }
    # Exercise the complete publisher entry points with local transport stubs.
    # No HTTP clients or remote uploads are created by these fixture scripts.
    foreach ($platform in @('modrinth', 'curseforge')) {
        $scriptPath = "$fixture/scripts/publish-$platform.ps1"
        $stub = if ($platform -eq 'modrinth') {
            @'
function New-ModrinthHttpClient { param($Token) return [IO.MemoryStream]::new() }
function Invoke-ModrinthGetProject { param($Client, $ProjectId) return [pscustomobject]@{ id = 'example' } }
function Invoke-ModrinthGetProjectVersions {
    param($Client, $ProjectId)
    $path = Join-Path $PSScriptRoot '../modrinth-upload.json'
    if (Test-Path $path) { return (Get-Content $path -Raw | ConvertFrom-Json) }
    return @()
}
function Publish-ModrinthVersion {
    param($Client, $Item)
    Get-ModrinthUploadMetadata $Item | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $PSScriptRoot '../modrinth-upload.json')
    return [pscustomobject]@{ id = 'local-file' }
}
'@
        } else {
            @'
function New-CurseForgeHttpClient { param($Token) return [IO.MemoryStream]::new() }
function Publish-CurseForgeVersion {
    param($Client, $Item)
    Get-CurseForgeUploadMetadata $Item | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $PSScriptRoot '../curseforge-upload.json')
    return [pscustomobject]@{ id = '1234' }
}
'@
        }
        $source = [IO.File]::ReadAllText($scriptPath)
        $marker = '$repoRoot = Split-Path -Path $PSScriptRoot -Parent'
        if (-not $source.Contains($marker)) { throw 'Unable to install local publisher transport.' }
        [IO.File]::WriteAllText($scriptPath, $source.Replace($marker, $stub + "`r`n" + $marker))
        $env:RPM_GROUP_TEST_TOKEN = 'fixture-token'
        try {
            & $scriptPath -ConfigPath config.psd1 -Pack example -Version '1.13,1.13.2' -ReleaseVersion 1.0.0 -SkipBuild -Publish -Yes -TokenEnvironmentVariable RPM_GROUP_TEST_TOKEN | Out-Null
            $capture = "$fixture/$platform-upload.json"
            $metadata = Get-Content $capture -Raw | ConvertFrom-Json
            $gameVersions = if ($platform -eq 'modrinth') { @($metadata.game_versions) } else { @($metadata.gameVersionNames) }
            if ($gameVersions.Count -ne 2 -or '1.13' -notin $gameVersions -or '1.13.2' -notin $gameVersions) { throw "Wrong grouped version metadata: $platform" }
            $writeTime = (Get-Item $capture).LastWriteTimeUtc
            & $scriptPath -ConfigPath config.psd1 -Pack example -Version 1.13.2 -ReleaseVersion 1.0.0 -SkipBuild -Publish -Yes -TokenEnvironmentVariable RPM_GROUP_TEST_TOKEN | Out-Null
            if ((Get-Item $capture).LastWriteTimeUtc -ne $writeTime) { throw "Publishing one member repeated a grouped upload: $platform" }
        }
        finally { Remove-Item Env:RPM_GROUP_TEST_TOKEN }
    }
    # Missing builds are built together before publishers resolve shared paths.
    Copy-Item -LiteralPath "$fixture/resource_packs/example" -Destination "$fixture/resource_packs/ondemand" -Recurse
    $output = (& "$fixture/scripts/publish-curseforge.ps1" -ConfigPath config.psd1 -Pack ondemand -Version '1.13..1.13.2' -ReleaseVersion 1.0.0 -Build 6>&1 | Out-String)
    if (($output | Select-String 'Dry run: would publish' -AllMatches).Matches.Count -ne 1) { throw "Build-on-demand did not group uploads: $output" }
    # Version-specific dependencies must never become a shared global requirement.
    $optionsPath = "$fixture/resource_packs/example/pack.build.psd1"
    Set-Content -LiteralPath $optionsPath -Value "@{ CurseForge = @{ ProjectId = '123'; Dependencies = @(@{ ProjectId = '456'; Slug = 'fixture-dependency'; Versions = @('1.13.2') }) } }"
    $output = (& "$fixture/scripts/publish-curseforge.ps1" -ConfigPath config.psd1 -Pack example -Version '1.13,1.13.2' -ReleaseVersion 1.0.0 -SkipBuild -Republish 6>&1 | Out-String)
    if (($output | Select-String 'Dry run: would publish' -AllMatches).Matches.Count -ne 2) { throw "Different dependencies were merged: $output" }
    Write-Output 'Grouped build tests passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
