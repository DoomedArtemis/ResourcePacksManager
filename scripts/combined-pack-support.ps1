# Shared discovery for builds and publishers. Definitions stay outside resource_packs.
function ConvertFrom-PublishStateAst {
    param([Management.Automation.Language.Ast]$Node)
    # Windows PowerShell's SafeGetValue limits the size of one expression. Read
    # containers separately, retaining safe literal evaluation for every leaf.
    if ($Node -is [Management.Automation.Language.HashtableAst]) {
        $result = @{}
        foreach ($pair in $Node.KeyValuePairs) {
            $key = $pair.Item1.SafeGetValue()
            $result[$key] = ConvertFrom-PublishStateAst $pair.Item2
        }
        return $result
    }
    if ($Node -is [Management.Automation.Language.ArrayExpressionAst] -or $Node -is [Management.Automation.Language.ArrayLiteralAst]) {
        $values = New-Object System.Collections.Generic.List[object]
        $elements = if ($Node -is [Management.Automation.Language.ArrayExpressionAst]) { $Node.SubExpression.Statements } else { $Node.Elements }
        foreach ($element in $elements) { $values.Add((ConvertFrom-PublishStateAst $element)) }
        return ,$values.ToArray()
    }
    if ($Node -is [Management.Automation.Language.StatementBlockAst]) {
        if ($Node.Statements.Count -ne 1) { throw 'Expected one data expression.' }
        return ConvertFrom-PublishStateAst $Node.Statements[0]
    }
    if ($Node -is [Management.Automation.Language.PipelineAst]) {
        if ($Node.PipelineElements.Count -ne 1 -or $Node.PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst]) { throw 'Commands are not allowed in publish state.' }
        return ConvertFrom-PublishStateAst $Node.PipelineElements[0].Expression
    }
    return $Node.SafeGetValue()
}

function Read-PublishStateDataFile {
    param([string]$Path)
    try {
        $tokens = $null; $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -or $null -eq $ast.EndBlock -or $ast.EndBlock.Statements.Count -ne 1) { throw 'Expected a data table.' }
        $state = ConvertFrom-PublishStateAst $ast.EndBlock.Statements[0]
        if ($state -isnot [hashtable]) { throw 'Expected a data table.' }
        return $state
    }
    catch {
        # Parser/SafeGetValue errors can include the complete source and tokens.
        throw "Unable to read local publishing state '$Path'. It must contain a valid literal PSD1 table; state contents are omitted to protect tokens."
    }
}

function Convert-PublishVersionNumber {
    param([string]$Value)
    return ($Value -replace '-mc\.(?=[0-9])', '-mc')
}

function Convert-ArchivedPackRelease {
    param([string]$Name)
    if ($Name -notmatch '^v?(?<Core>\d+\.\d+(?:\.\d+){0,2})(?:-(?<Prerelease>[0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$') { return $null }
    $coreText = $Matches.Core
    $prerelease = $Matches['Prerelease']
    $core = $null
    if (-not [Version]::TryParse($coreText, [ref]$core)) { return $null }
    return @{ Name = $Name; Core = $core; Prerelease = $prerelease }
}

function Compare-ArchivedPackReleases {
    param([hashtable]$Left, [hashtable]$Right)
    $comparison = $Left.Core.CompareTo($Right.Core)
    if ($comparison -ne 0) { return $comparison }
    if (-not $Left.Prerelease -and -not $Right.Prerelease) { return 0 }
    if (-not $Left.Prerelease) { return 1 }
    if (-not $Right.Prerelease) { return -1 }
    $leftParts = $Left.Prerelease.Split('.')
    $rightParts = $Right.Prerelease.Split('.')
    for ($index = 0; $index -lt [Math]::Min($leftParts.Count, $rightParts.Count); $index++) {
        $leftPart = $leftParts[$index]
        $rightPart = $rightParts[$index]
        $leftNumeric = $leftPart -match '^\d+$'
        $rightNumeric = $rightPart -match '^\d+$'
        if ($leftNumeric -and $rightNumeric) {
            $leftNumber = $leftPart.TrimStart('0'); $rightNumber = $rightPart.TrimStart('0')
            $comparison = $leftNumber.Length.CompareTo($rightNumber.Length)
            if ($comparison -eq 0) { $comparison = [StringComparer]::Ordinal.Compare($leftNumber, $rightNumber) }
        }
        elseif ($leftNumeric) { $comparison = -1 }
        elseif ($rightNumeric) { $comparison = 1 }
        else { $comparison = [StringComparer]::Ordinal.Compare($leftPart, $rightPart) }
        if ($comparison -ne 0) { return $comparison }
    }
    return $leftParts.Count.CompareTo($rightParts.Count)
}

