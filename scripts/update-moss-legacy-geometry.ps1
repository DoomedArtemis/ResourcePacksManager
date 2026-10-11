[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot
$packRoot = Join-Path $workspaceRoot 'resource_packs/better_moss'
$cacheRoot = Join-Path $workspaceRoot 'cache/transparency'
$optionsPath = Join-Path $packRoot 'pack.build.psd1'
$encoding = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null

$manifestPath = Join-Path $workspaceRoot 'cache/vanilla-asset-catalogs/version_manifest_v2.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -OutFile $manifestPath
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($versionId in @('1.17', '1.20', '1.21.4', '1.21.5', '1.21.11')) {
    $version = $manifest.versions | Where-Object id -EQ $versionId | Select-Object -First 1
    $metadataPath = Join-Path $cacheRoot "$versionId.json"
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        Invoke-WebRequest -UseBasicParsing -Uri $version.url -OutFile $metadataPath
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $jarPath = Join-Path $cacheRoot "$versionId.jar"
    if (-not (Test-Path -LiteralPath $jarPath)) {
        Invoke-WebRequest -UseBasicParsing -Uri $metadata.downloads.client.url -OutFile $jarPath
    }
    if ((Get-FileHash -LiteralPath $jarPath -Algorithm SHA1).Hash.ToLowerInvariant() -ne $metadata.downloads.client.sha1) {
        throw "Official client SHA1 mismatch: $versionId"
    }
    $outputRoot = Join-Path $cacheRoot "vanilla/$versionId"
    $archive = [IO.Compression.ZipFile]::OpenRead($jarPath)
    try {
        foreach ($entry in $archive.Entries | Where-Object {
            $_.FullName -match '^assets/minecraft/(models/block/.*\.json|textures/block/.*\.png(?:\.mcmeta)?)$'
        }) {
            $target = Join-Path $outputRoot $entry.FullName
            if (-not (Test-Path -LiteralPath $target)) {
                New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
            }
        }
    } finally {
        $archive.Dispose()
    }
}

$options = Import-PowerShellDataFile -LiteralPath $optionsPath
$matrix = Import-PowerShellDataFile -LiteralPath (Join-Path $workspaceRoot 'config/minecraft-release-version-matrix.psd1')
$configuration = @{
    rules = @($options.FileRules | Where-Object { $_.Path -notlike '*better_moss_legacy/*' })
    variants = @($options.FileVariants | Where-Object { $_.SourcePath -notlike 'variants/legacy-solid/*' })
    versions = @($matrix.Versions | ForEach-Object Id)
}
[IO.File]::WriteAllText((Join-Path $cacheRoot 'config.json'), ($configuration | ConvertTo-Json -Depth 20), $encoding)
& node (Join-Path $PSScriptRoot 'moss-legacy-geometry.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Legacy geometry generation failed.' }
& node (Join-Path $PSScriptRoot 'moss-legacy-geometry.cjs') --check
if ($LASTEXITCODE -ne 0) { throw 'Legacy geometry validation failed.' }

$generated = Get-Content -LiteralPath (Join-Path $cacheRoot 'generated.json') -Raw | ConvertFrom-Json
$text = Get-Content -LiteralPath $optionsPath -Raw
foreach ($label in @('GEOMETRY', 'TEXTURES')) {
    $text = [regex]::Replace($text, "(?ms)^        # BEGIN GENERATED LEGACY $label\r?\n.*?^        # END GENERATED LEGACY $label\r?\n", '')
}
$fileOptions = @{ FileVariants = @($generated.variants); FileRules = @($generated.textureRules) }
$manifestTarget = Join-Path $packRoot 'variants/legacy-solid/manifest.json'
[IO.File]::WriteAllText($manifestTarget, ($fileOptions | ConvertTo-Json -Depth 20), $encoding)
$formatCode = "const fs = require('node:fs'); const formatter = require(process.argv[1]); const file = process.argv[2]; fs.writeFileSync(file, formatter.format(formatter.parse(fs.readFileSync(file, 'utf8'))) + '\n');"
& node -e $formatCode (Join-Path $PSScriptRoot 'format-json.cjs') $manifestTarget
if ($LASTEXITCODE -ne 0) { throw 'Compatibility manifest formatting failed.' }
if ($text -notmatch 'FileOptionsPath\s*=') {
    $text = $text.Replace("    MinVersion = '1.17'", "    MinVersion = '1.17'" + [Environment]::NewLine + "    FileOptionsPath = 'variants/legacy-solid/manifest.json'")
}
[IO.File]::WriteAllText($optionsPath, $text, $encoding)
Import-PowerShellDataFile -LiteralPath $optionsPath | Out-Null
Write-Output "Updated build rules for $($generated.variants.Count) legacy model variants."
