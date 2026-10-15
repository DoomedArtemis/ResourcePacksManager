# Dependency handling belongs only to the combined builder; normal sources are untouched.
Add-Type -AssemblyName System.Web.Extensions
$script:combinedJsonSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:combinedJsonSerializer.MaxJsonLength = [int]::MaxValue
$script:combinedJsonSerializer.RecursionLimit = 200

function ConvertFrom-CombinedJson {
    param([string]$Json)
    # Windows PowerShell's ConvertFrom-Json rejects the empty variant key in vanilla blockstates.
    # Retain native dictionaries/arrays: recursive PowerShell conversion is very slow
    # for the large detailed Moss models, and can collapse singleton JSON arrays.
    return $script:combinedJsonSerializer.DeserializeObject($Json)
}

function Get-CombinedVanillaDependencies {
    param([string]$RepoRoot, $Config, $VersionConfig)
    $cacheRoot = Resolve-FullPath -BasePath $RepoRoot -Path $Config.VanillaCatalogCacheRoot
    $cachePath = Join-Path $cacheRoot "dependency-data/$($VersionConfig.Id).json"
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        $cached = ConvertFrom-CombinedJson ([IO.File]::ReadAllText($cachePath))
        return @{ Version = $cached.Version; Paths = $cached.Paths; JsonAssets = $cached.JsonAssets }
    }
    $jarPath = Join-Path $env:APPDATA ".minecraft/versions/$($VersionConfig.Id)/$($VersionConfig.Id).jar"
    $downloaded = $false
    if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf)) {
        $manifestPath = Join-Path $cacheRoot 'version_manifest_v2.json'
        $manifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } else { Get-MojangVersionManifest -RepoRoot $RepoRoot -Config $Config }
        $version = @($manifest.versions | Where-Object { $_.id -eq $VersionConfig.Id })
        if ($version.Count -ne 1) { throw "No official client metadata for Minecraft $($VersionConfig.Id)." }
        Write-Host "Caching vanilla dependency definitions for Minecraft $($VersionConfig.Id)..."
        $metadata = Invoke-WebRequest -UseBasicParsing -Uri $version[0].url -TimeoutSec 60 | Select-Object -ExpandProperty Content | ConvertFrom-Json
        $jarPath = Join-Path ([IO.Path]::GetTempPath()) ('combined-client-' + [Guid]::NewGuid().ToString('N') + '.jar')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $metadata.downloads.client.url -OutFile $jarPath -TimeoutSec 120
            if ((Get-FileHash -LiteralPath $jarPath -Algorithm SHA1).Hash -ine $metadata.downloads.client.sha1) { throw 'Official client JAR checksum mismatch.' }
        }
        catch {
            if (Test-Path -LiteralPath $jarPath) { Remove-Item -LiteralPath $jarPath -Force }
            throw
        }
        $downloaded = $true
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($jarPath)
    try {
        $data = @{ Version = $VersionConfig.Id; Paths = @{}; JsonAssets = @{} }
        foreach ($entry in $archive.Entries) {
            $path = $entry.FullName
            if (-not $path.StartsWith('assets/') -or $path.EndsWith('/')) { continue }
            $data.Paths[$path] = $true
            if ($path -match '^assets/[^/]+/(models|blockstates|items)/.+\.json$') {
                $reader = [IO.StreamReader]::new($entry.Open())
                try { $data.JsonAssets[$path] = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
        }
        Ensure-Directory -Path (Split-Path $cachePath -Parent)
        $data | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8
        return $data
    }
    finally {
        $archive.Dispose()
        if ($downloaded) { Remove-Item -LiteralPath $jarPath -Force }
    }
}

function Read-CombinedComponent {
    param([string]$ZipPath, [hashtable]$Entry, [hashtable]$Definition, [string]$Root, [hashtable]$Validation, [hashtable]$VersionConfig)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $component = @{ Entry = $Entry; Files = @{}; Included = @{}; Notices = @{} }
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $paths = @{}
        foreach ($file in $archive.Entries) {
            $path = $file.FullName.Replace('\', '/')
            if ($path.EndsWith('/')) { continue }
            if ($path.StartsWith('/') -or $path.Split('/') -contains '..' -or $path.Contains(':')) { throw "Unsafe component path '$path'." }
            if ($paths.ContainsKey($path)) { throw "Duplicate archive output path '$path' in '$ZipPath'." }
            $paths[$path] = $true
            if ($Validation) {
                if ($Validation.RequireLowercasePaths -and $path.StartsWith('assets/') -and $path -cmatch '[A-Z]') { throw "Output path contains uppercase characters: $path" }
                if (($Validation.ParseJsonFiles -and $path.EndsWith('.json')) -or ($Validation.ParseMcmetaFiles -and $path.EndsWith('.mcmeta'))) {
                    $reader = [IO.StreamReader]::new($file.Open())
                    try { $null = ConvertFrom-CombinedJson ($reader.ReadToEnd()) }
                    catch { throw "Invalid JSON in component '$($Entry.Name)' at '$path': $($_.Exception.Message)" }
                    finally { $reader.Dispose() }
                }
            }
            if ($path -notmatch '/' -and $path -imatch '^(credits?|license|licence|copying|notice)(\.[a-z0-9_-]+)?$') {
                Ensure-Directory -Path $Root
                $noticePath = Join-Path $Root $path
                [IO.Compression.ZipFileExtensions]::ExtractToFile($file, $noticePath, $true)
                $component.Notices[$path] = $noticePath
                continue
            }
            if (-not $path.StartsWith('assets/') -or $path.EndsWith('/')) { continue }
            if ($path.Split('/') -contains '..' -or $path.Contains(':')) { throw "Unsafe component path '$path'." }
            $destination = Join-Path $Root $path
            Ensure-Directory -Path (Split-Path $destination -Parent)
            [IO.Compression.ZipFileExtensions]::ExtractToFile($file, $destination, $true)
            $component.Files[$path] = $destination
            if (Test-CombinedPath -Path $path -Entry $Entry -Definition $Definition) { $component.Included[$path] = $true }
        }
        if ($Validation -and $Validation.RequireTextureForTextureMcmeta) {
            foreach ($path in $paths.Keys) {
                if ($path.EndsWith('.png.mcmeta') -and -not $paths.ContainsKey($path.Substring(0, $path.Length - '.mcmeta'.Length))) { throw "Texture metadata file is missing its texture pair: $path" }
            }
        }
        if ($VersionConfig) {
            foreach ($rule in @($VersionConfig['Required'])) {
                if ($null -eq $rule) { continue }
                $matched = $false
                foreach ($path in $paths.Keys) { if (Test-RuleMatch -Path $path -Rule $rule) { $matched = $true; break } }
                if (-not $matched) { throw "Required output rule missing for pack '$($Entry.Name)' version '$($VersionConfig.Id)': $rule" }
            }
        }
    }
    finally { $archive.Dispose() }
    return $component
}

function Convert-CombinedResourcePath {
    param([string]$Id, [ValidateSet('models', 'textures')][string]$Kind)
    if ($Id -cnotmatch '^(?:[a-z0-9_.-]+:)?[a-z0-9_./-]+$' -or $Id.Split('/') -contains '..') { throw "Invalid $Kind resource location '$Id'." }
    $parts = $Id.Split(':')
    $namespace = 'minecraft'
    $relative = $Id
    if ($parts.Count -eq 2) { $namespace = $parts[0]; $relative = $parts[1] }
    $extension = if ($Kind -eq 'models') { '.json' } else { '.png' }
    return "assets/$namespace/$Kind/$relative$extension"
}

function Get-CombinedModelIds {
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            if ($key -eq 'model' -and $Node[$key] -is [string]) { Write-Output $Node[$key] }
            elseif ($Node[$key] -isnot [string]) { Get-CombinedModelIds -Node $Node[$key] }
        }
    }
    elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($value in $Node) { Get-CombinedModelIds -Node $value }
    }
}