function Get-LatestArchivedPackVersion {
    param([string]$RepoRoot, [string]$PackName)
    $root = Join-Path $RepoRoot "archive/$PackName"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return 'unreleased' }
    $latest = $null
    foreach ($folder in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
        if (-not (Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.zip' | Select-Object -First 1)) { continue }
        $release = Convert-ArchivedPackRelease -Name $folder.Name
        if ($null -eq $release) { continue }
        if ($null -eq $latest -or (Compare-ArchivedPackReleases -Left $release -Right $latest) -gt 0) { $latest = $release }
    }
    if ($null -eq $latest) { return 'unreleased' }
    return $latest.Name
}

function Get-ReleaseArchiveZip {
    param([string]$Directory, [string]$PackName, [string]$ReleaseVersion, [string]$MinecraftVersion)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $null }
    $legacy = [regex]::Escape("$PackName-$ReleaseVersion-mc") + '\.?'+ [regex]::Escape($MinecraftVersion)
    $readable = '.+ ' + [regex]::Escape($ReleaseVersion) + ' MC' + [regex]::Escape($MinecraftVersion)
    $pattern = '^(?:' + $legacy + '|' + $readable + ')(?:-uploaded-[0-9]{14})?\.zip$'
    return Get-ChildItem -LiteralPath $Directory -File -Filter '*.zip' |
        Where-Object { $_.Name -match $pattern -or $MinecraftVersion -in @(Get-PackZipVersions $_.FullName) } |
        Sort-Object LastWriteTimeUtc, Name -Descending | Select-Object -First 1
}

function Get-ReleasePackDisplayName {
    param($PackDirectory, [hashtable]$PackOptions)
    if ($PackOptions.ContainsKey('PackMetadata') -and $PackOptions.PackMetadata.ContainsKey('name') -and
        -not [string]::IsNullOrWhiteSpace([string]$PackOptions.PackMetadata.name)) {
        return ([string]$PackOptions.PackMetadata.name).Trim()
    }
    if ($PackOptions.ContainsKey('DisplayName') -and $PackOptions.DisplayName) { return [string]$PackOptions.DisplayName }
    return Convert-ToPackDisplayName -PackFolderName $PackDirectory.Name
}

function Get-ReleaseZipFileName {
    param($Item)
    if ($Item.PSObject.Properties['ZipSource'] -and $Item.ZipSource -eq 'archive') {
        return [IO.Path]::GetFileName($Item.ZipPath)
    }
    $title = if ($Item.PSObject.Properties['PackDisplayName']) { [string]$Item.PackDisplayName } else { Convert-ToPackDisplayName -PackFolderName $Item.PackName }
    $minecraft = if ($Item.PSObject.Properties['MinecraftVersion']) { [string]$Item.MinecraftVersion } else { [string]$Item.VersionNumber -replace '^.*-mc\.?', '' }
    if ($Item.PSObject.Properties['ZipPath'] -and (Test-Path -LiteralPath "$($Item.ZipPath).versions.json")) {
        $null = Get-PackZipVersions $Item.ZipPath
        $minecraft = (Get-Content -LiteralPath "$($Item.ZipPath).versions.json" -Raw | ConvertFrom-Json).Label
    }
    if ([string]::IsNullOrWhiteSpace($title) -or $title -match '[<>:"/\\|?*\x00-\x1f]' -or $title -match '[. ]$') {
        throw "Invalid pack name for release ZIP: '$title'."
    }
    return "$title $($Item.ReleaseVersion) MC$minecraft.zip"
}

