[CmdletBinding()]
param([string[]]$Version = @('1.13', '1.15.1', '1.15.2', '1.16.5', '1.18.2', '1.21.1', '1.21.2', '26.2', '26.3'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repoRoot = Split-Path $PSScriptRoot -Parent
$packRoot = Join-Path $repoRoot 'resource_packs/alternative_ores'
$matrix = Import-PowerShellDataFile (Join-Path $repoRoot 'config/minecraft-release-version-matrix.psd1')
$order = @{}
for ($index = 0; $index -lt $matrix.Versions.Count; $index++) { $order[$matrix.Versions[$index].Id] = $index }
$rules = Get-Content (Join-Path $packRoot 'variants/ore-versions.json') -Raw | ConvertFrom-Json
$variants = @{}
foreach ($variant in $rules.FileVariants | Where-Object { $_.SourcePath.StartsWith('variants/legacy-lighting/') }) { $variants[$variant.Path] = $variant.SourcePath }
foreach ($versionId in $Version) {
    if (-not $order.ContainsKey($versionId)) { throw "Unknown version: $versionId" }
    $legacy = $order[$versionId] -lt $order['1.21.2']
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $repoRoot "build/alternative_ores/alternative_ores-$versionId.zip"))
    try {
        $assetEntries = @($zip.Entries | Where-Object { $_.FullName.StartsWith('assets/') -and -not $_.FullName.EndsWith('/') })
        $names = @($assetEntries.FullName)
        if (-not $legacy -and @($names | Where-Object { $_ -like '*/legacy_lighting/*' }).Count) { throw "Legacy helper leaked into $versionId" }
        $checkedVariants = 0
        foreach ($entry in $assetEntries) {
            $source = $entry.FullName
            if ($legacy -and $variants.ContainsKey($source)) { $source = $variants[$source]; $checkedVariants++ }
            $expectedPath = Join-Path $packRoot $source
            if (-not (Test-Path -LiteralPath $expectedPath)) { throw "Unexpected packaged asset: $($entry.FullName)" }
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($hash -ne (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash) { throw "Wrong asset bytes in $versionId`: $($entry.FullName)" }
            if ($entry.FullName -like 'assets/*/blockstates/*.json') {
                $reader = [IO.StreamReader]::new($entry.Open())
                try { $state = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
                $base = $state.multipart[0].apply.model
                if ($base.Contains('/legacy_lighting/') -ne $legacy) { throw "Wrong multipart AO selection in $versionId" }
                if ($legacy) {
                    $basePath = 'assets/' + $base.Replace(':', '/models/') + '.json'
                    if ($basePath -notin $names) { throw "Missing AO wrapper in $versionId" }
                    $baseEntry = $zip.GetEntry($basePath)
                    $reader = [IO.StreamReader]::new($baseEntry.Open())
                    try { $baseJson = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
                    if ($baseJson.PSObject.Properties['parent'] -or $baseJson.ambientocclusion -ne $false) { throw "Legacy AO setting would be overridden by a parent in $versionId" }
                }
            }
        }
        if ($legacy -and $checkedVariants -eq 0) { throw "No fallback variants applied in $versionId" }
        Write-Output "Verified $versionId`: $($assetEntries.Count) packaged assets match their exact expected bytes; $checkedVariants legacy lighting variants."
    }
    finally { $zip.Dispose() }
}