function Get-CombinedJson {
    param([hashtable]$Context, [string]$Pack, [string]$Path)
    $key = "$Pack|$Path"
    if (-not $Context.Documents.ContainsKey($key)) {
        $raw = if ($Pack -eq '@vanilla') { $Context.Vanilla.JsonAssets[$Path] } else { Get-Content -LiteralPath $Context.Components[$Pack].Files[$Path] -Raw -Encoding UTF8 }
        $Context.Documents[$key] = ConvertFrom-CombinedJson $raw
        if ($Context.Documents[$key] -isnot [System.Collections.IDictionary]) { throw "Dependency JSON must be an object: $Pack/$Path" }
    }
    return $Context.Documents[$key]
}

function Get-CombinedVanillaModelClosure {
    param([hashtable]$Context, [string]$Path, [hashtable]$Seen)
    if ($Seen.ContainsKey($Path)) { return }
    $Seen[$Path] = $true
    if (-not $Context.Vanilla.JsonAssets.ContainsKey($Path)) { return }
    $document = Get-CombinedJson -Context $Context -Pack '@vanilla' -Path $Path
    if ($document.ContainsKey('parent') -and $document.parent -notmatch '^(minecraft:)?builtin/') {
        Get-CombinedVanillaModelClosure -Context $Context -Path (Convert-CombinedResourcePath $document.parent 'models') -Seen $Seen
    }
    foreach ($model in @(Get-CombinedModelIds $document)) {
        Get-CombinedVanillaModelClosure -Context $Context -Path (Convert-CombinedResourcePath $model 'models') -Seen $Seen
    }
}