function Get-CombinedArchivedComponent {
    param([string]$RepoRoot, [string]$PackName, [string]$MinecraftVersion)
    $root = Join-Path $RepoRoot "archive/$PackName"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $latest = $null
    foreach ($folder in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
        $release = Convert-ArchivedPackRelease $folder.Name
        if ($null -eq $release) { continue }
        $zip = Get-ReleaseArchiveZip -Directory $folder.FullName -PackName $PackName -ReleaseVersion $folder.Name -MinecraftVersion $MinecraftVersion
        if ($null -eq $zip) { continue }
        if ($null -eq $latest -or (Compare-ArchivedPackReleases $release $latest.Release) -gt 0) {
            $latest = @{ Release = $release; ReleaseVersion = $folder.Name; ZipPath = $zip.FullName }
        }
    }
    return $latest
}

function Copy-CombinedPackDocumentation {
    param([string]$RepoRoot, [string]$DefinitionDirectory, [string]$Destination, [hashtable]$Components,
        [string]$DisplayName = 'Artemis Enhanced Visuals', [string]$MinecraftVersion = '', [string]$Description = '')
    $credits = New-Object 'System.Collections.Generic.List[string]'
    $readme = New-Object 'System.Collections.Generic.List[string]'
    $readme.Add($DisplayName)
    if ($MinecraftVersion) { $readme.Add("For Minecraft Java Edition $MinecraftVersion") }
    $readme.Add('')
    if (-not $Description) { $Description = "A collection of resource packs that enhances Minecraft's vanilla visuals while preserving its familiar style." }
    $readme.Add($Description)
    $readme.Add('')
    $readme.Add('How to use')
    $readme.Add('1. Open Minecraft and go to Options > Resource Packs > Open Pack Folder.')
    $readme.Add('2. Place this ZIP in the folder that opens.')
    $readme.Add('3. Return to Resource Packs, move this pack to Selected, and click Done.')
    $readme.Add('')
    $readme.Add('The resource packs listed below are already included. You can use this pack on its own.')
    $readme.Add('')
    $readme.Add('Included packs and versions')
    $versions = @{}
    $support = New-Object 'System.Collections.Generic.List[string]'
    $hasLicenseNotices = $false
    # The repository license remains authoritative if it changes in a future release.
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Destination (Join-Path $Destination 'license.txt') -Force
    foreach ($pack in @($Components.Keys | Sort-Object)) {
        $versions[$pack] = if ($Components[$pack].ContainsKey('ReleaseVersion')) { $Components[$pack].ReleaseVersion } else { Get-LatestArchivedPackVersion -RepoRoot $RepoRoot -PackName $pack }
        $packTitle = Convert-ToPackDisplayName -PackFolderName $pack
        if ($Components[$pack].ContainsKey('CompatibilityText') -and -not [string]::IsNullOrWhiteSpace($Components[$pack].CompatibilityText)) {
            foreach ($modName in ($Components[$pack].CompatibilityText -split '\r?\n')) {
                if (-not [string]::IsNullOrWhiteSpace($modName)) { $support.Add($modName.Trim()) }
            }
        }
        $readme.Add("$($packTitle): $($versions[$pack])")
        $creditNames = @($Components[$pack].Notices.Keys | Where-Object { $_ -imatch '^credits?(\.|$)' } | Sort-Object)
        if ($creditNames.Count) {
            $credits.Add("$($pack):")
            foreach ($name in $creditNames) { $credits.Add((Get-Content -LiteralPath $Components[$pack].Notices[$name] -Raw -Encoding UTF8).Trim()) }
            $credits.Add('')
        }
        $licenseNames = @($Components[$pack].Notices.Keys | Where-Object { $_ -inotmatch '^credits?(\.|$)' } | Sort-Object)
        foreach ($name in $licenseNames) {
            $hasLicenseNotices = $true
            $folder = Join-Path $Destination 'licenses'
            Ensure-Directory -Path $folder
            $fileName = if ($licenseNames.Count -eq 1) { "$pack.txt" } else { "$pack-$name" }
            Copy-Item -LiteralPath $Components[$pack].Notices[$name] -Destination (Join-Path $folder $fileName) -Force
        }
    }
    $readme.Add('')
    $readme.Add('Credits and license')
    $readme.Add('See credits.txt for the artists and original creators whose work is included in this pack.')
    $readme.Add('See license.txt for license information.')
    if ($hasLicenseNotices) { $readme.Add('Additional license notices are included in the licenses folder.') }
    Set-Content -LiteralPath (Join-Path $Destination 'credits.txt') -Value ($credits -join [Environment]::NewLine) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Destination 'readme.txt') -Value ($readme -join [Environment]::NewLine) -Encoding UTF8
    if ($support.Count) {
        Set-Content -LiteralPath (Join-Path $Destination 'compatibility.txt') -Value (@($support | Sort-Object -Unique) -join [Environment]::NewLine) -Encoding UTF8
    }
    return $versions
}

