[CmdletBinding()]
param([string[]]$Version = @('1.13', '1.17', '1.19', '1.20', '1.21.1', '1.21.4', '26.3'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Web.Extensions
$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$serializer.MaxJsonLength = [int]::MaxValue
$serializer.RecursionLimit = 200
$repo = Split-Path $PSScriptRoot -Parent

function Read-EntryJson($Entry) {
    $reader = [IO.StreamReader]::new($Entry.Open())
    try { return $serializer.DeserializeObject($reader.ReadToEnd()) } finally { $reader.Dispose() }
}
function Normalize-ResourceId([string]$Id) {
    if ($Id.Contains(':')) { return $Id }
    return 'minecraft:' + $Id
}
function Find-ModelReferences($Value) {
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.ContainsKey('model') -and $Value.model -is [string]) { Normalize-ResourceId $Value.model }
        foreach ($child in $Value.Values) { Find-ModelReferences $child }
    } elseif ($Value -is [array]) {
        foreach ($child in $Value) { Find-ModelReferences $child }
    }
}
foreach ($versionId in $Version) {
    $zipPath = Join-Path $repo "build/bushy_leaves_enhanced/bushy_leaves_enhanced-$versionId.zip"
    $zipPath = Find-PackBuildZip -BuildZipPath $zipPath -MinecraftVersion $versionId
    $vanillaPath = Join-Path $repo "cache/vanilla-asset-catalogs/dependency-data/$versionId.json"
    if (-not (Test-Path -LiteralPath $vanillaPath)) { throw "Cache official vanilla dependency definitions for $versionId before this check." }
    $vanilla = $serializer.DeserializeObject([IO.File]::ReadAllText($vanillaPath))
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $models = @{}; $paths = @{}; $references = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '^assets/minecraft/(models/item|items)/.+_leaves\.json$') { throw "Leaf item override in $versionId`: $($entry.FullName)" }
            if ($paths.ContainsKey($entry.FullName)) { throw "Duplicate ZIP path: $($entry.FullName)" }
            $paths[$entry.FullName] = $true
            if ($entry.FullName -match '^assets/([^/]+)/models/(.+)\.json$') {
                $models["$($Matches[1]):$($Matches[2])"] = Read-EntryJson $entry
            } elseif ($entry.FullName -match '^assets/[^/]+/blockstates/.+\.json$') {
                foreach ($reference in @(Find-ModelReferences (Read-EntryJson $entry))) { $null = $references.Add($reference) }
            }
        }
        $inventoryReferences = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($asset in $vanilla.JsonAssets.Keys) {
            if ($asset -notmatch '^assets/minecraft/(models/item|items)/([^/]+_leaves)\.json$') { continue }
            $kind = $Matches[1]; $name = $Matches[2]
            if (-not $models.ContainsKey("minecraft:block/$name")) { continue }
            if ($kind -eq 'models/item') {
                $null = $inventoryReferences.Add("minecraft:item/$name")
            } else {
                foreach ($reference in @(Find-ModelReferences ($serializer.DeserializeObject($vanilla.JsonAssets[$asset])))) { $null = $inventoryReferences.Add($reference) }
            }
        }
        foreach ($reference in $inventoryReferences) { $null = $references.Add($reference) }
        foreach ($reference in $references) {
            $chain = New-Object 'System.Collections.Generic.List[object]'
            $seen = @{}; $current = $reference
            while ($current) {
                if ($seen.ContainsKey($current)) { throw "Cyclic packaged model $current" }
                $seen[$current] = $true
                $model = $models[$current]
                if (-not $model) {
                    $parts = $current.Split(':')
                    $asset = "assets/$($parts[0])/models/$($parts[1]).json"
                    if (-not $vanilla.JsonAssets.ContainsKey($asset)) { throw "Missing parent $current in $versionId" }
                    $model = $serializer.DeserializeObject($vanilla.JsonAssets[$asset])
                }
                $chain.Add($model)
                $current = if ($model.ContainsKey('parent')) { Normalize-ResourceId $model.parent } else { $null }
            }
            $textures = @{}; $elements = @()
            for ($index = $chain.Count - 1; $index -ge 0; $index--) {
                $model = $chain[$index]
                if ($model.ContainsKey('textures')) { foreach ($key in $model.textures.Keys) { $textures[$key] = $model.textures[$key] } }
                if ($model.ContainsKey('elements')) { $elements = $model.elements }
            }
            if ($inventoryReferences.Contains($reference)) {
                if ($elements.Count -le 1) { throw "Leaf item $reference is missing bushy geometry for $versionId" }
            }
            foreach ($element in $elements) { foreach ($face in $element.faces.Values) {
                $texture = $face.texture; $aliases = @{}
                while ($texture.StartsWith('#')) {
                    if ($aliases.ContainsKey($texture)) { throw "Texture alias cycle in $reference" }
                    $aliases[$texture] = $true
                    $texture = $textures[$texture.Substring(1)]
                    if (-not $texture) { throw "Unbound texture in $reference for $versionId" }
                }
                $parts = (Normalize-ResourceId $texture).Split(':')
                $asset = "assets/$($parts[0])/textures/$($parts[1]).png"
                if (-not $paths.ContainsKey($asset) -and -not $vanilla.Paths.ContainsKey($asset)) { throw "Missing texture $asset in $versionId" }
            } }
        }
        # Every vanilla leaf override must refer to a leaf actually present in
        # this client, including wrappers not directly used in blockstates.
        foreach ($modelId in $models.Keys) {
            if ($modelId -notmatch '^minecraft:block/(?:bushy_leaves_enhanced/)?[^/]+$') { continue }
            $model = $models[$modelId]
            if ($model.ContainsKey('textures') -and $model.textures.ContainsKey('all')) {
                $parts = (Normalize-ResourceId $model.textures.all).Split(':')
                $asset = "assets/$($parts[0])/textures/$($parts[1]).png"
                if (-not $vanilla.Paths.ContainsKey($asset)) { throw "Future leaf texture leaked into ${versionId}: $asset" }
            }
        }
        Write-Output "${versionId}: $($references.Count) block/item model references, bushy leaf inventory shapes, texture bindings and version gates passed."
    } finally { $zip.Dispose() }
}