function Add-CombinedTextureWarning {
    param([hashtable]$Context, [string]$Type, [string]$Reference, [string]$Chain, [string]$ModelKey)
    $key = "$Type|$ModelKey|$Reference"
    if (-not $Context.TextureWarnings.ContainsKey($key)) {
        $Context.TextureWarnings[$key] = @{ Type = $Type; Reference = $Reference; Context = $Chain; Model = $ModelKey }
    }
}

function Resolve-CombinedDependencySource {
    param([hashtable]$Context, [string]$Pack, [string]$Path, [string]$Chain, [switch]$AllowMissingTexture)
    # References use the same priority winner as files, including inventory parents.
    if ($Context.OriginalOwners.ContainsKey($Path)) { return [string]$Context.OriginalOwners[$Path].Pack }
    if ($Context.Components.ContainsKey($Pack) -and $Context.Components[$Pack].Files.ContainsKey($Path)) {
        if (-not $Context.Components[$Pack].Included.ContainsKey($Path)) { throw "Excluded dependency: $Chain -> $Path (required from '$Pack')." }
        return $Pack
    }
    if ($Context.Vanilla.Paths.ContainsKey($Path)) { return '@vanilla' }
    if ($AllowMissingTexture) {
        Add-CombinedTextureWarning -Context $Context -Type 'MissingTexture' -Reference $Path -Chain $Chain -ModelKey $Pack
        return ''
    }
    throw "Missing dependency: $Chain -> $Path (Minecraft $($Context.Vanilla.Version), pack '$Pack')."
}

function Get-CombinedPrivateLocation {
    param([hashtable]$Context, [string]$Pack, [string]$Path)
    if ($Path -notmatch '^assets/([^/]+)/(models|textures)/(.+)\.(json|png)$') { throw "Cannot isolate '$Path'." }
    $provider = if ($Pack -eq '@vanilla') { 'vanilla' } else { $Pack }
    $namespace = $Matches[1]
    $kind = $Matches[2]
    $originalPath = $Matches[3]
    $extension = $Matches[4]
    $relative = "pack_dependencies/$provider/$namespace/$originalPath"
    # Modern vanilla block atlases discover textures under block/ and item/.
    if ($kind -eq 'textures') { $relative = "block/$relative" }
    return @{ Path = "assets/$($Context.Name)/$kind/$relative.$extension"; Id = "$($Context.Name):$relative" }
}

function Get-CombinedCanonicalLocation {
    param([string]$Path)
    if ($Path -notmatch '^assets/([^/]+)/(models|textures)/(.+)\.(json|png)$') { throw "Invalid canonical resource path: $Path" }
    return @{ Path = $Path; Id = "$($Matches[1]):$($Matches[3])" }
}