function Get-CombinedBuildReportPath {
    param([string]$ZipPath)
    $directory = Split-Path -Path $ZipPath -Parent
    $baseName = [IO.Path]::GetFileNameWithoutExtension($ZipPath)
    return Join-Path (Join-Path $directory 'reports') "$baseName.report.json"
}

function Remove-ArchivedBuildReport {
    param([string]$ZipPath)
    $reportPath = Get-CombinedBuildReportPath -ZipPath $ZipPath
    # Also clean reports from builds made before reports/ was introduced.
    $legacyPath = [IO.Path]::ChangeExtension($ZipPath, 'report.json')
    foreach ($path in @($reportPath, $legacyPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}

function Get-CombinedDefinitionPath {
    param($PackDirectory)
    $property = $PackDirectory.PSObject.Properties['CombinedDefinitionPath']
    if ($null -ne $property) { return [string]$property.Value }
    return ''
}

function Get-CombinedPublishingOptions {
    param($PackDirectory, $Config)
    $definitionPath = Get-CombinedDefinitionPath $PackDirectory
    $options = Import-PowerShellDataFile -Path $definitionPath
    $repoRoot = Split-Path (Split-Path $definitionPath -Parent) -Parent
    $order = Get-VersionOrderLookup -Config $Config
    foreach ($platform in @('Modrinth', 'CurseForge')) {
        $dependencies = @()
        $configured = $options.ContainsKey($platform) -and $options[$platform].ContainsKey('Dependencies')
        if ($configured) { $dependencies = @($options[$platform].Dependencies) }
        foreach ($entry in @($options['Packs'])) {
            if ($null -eq $entry) { continue }
            if (-not $entry.Enabled -or ($entry.ContainsKey('Include') -and @($entry.Include).Count -eq 0)) { continue }
            $path = Join-Path (Join-Path (Resolve-FullPath -BasePath $repoRoot -Path $Config.PackRoot) $entry.Name) $Config.PackBuildConfigFile
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
            $component = Import-PowerShellDataFile -Path $path
            if (-not $component.ContainsKey($platform) -or -not $component[$platform].ContainsKey('Dependencies')) { continue }
            $configured = $true
            $versions = @($Config.Versions | Where-Object {
                Test-VersionSelectorMatch -Options $component -VersionConfig $_ -VersionOrder $order -ContextDescription "Combined component '$($entry.Name)'"
            } | ForEach-Object { $_.Id })
            foreach ($dependency in @($component[$platform].Dependencies)) {
                # Intersect selectors with component support before the platform's
                # normal validation, deduplication and conflict detection.
                if ($dependency -isnot [System.Collections.IDictionary]) { throw "$platform.Dependencies for '$($entry.Name)' must contain dependency tables." }
                $copy = @{} + $dependency
                foreach ($selector in @('Versions', 'ExcludeVersions', 'MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion')) {
                    if ($copy.ContainsKey($selector)) {
                        foreach ($id in @($copy[$selector])) {
                            Assert-KnownVersionSelectorId -VersionId ([string]$id) -OptionName $selector -VersionOrder $order -ContextDescription "Dependency in '$($entry.Name)'"
                        }
                    }
                }
                $matching = @($Config.Versions | Where-Object {
                    $_.Id -in $versions -and (Test-VersionSelectorMatch -Options $copy -VersionConfig $_ -VersionOrder $order -ContextDescription "Dependency in '$($entry.Name)'")
                } | ForEach-Object { $_.Id })
                $copy.Versions = $matching
                if ($matching.Count -eq 0) { continue }
                $dependencies += $copy
            }
        }
        if ($configured) {
            if (-not $options.ContainsKey($platform)) { $options[$platform] = @{} }
            $options[$platform].Dependencies = $dependencies
        }
    }
    return $options
}

function Get-CombinedPackDirectories {
    param([string]$RepoRoot, $Config)
    $root = Join-Path $RepoRoot 'artemis_enhanced_visuals'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Filter '*.psd1' | Sort-Object Name) {
        $definition = Import-PowerShellDataFile -Path $file.FullName
        if (-not $definition.ContainsKey('Name') -or [string]$definition.Name -cnotmatch '^[a-z0-9_]+$') {
            throw "Invalid combined pack Name in '$($file.FullName)'."
        }
        if ($definition.Name -cne $file.BaseName) { throw "Combined definition filename must match Name: $($file.FullName)" }
        if (Test-Path -LiteralPath (Join-Path (Resolve-FullPath -BasePath $RepoRoot -Path $Config.PackRoot) $definition.Name)) {
            throw "Combined pack '$($definition.Name)' conflicts with a normal pack."
        }
        [pscustomobject]@{
            Name = [string]$definition.Name
            FullName = $file.DirectoryName
            CombinedDefinitionPath = $file.FullName
        }
    }
}

function Move-ReleaseZipToArchive {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$ArchiveRootPath
    )

    $destinationDirectory = Join-Path -Path (Join-Path -Path $ArchiveRootPath -ChildPath $Item.PackName) -ChildPath $Item.ReleaseVersion
    # Archived uploads retain their exact filename on every platform.
    if ([IO.Path]::GetFullPath((Split-Path $Item.ZipPath -Parent)).Equals([IO.Path]::GetFullPath($destinationDirectory), [StringComparison]::OrdinalIgnoreCase)) {
        return $Item.ZipPath
    }
    Ensure-Directory -Path $destinationDirectory

    $destinationFileName = Get-ReleaseZipFileName -Item $Item
    $destinationPath = Join-Path -Path $destinationDirectory -ChildPath $destinationFileName
    if ([System.IO.Path]::GetFullPath($Item.ZipPath).Equals([System.IO.Path]::GetFullPath($destinationPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-ArchivedBuildReport -ZipPath $Item.ZipPath
        return $destinationPath
    }

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $sourceHash = (Get-FileHash -LiteralPath $Item.ZipPath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash) {
            if (Test-Path -LiteralPath "$($Item.ZipPath).versions.json") {
                Move-Item -LiteralPath "$($Item.ZipPath).versions.json" -Destination "$destinationPath.versions.json" -Force
            }
            Remove-Item -LiteralPath $Item.ZipPath
            Remove-ArchivedBuildReport -ZipPath $Item.ZipPath
            return $destinationPath
        }

        $timestamp = [System.DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmss')
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($destinationFileName)
        $extension = [System.IO.Path]::GetExtension($Item.ZipPath)
        $destinationPath = Join-Path -Path $destinationDirectory -ChildPath "$baseName-uploaded-$timestamp$extension"
    }

    Move-Item -LiteralPath $Item.ZipPath -Destination $destinationPath
    if (Test-Path -LiteralPath "$($Item.ZipPath).versions.json") {
        Move-Item -LiteralPath "$($Item.ZipPath).versions.json" -Destination "$destinationPath.versions.json" -Force
    }
    Remove-ArchivedBuildReport -ZipPath $Item.ZipPath
    return $destinationPath
}

function Get-PackZipVersions {
    param([string]$ZipPath)
    $path = "$ZipPath.versions.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($data.Sha256 -ne (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash) { throw "Version metadata does not match ZIP: $ZipPath" }
        return @($data.Versions)
    }
    return @()
}

function Set-PackZipVersions {
    param([string]$ZipPath, [string[]]$Versions, [string]$Label)
    @{ Versions = @($Versions); Label = $Label; Sha256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$ZipPath.versions.json" -Encoding UTF8
}

function Get-PackVersionLabel {
    param([string[]]$Versions, $Config)
    $ordered = @($Config.Versions | Where-Object { $_.Id -in $Versions } | ForEach-Object { [string]$_.Id })
    if ($ordered.Count -eq 1) { return $ordered[0] }
    $segments = New-Object 'Collections.Generic.List[string]'
    $run = New-Object 'Collections.Generic.List[string]'
    # A range may never claim a missing version, including versions disabled in the matrix.
    foreach ($entry in $Config.Versions) {
        if ($entry.Id -in $Versions) { $run.Add([string]$entry.Id) }
        elseif ($run.Count) {
            $segments.Add(($run.ToArray() -join ',')); $run.Clear()
        }
    }
    if ($run.Count) { $segments.Add(($run.ToArray() -join ',')) }
    $labels = foreach ($segment in $segments) {
        $ids = @($segment.Split(','))
        $family = ($ids[0].Split('.')[0..1] -join '.')
        $familyIds = @($Config.Versions | Where-Object { $_.Id -eq $family -or $_.Id -like "$family.*" } | ForEach-Object { $_.Id })
        if ($ids.Count -gt 1 -and @($ids | Where-Object { $_ -notin $familyIds }).Count -eq 0 -and @($familyIds | Where-Object { $_ -notin $ids }).Count -eq 0) { "$family.x" }
        elseif ($ids.Count -gt 1) { "$($ids[0])-$($ids[-1])" }
        else { $ids[0] }
    }
    return ($labels -join '+')
}

function Get-PackZipContentHash {
    param([string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entries = foreach ($entry in $zip.Entries | Sort-Object FullName -CaseSensitive) {
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)) }
            finally { $sha.Dispose(); $stream.Dispose() }
            @($entry.FullName, $entry.Length, $hash)
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($entries) -Compress -Depth 5))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
    }
    finally { $zip.Dispose() }
}