function Test-CombinedJsonEqual {
    param($Left, $Right)
    if ($Left -is [System.Collections.IDictionary]) {
        if ($Right -isnot [System.Collections.IDictionary] -or $Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) { if (-not $Right.ContainsKey($key) -or -not (Test-CombinedJsonEqual $Left[$key] $Right[$key])) { return $false } }
        return $true
    }
    if ($Left -is [array]) {
        if ($Right -isnot [array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($index = 0; $index -lt $Left.Count; $index++) { if (-not (Test-CombinedJsonEqual $Left[$index] $Right[$index])) { return $false } }
        return $true
    }
    return $Left -ceq $Right
}

function Get-CombinedModelReference {
    param([string]$OriginalId, [hashtable]$Resolved)
    if (-not $Resolved.Path -or (Convert-CombinedResourcePath $OriginalId 'models') -eq $Resolved.Path) { return $OriginalId }
    return $Resolved.Id
}

function Get-CombinedJsonStringEdits {
    param($Tokens, [ref]$Cursor, $Original, $Edited, $Edits)
    $token = $Tokens[$Cursor.Value]
    if ($token.Value -eq '{') {
        $Cursor.Value++
        while ($Tokens[$Cursor.Value].Value -ne '}') {
            $key = $script:combinedJsonSerializer.DeserializeObject($Tokens[$Cursor.Value].Value)
            $Cursor.Value += 2 # property name and colon
            Get-CombinedJsonStringEdits $Tokens $Cursor $Original[$key] $Edited[$key] $Edits
            if ($Tokens[$Cursor.Value].Value -eq ',') { $Cursor.Value++ }
        }
        $Cursor.Value++
    }
    elseif ($token.Value -eq '[') {
        $Cursor.Value++
        $index = 0
        while ($Tokens[$Cursor.Value].Value -ne ']') {
            Get-CombinedJsonStringEdits $Tokens $Cursor $Original[$index] $Edited[$index] $Edits
            $index++
            if ($Tokens[$Cursor.Value].Value -eq ',') { $Cursor.Value++ }
        }
        $Cursor.Value++
    }
    else {
        if ($Original -is [string] -and $Edited -is [string] -and $Original -cne $Edited) {
            $Edits.Add(@{ Index = $token.Index; Length = $token.Length; Value = $script:combinedJsonSerializer.Serialize($Edited) })
        }
        $Cursor.Value++
    }
}

function Write-CombinedDependencyJson {
    param([hashtable]$Context, [string]$Provider, [string]$SourcePath, $Edited, [string]$OutputPath)
    $original = Get-CombinedJson $Context $Provider $SourcePath
    $changed = $script:combinedJsonSerializer.Serialize($original) -cne $script:combinedJsonSerializer.Serialize($Edited)
    $output = Join-Path $Context.Destination $OutputPath
    Ensure-Directory -Path (Split-Path $output -Parent)
    if (-not $changed -and $Provider -ne '@vanilla') {
        Copy-Item -LiteralPath $Context.Components[$Provider].Files[$SourcePath] -Destination $output -Force
        return
    }
    $raw = if ($Provider -eq '@vanilla') { $Context.Vanilla.JsonAssets[$SourcePath] } else { Get-Content -LiteralPath $Context.Components[$Provider].Files[$SourcePath] -Raw -Encoding UTF8 }
    if ($changed) {
        # Change only reference string tokens, retaining indentation, property order,
        # inline faces, numeric spelling, and line endings from the original JSON.
        $tokens = [regex]::Matches($raw, '"(?:\\.|[^"\\])*"|true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[{}\[\]:,]')
        $cursor = 0
        $edits = New-Object 'System.Collections.Generic.List[object]'
        Get-CombinedJsonStringEdits $tokens ([ref]$cursor) $original $Edited $edits
        $text = [Text.StringBuilder]::new($raw)
        foreach ($edit in @($edits | Sort-Object Index -Descending)) { $null = $text.Remove($edit.Index, $edit.Length).Insert($edit.Index, $edit.Value) }
        $raw = $text.ToString()
    }
    $hasBom = $false
    if ($Provider -ne '@vanilla') {
        $bytes = [IO.File]::ReadAllBytes($Context.Components[$Provider].Files[$SourcePath])
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    }
    [IO.File]::WriteAllText($output, $raw, [Text.UTF8Encoding]::new($hasBom))
}

function Resolve-CombinedTexture {
    param([hashtable]$Context, [string]$Pack, [string]$Id, [string]$Chain)
    $path = Convert-CombinedResourcePath $Id 'textures'
    $provider = Resolve-CombinedDependencySource $Context $Pack $path $Chain -AllowMissingTexture
    if (-not $provider) { return $Id }
    if ($provider -eq '@vanilla' -or ($Context.OriginalOwners.ContainsKey($path) -and $Context.OriginalOwners[$path].Pack -eq $provider)) { return $Id }
    if ($Context.OriginalOwners.ContainsKey($path)) {
        $winner = $Context.OriginalOwners[$path].Pack
        $sourceHash = (Get-FileHash -LiteralPath $Context.Components[$provider].Files[$path] -Algorithm SHA256).Hash
        $winnerHash = (Get-FileHash -LiteralPath $Context.Components[$winner].Files[$path] -Algorithm SHA256).Hash
        $sidecar = "$path.mcmeta"
        $sourceHasMeta = $Context.Components[$provider].Files.ContainsKey($sidecar)
        $winnerHasMeta = $Context.Components[$winner].Files.ContainsKey($sidecar)
        if ($sourceHasMeta -and -not $Context.Components[$provider].Included.ContainsKey($sidecar)) { throw "Excluded dependency: $Chain -> $sidecar" }
        $sameMeta = $sourceHasMeta -eq $winnerHasMeta
        if ($sameMeta -and $sourceHasMeta) { $sameMeta = (Get-FileHash -LiteralPath $Context.Components[$provider].Files[$sidecar]).Hash -eq (Get-FileHash -LiteralPath $Context.Components[$winner].Files[$sidecar]).Hash }
        if ($sourceHash -eq $winnerHash -and $sameMeta) { return $Id }
    }
    $location = Get-CombinedPrivateLocation $Context $provider $path
    if (-not $Context.Owners.ContainsKey($location.Path)) {
        if ($Context.OriginalOwners.ContainsKey($location.Path)) { throw "Reserved dependency output path already exists: $($location.Path)" }
        $destination = Join-Path $Context.Destination $location.Path
        Ensure-Directory -Path (Split-Path $destination -Parent)
        Copy-Item -LiteralPath $Context.Components[$provider].Files[$path] -Destination $destination
        $Context.Owners[$location.Path] = @{ Pack = $provider; Priority = $Context.Components[$provider].Entry.Priority; DependencyOf = $Chain; SourcePath = $path }
        $sidecar = "$path.mcmeta"
        if ($Context.Components[$provider].Files.ContainsKey($sidecar)) {
            if (-not $Context.Components[$provider].Included.ContainsKey($sidecar)) { throw "Excluded dependency: $Chain -> $sidecar" }
            Copy-Item -LiteralPath $Context.Components[$provider].Files[$sidecar] -Destination "$destination.mcmeta"
            $Context.Owners["$($location.Path).mcmeta"] = @{ Pack = $provider; Priority = $Context.Components[$provider].Entry.Priority; SourcePath = $sidecar }
        }
    }
    return $location.Id
}

function Update-CombinedModelReferences {
    param([hashtable]$Context, [string]$Pack, $Node, [string]$Chain)
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            if ($key -eq 'model' -and $Node[$key] -is [string]) {
                $resolved = Resolve-CombinedModel $Context $Pack $Node[$key] $Chain
                Assert-CombinedTextureVariables $resolved "$Chain -> $($Node[$key])" $Context
                $Node[$key] = Get-CombinedModelReference $Node[$key] $resolved
            }
            elseif ($Node[$key] -isnot [string]) { Update-CombinedModelReferences $Context $Pack $Node[$key] $Chain }
        }
    }
    elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($value in $Node) { Update-CombinedModelReferences $Context $Pack $value $Chain }
    }
}

function Resolve-CombinedModel {
    param([hashtable]$Context, [string]$Pack, [string]$Id, [string]$Chain)
    if ($Id -match '^(minecraft:)?builtin/') {
        if ($Id -notmatch '^(minecraft:)?builtin/(generated|entity)$') { throw "Unknown built-in model '$Id': $Chain" }
        return @{ Id = $Id; Textures = @{}; Elements = @(); Builtin = $true; Path = ''; Key = $Id }
    }
    $path = Convert-CombinedResourcePath $Id 'models'
    $provider = Resolve-CombinedDependencySource $Context $Pack $path $Chain
    # Vanilla models inherit the requesting pack's changes; custom models inherit their provider's.
    $scope = if ($provider -eq '@vanilla') { $Pack } else { $provider }
    $key = "$scope|$path"
    if ($Context.Visiting.ContainsKey($key)) { throw "Model dependency cycle: $Chain -> $key" }
    if ($Context.Resolved.ContainsKey($key)) { return $Context.Resolved[$key] }
    $Context.Visiting[$key] = $true
    try {
        $chainNext = "$Chain -> $path [$scope]"
        $original = Get-CombinedJson $Context $provider $path
        # Fresh copy: the same vanilla parent can be used with different pack contexts.
        $model = ConvertFrom-CombinedJson ($script:combinedJsonSerializer.Serialize($original))
        $textures = @{}
        $elements = @()
        $builtin = $false
        if ($model.ContainsKey('parent')) {
            $parent = Resolve-CombinedModel $Context $scope $model.parent $chainNext
            $model.parent = Get-CombinedModelReference $model.parent $parent
            $textures = @{} + $parent.Textures
            $elements = @($parent.Elements)
            $builtin = $parent.Builtin
        }
        if ($model.ContainsKey('textures')) {
            foreach ($variable in @($model.textures.Keys)) {
                $value = [string]$model.textures[$variable]
                if (-not $value.StartsWith('#')) { $value = Resolve-CombinedTexture $Context $scope $value $chainNext }
                $model.textures[$variable] = $value
                $textures[$variable] = $value
            }
        }
        if ($model.ContainsKey('elements')) {
            foreach ($element in @($model.elements)) {
                if ($element.ContainsKey('faces')) {
                    foreach ($face in $element.faces.Values) {
                        if ($face.ContainsKey('texture') -and -not ([string]$face.texture).StartsWith('#')) { $face.texture = Resolve-CombinedTexture $Context $scope $face.texture $chainNext }
                    }
                }
            }
            $elements = @($model.elements)
        }
        Update-CombinedModelReferences $Context $scope $model $chainNext
        $serialized = $script:combinedJsonSerializer.Serialize($model)
        $ownsCanonical = $Context.OriginalOwners.ContainsKey($path) -and $Context.OriginalOwners[$path].Pack -eq $provider
        $usesUnchangedVanilla = $provider -eq '@vanilla' -and $serialized -ceq $script:combinedJsonSerializer.Serialize($original)
        $matchesCanonical = $Context.CanonicalDocuments.ContainsKey($path) -and (Test-CombinedJsonEqual $model $Context.CanonicalDocuments[$path])
        $location = if ($ownsCanonical -or $usesUnchangedVanilla -or $matchesCanonical) { Get-CombinedCanonicalLocation $path } else { Get-CombinedPrivateLocation $Context $scope $path }
        $priority = if ($Context.Components.ContainsKey($scope)) { $Context.Components[$scope].Entry.Priority } else { 0 }
        if ($ownsCanonical) {
            Write-CombinedDependencyJson $Context $provider $path $model $path
            $Context.CanonicalDocuments[$path] = $model
        }
        elseif (-not $usesUnchangedVanilla -and -not $matchesCanonical) {
            if ($Context.OriginalOwners.ContainsKey($location.Path)) { throw "Reserved dependency output path already exists: $($location.Path)" }
            Write-CombinedDependencyJson $Context $provider $path $model $location.Path
            $Context.Owners[$location.Path] = @{ Pack = $scope; Priority = $priority; SourcePath = $path; DependencyOf = $Chain }
        }
        $result = @{ Id = $location.Id; Path = $location.Path; Key = $key; Textures = $textures; Elements = $elements; Builtin = $builtin }
        $Context.Resolved[$key] = $result
        return $result
    }
    finally { $Context.Visiting.Remove($key) }
}