function Find-PackBuildZip {
    param([string]$BuildZipPath, [string]$MinecraftVersion)
    if (Test-Path -LiteralPath $BuildZipPath -PathType Leaf) { return $BuildZipPath }
    $directory = Split-Path $BuildZipPath -Parent
    if (-not (Test-Path -LiteralPath $directory)) { return $BuildZipPath }
    foreach ($zip in Get-ChildItem -LiteralPath $directory -File -Filter '*.zip') {
        if ($MinecraftVersion -in @(Get-PackZipVersions $zip.FullName)) { return $zip.FullName }
    }
    return $BuildZipPath
}

function Merge-IdenticalPackBuilds {
    param([string]$Directory, [string]$PackName, [string]$DisplayName, $Config)
    if (-not (Test-Path -LiteralPath $Directory)) { return }
    $byVersion = @{}; $oldPaths = @{}
    foreach ($zip in Get-ChildItem -LiteralPath $Directory -File -Filter '*.zip') {
        foreach ($id in @(Get-PackZipVersions $zip.FullName)) {
            if ($id -notin @($Config.Versions | ForEach-Object { $_.Id })) { throw "Cannot regroup '$($zip.FullName)': version '$id' is missing from the configured matrix." }
            $byVersion[$id] = $zip.FullName; $oldPaths[$zip.FullName] = $true
        }
    }
    # Fresh individual builds override only their own members of an earlier group.
    foreach ($entry in $Config.Versions) {
        $name = Convert-Tokens -Value $Config.PackageNameTemplate -Tokens @{ PackName = $PackName; PackDisplayName = $DisplayName; VersionId = $entry.Id }
        $path = Join-Path $Directory "$name.zip"
        if (Test-Path -LiteralPath $path -PathType Leaf) { $byVersion[$entry.Id] = $path; $oldPaths[$path] = $true }
    }
    $hashes = @{}; $groups = @{}
    foreach ($entry in $Config.Versions) {
        $id = [string]$entry.Id
        if (-not $byVersion.ContainsKey($id)) { continue }
        $path = $byVersion[$id]
        if (-not $hashes.ContainsKey($path)) { $hashes[$path] = Get-PackZipContentHash $path }
        $hash = $hashes[$path]
        if (-not $groups.ContainsKey($hash)) { $groups[$hash] = New-Object 'Collections.Generic.List[string]' }
        $groups[$hash].Add($id)
    }
    if (-not $groups.Count) { return }
    $staging = Join-Path $Directory ('.group-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    $retiring = $false; $complete = $false
    try {
        foreach ($group in $groups.Values) {
            $ids = $group.ToArray(); $label = Get-PackVersionLabel -Versions $ids -Config $Config
            $name = Convert-Tokens -Value $Config.PackageNameTemplate -Tokens @{ PackName = $PackName; PackDisplayName = $DisplayName; VersionId = $label }
            $target = Join-Path $staging "$name.zip"
            Copy-Item -LiteralPath $byVersion[$ids[0]] -Destination $target
            Set-PackZipVersions -ZipPath $target -Versions $ids -Label $label
        }
        $retiring = $true
        foreach ($path in $oldPaths.Keys) {
            Remove-Item -LiteralPath $path
            if (Test-Path -LiteralPath "$path.versions.json") { Remove-Item -LiteralPath "$path.versions.json" }
        }
        Get-ChildItem -LiteralPath $staging -File | Move-Item -Destination $Directory
        $complete = $true
    }
    finally {
        # The directory is a newly created immediate child of the checked build directory.
        if ((Split-Path ([IO.Path]::GetFullPath($staging)) -Parent) -ne [IO.Path]::GetFullPath($Directory)) { throw 'Unsafe grouping cleanup path.' }
        if ($complete -or -not $retiring) { Remove-Item -LiteralPath $staging -Recurse -Force }
        else { Write-Warning "Regrouping was interrupted. Remaining replacement ZIPs are retained in '$staging'." }
    }
}

function Merge-PackUploadItems {
    param([object[]]$Items, $Config)
    $groups = @{}
    foreach ($item in $Items) {
        $deps = ConvertTo-Json -InputObject @($item.Dependencies) -Depth 20 -Compress
        $key = "$($item.PackName)|$($item.ProjectId)|$($item.ReleaseVersion)|$($item.ZipPath)|$deps"
        if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object 'Collections.Generic.List[object]' }
        $groups[$key].Add($item)
    }
    foreach ($group in $groups.Values) {
        $item = $group[0]
        $members = @($group | ForEach-Object { [pscustomobject]@{ MinecraftVersion = $_.MinecraftVersion; VersionNumber = $_.VersionNumber } })
        $item | Add-Member -NotePropertyName PublishMembers -NotePropertyValue $members -Force
        $ids = @($group | ForEach-Object { $_.MinecraftVersion })
        $item | Add-Member -NotePropertyName MinecraftVersions -NotePropertyValue $ids -Force
        if ($group.Count -gt 1) {
            $label = Get-PackVersionLabel -Versions $ids -Config $Config
            $tokens = @{ PackName = $item.PackName; PackDisplayName = $item.PackDisplayName; VersionId = $label; MinecraftVersion = $label; ReleaseVersion = $item.ReleaseVersion }
            $item.VersionNumber = Convert-PublishVersionNumber (Convert-Tokens -Value $item.PublishTemplates.VersionNumber -Tokens $tokens)
            $item.VersionName = Convert-Tokens -Value $item.PublishTemplates.VersionName -Tokens $tokens
            $item.Changelog = Convert-Tokens -Value $item.PublishTemplates.Changelog -Tokens $tokens
            if ($item.PSObject.Properties['GameVersionNames']) {
                $item.GameVersionNames = @($group | ForEach-Object { $_.GameVersionNames } | Select-Object -Unique)
            }
            $item.MinecraftVersion = $label
        }
        $item
    }
}