function Assert-CombinedTextureVariables {
    param([hashtable]$Model, [string]$Chain, [hashtable]$Context)
    $references = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($element in $Model.Elements) {
        if ($element.ContainsKey('faces')) { foreach ($face in $element.faces.Values) { if ($face.ContainsKey('texture')) { $null = $references.Add([string]$face.texture) } } }
    }
    if ($Model.Textures.ContainsKey('particle')) { $null = $references.Add([string]$Model.Textures.particle) }
    # All declared texture aliases must resolve in the effective child/parent context.
    foreach ($value in $Model.Textures.Values) { if (([string]$value).StartsWith('#')) { $null = $references.Add([string]$value) } }
    foreach ($reference in $references) {
        $seen = @{}
        while ($reference.StartsWith('#')) {
            $variable = $reference.Substring(1)
            if ($seen.ContainsKey($variable)) { throw "Texture variable cycle: $Chain -> #$variable" }
            $seen[$variable] = $true
            if (-not $Model.Textures.ContainsKey($variable)) {
                Add-CombinedTextureWarning -Context $Context -Type 'UnresolvedTextureVariable' -Reference "#$variable" -Chain $Chain -ModelKey $Model.Key
                break
            }
            $reference = [string]$Model.Textures[$variable]
        }
    }
}

function Get-CombinedTextureIds {
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            if ($key -eq 'textures' -and $Node[$key] -is [System.Collections.IDictionary]) {
                foreach ($value in $Node[$key].Values) { if ($value -is [string] -and -not $value.StartsWith('#')) { Write-Output $value } }
            }
            elseif ($key -eq 'texture' -and $Node[$key] -is [string] -and -not $Node[$key].StartsWith('#')) { Write-Output $Node[$key] }
            elseif ($Node[$key] -isnot [string]) { Get-CombinedTextureIds $Node[$key] }
        }
    }
    elseif ($Node -is [array]) { foreach ($value in $Node) { Get-CombinedTextureIds $value } }
}

function Remove-UnusedCombinedDependencyCopies {
    param([string]$Name, [string]$Destination, [hashtable]$Owners)
    $modelPrefix = "assets/$Name/models/pack_dependencies/"
    $texturePrefix = "assets/$Name/textures/block/pack_dependencies/"
    # With no generated copies there is nothing to prune; validation already ran.
    if (-not @($Owners.Keys | Where-Object { $_.StartsWith($modelPrefix) -or $_.StartsWith($texturePrefix) }).Count) { return }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $used = @{}
    $showProgress = $null -ne (Get-Command Show-BuildProgress -ErrorAction SilentlyContinue)
    $scanCount = 0
    $scanTotal = @($Owners.Keys | Where-Object { $_ -match '^assets/[^/]+/(models|blockstates|items)/.+\.json$' }).Count
    foreach ($path in $Owners.Keys) {
        if (-not $path.StartsWith($modelPrefix) -and $path -match '^assets/[^/]+/(models|blockstates|items)/.+\.json$') { $queue.Enqueue($path) }
    }
    while ($queue.Count) {
        $path = $queue.Dequeue()
        if ($used.ContainsKey($path)) { continue }
        if ($showProgress) { Show-BuildProgress -Id 5 -Activity 'Checking dependencies' -Stage 'Scanning references for unused dependency copies' -Completed $scanCount -Total $scanTotal }
        $scanCount++
        $used[$path] = $true
        $document = ConvertFrom-CombinedJson (Get-Content -LiteralPath (Join-Path $Destination $path) -Raw -Encoding UTF8)
        $models = @(Get-CombinedModelIds $document)
        if ($path -match '/models/' -and $document.ContainsKey('parent')) { $models += [string]$document.parent }
        foreach ($id in $models) {
            if ($id -match '^(minecraft:)?builtin/') { continue }
            $reference = Convert-CombinedResourcePath $id 'models'
            if ($reference.StartsWith($modelPrefix) -and $Owners.ContainsKey($reference)) { $queue.Enqueue($reference) }
        }
        foreach ($id in @(Get-CombinedTextureIds $document)) {
            $reference = Convert-CombinedResourcePath $id 'textures'
            if ($reference.StartsWith($texturePrefix) -and $Owners.ContainsKey($reference)) {
                $used[$reference] = $true
                if ($Owners.ContainsKey("$reference.mcmeta")) { $used["$reference.mcmeta"] = $true }
            }
        }
    }
    foreach ($path in @($Owners.Keys)) {
        if (($path.StartsWith($modelPrefix) -or $path.StartsWith($texturePrefix)) -and -not $used.ContainsKey($path)) {
            Remove-Item -LiteralPath (Join-Path $Destination $path) -Force
            $Owners.Remove($path)
        }
    }
}

function Complete-CombinedDependencies {
    param([string]$Name, [hashtable]$Components, [hashtable]$Vanilla, [string]$Destination, [hashtable]$Owners)
    $showProgress = $null -ne (Get-Command Show-BuildProgress -ErrorAction SilentlyContinue)
    # Animation metadata follows its texture's provider, not an unrelated lower-priority PNG.
    foreach ($path in @($Owners.Keys | Where-Object { $_ -match '^assets/[^/]+/textures/.+\.png$' })) {
        $provider = $Owners[$path].Pack
        $sidecar = "$path.mcmeta"
        if ($Components[$provider].Files.ContainsKey($sidecar)) {
            if (-not $Components[$provider].Included.ContainsKey($sidecar)) { throw "Excluded texture animation dependency: $path -> $sidecar (pack '$provider')." }
            $target = Join-Path $Destination $sidecar
            Copy-Item -LiteralPath $Components[$provider].Files[$sidecar] -Destination $target -Force
            $Owners[$sidecar] = @{ Pack = $provider; Priority = $Components[$provider].Entry.Priority }
        }
        elseif ($Owners.ContainsKey($sidecar)) {
            Remove-Item -LiteralPath (Join-Path $Destination $sidecar) -Force
            $Owners.Remove($sidecar)
        }
    }
    $context = @{ Name = $Name; Components = $Components; Vanilla = $Vanilla; Destination = $Destination; Owners = $Owners;
        OriginalOwners = @{} + $Owners; Documents = @{}; CanonicalDocuments = @{}; Resolved = @{}; Visiting = @{}; TextureWarnings = @{} }
    # Resolve normal output models first so identical alternate contexts can share them.
    $modelPaths = @($context.OriginalOwners.Keys | Where-Object { $_ -match '^assets/[^/]+/models/.+\.json$' } | Sort-Object @{ Expression = { $context.OriginalOwners[$_].Priority }; Descending = $true }, @{ Expression = { $_ } })
    $dependencyIndex = 0
    foreach ($path in $modelPaths) {
        if ($showProgress) { Show-BuildProgress -Id 5 -Activity 'Checking dependencies' -Stage 'Resolving models and textures' -Completed $dependencyIndex -Total $modelPaths.Count }
        $dependencyIndex++
        $pack = $context.OriginalOwners[$path].Pack
        $id = (Get-CombinedCanonicalLocation $path).Id
        $model = Resolve-CombinedModel $context $pack $id $path
        if ($path -match '/models/item/') { Assert-CombinedTextureVariables $model $path $context }
    }
    $states = @{}
    foreach ($pack in $Components.Keys) {
        foreach ($path in $Components[$pack].Included.Keys) {
            if ($path -match '^assets/[^/]+/blockstates/.+\.json$') {
                $candidate = @{ Pack = $pack; Priority = $Components[$pack].Entry.Priority; Source = $pack; Implicit = $false }
                if (-not $states.ContainsKey($path) -or $states[$path].Priority -lt $candidate.Priority) { $states[$path] = $candidate }
                elseif ($states[$path].Priority -eq $candidate.Priority) { throw "Equal priority blockstate conflict: $path" }
            }
        }
    }
    # A model-only pack implicitly uses the version's vanilla blockstate for that block.
    $vanillaStates = @($Vanilla.JsonAssets.Keys | Where-Object { $_ -match '^assets/[^/]+/blockstates/.+\.json$' })
    $dependencyIndex = 0
    foreach ($path in $vanillaStates) {
        if ($showProgress) { Show-BuildProgress -Id 5 -Activity 'Checking dependencies' -Stage 'Checking vanilla blockstate relationships' -Completed $dependencyIndex -Total $vanillaStates.Count }
        $dependencyIndex++
        $state = Get-CombinedJson $context '@vanilla' $path
        $closure = @{}
        foreach ($id in @(Get-CombinedModelIds $state)) { Get-CombinedVanillaModelClosure $context (Convert-CombinedResourcePath $id 'models') $closure }
        foreach ($pack in $Components.Keys) {
            if ($Components[$pack].Files.ContainsKey($path)) { continue }
            $affected = $false
            foreach ($modelPath in $closure.Keys) { if ($Components[$pack].Included.ContainsKey($modelPath)) { $affected = $true; break } }
            if (-not $affected) { continue }
            $candidate = @{ Pack = $pack; Priority = $Components[$pack].Entry.Priority; Source = '@vanilla'; Implicit = $true }
            if (-not $states.ContainsKey($path) -or $states[$path].Priority -lt $candidate.Priority) { $states[$path] = $candidate }
            elseif ($states[$path].Priority -eq $candidate.Priority -and $states[$path].Pack -ne $pack) { throw "Equal priority blockstate conflict: $path" }
        }
    }
    $dependencyIndex = 0
    foreach ($path in $states.Keys) {
        if ($showProgress) { Show-BuildProgress -Id 5 -Activity 'Checking dependencies' -Stage 'Resolving winning blockstates' -Completed $dependencyIndex -Total $states.Count }
        $dependencyIndex++
        $winner = $states[$path]
        $document = ConvertFrom-CombinedJson ($script:combinedJsonSerializer.Serialize((Get-CombinedJson $context $winner.Source $path)))
        foreach ($id in @(Get-CombinedModelIds $document)) {
            $model = Resolve-CombinedModel $context $winner.Pack $id $path
            Assert-CombinedTextureVariables $model "$path -> $id" $context
        }
        Update-CombinedModelReferences $context $winner.Pack $document $path
        $needsOutput = $winner.Source -ne '@vanilla' -or $context.OriginalOwners.ContainsKey($path) -or $script:combinedJsonSerializer.Serialize($document) -cne $script:combinedJsonSerializer.Serialize((Get-CombinedJson $context '@vanilla' $path))
        if ($needsOutput) {
            Write-CombinedDependencyJson $context $winner.Source $path $document $path
            $Owners[$path] = @{ Pack = $winner.Pack; Priority = $winner.Priority; ImplicitVanillaBlockstate = $winner.Implicit }
        }
    }
    if ($showProgress) { Show-BuildProgress -Id 5 -Activity 'Checking dependencies' -Stage 'Checking item models and removing unused copies' }
    foreach ($path in @($context.OriginalOwners.Keys | Where-Object { $_ -match '^assets/[^/]+/items/.+\.json$' })) {
        $pack = $context.OriginalOwners[$path].Pack
        $document = ConvertFrom-CombinedJson ($script:combinedJsonSerializer.Serialize((Get-CombinedJson $context $pack $path)))
        foreach ($id in @(Get-CombinedModelIds $document)) {
            $model = Resolve-CombinedModel $context $pack $id $path
            Assert-CombinedTextureVariables $model "$path -> $id" $context
        }
        Update-CombinedModelReferences $context $pack $document $path
        Write-CombinedDependencyJson $context $pack $path $document $path
    }
    Remove-UnusedCombinedDependencyCopies -Name $Name -Destination $Destination -Owners $Owners
    $warnings = @($context.TextureWarnings.Keys | Sort-Object | ForEach-Object { $context.TextureWarnings[$_] })
    $status = if ($warnings.Count) { 'passed_with_warnings' } else { 'passed' }
    return @{ Blockstates = $states; ResolvedModelCount = $context.Resolved.Count; Status = $status; TextureWarnings = $warnings }
}
