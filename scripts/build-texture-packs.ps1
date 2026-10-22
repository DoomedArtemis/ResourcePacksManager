[CmdletBinding()]
param(
    [string]$ConfigPath = 'config/texture-pack.build.psd1',
    [string[]]$Version,
    [string[]]$Pack,
    [switch]$PromptForPack,
    [switch]$PromptForVersion,
    [switch]$ListVersions,
    [switch]$ListPacks,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')

function Show-BuildProgress {
    param([int]$Id, [string]$Activity, [string]$Stage, [int]$Completed = -1, [int]$Total = 1)
    $percent = -1
    if ($Completed -ge 0) { $percent = [Math]::Min(100, [Math]::Max(0, [int][Math]::Floor(100 * $Completed / [Math]::Max(1, $Total)))) }
    # IDE output panes may not render PowerShell's interactive progress bar.
    if (-not (Get-Variable -Name BuildProgressLog -Scope Script -ErrorAction SilentlyContinue)) { $script:BuildProgressLog = @{} }
    $now = [DateTime]::UtcNow
    $previous = $script:BuildProgressLog[$Id]
    $stageChanged = $null -eq $previous -or $previous.Activity -ne $Activity -or $previous.Stage -ne $Stage
    if ($stageChanged -or ($now - $previous.UiTime).TotalMilliseconds -ge 200 -or ($Completed -ge 0 -and $Completed -ge $Total)) {
        Write-Progress -Id $Id -Activity $Activity -Status $Stage -PercentComplete $percent
        if (-not $stageChanged) { $previous.UiTime = $now }
    }
    if ($null -eq $previous -or $previous.Activity -ne $Activity -or $previous.Stage -ne $Stage -or ($now - $previous.Time).TotalSeconds -ge 5) {
        if ($Completed -ge 0) { Write-Host "[$percent%] $Activity - $Stage ($Completed/$Total)" }
        else { Write-Host "$Activity - $Stage" }
        $script:BuildProgressLog[$Id] = @{ Activity = $Activity; Stage = $Stage; Time = $now; UiTime = $now }
    }
}

function Close-BuildProgress {
    param([int]$Id, [string]$Activity)
    Write-Progress -Id $Id -Activity $Activity -Completed
    if (Get-Variable -Name BuildProgressLog -Scope Script -ErrorAction SilentlyContinue) { $script:BuildProgressLog.Remove($Id) }
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-TemporaryBuildRoot {
    return Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'artemis-texture-pack-builder'
}

function New-RelativePathBaseUri {
    param([Parameter(Mandatory = $true)][string]$BasePath)
    $baseResolved = (Resolve-Path -LiteralPath $BasePath).Path
    return [System.Uri]::new(($baseResolved.TrimEnd('\') + '\'))
}

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath,
        [System.Uri]$BaseUri
    )

    if ($null -eq $BaseUri) { $BaseUri = New-RelativePathBaseUri -BasePath $BasePath }
    $fullResolved = (Resolve-Path -LiteralPath $FullPath).Path

    $fullUri = [System.Uri]::new($fullResolved)
    $relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString())

    return ($relative -replace '\\', '/').TrimStart('./')
}

function Convert-Tokens {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $result = $Value
    foreach ($entry in $Tokens.GetEnumerator()) {
        $result = $result.Replace("{$($entry.Key)}", [string]$entry.Value)
    }

    return $result
}

function ConvertTo-Hashtable {
    param([Parameter(Mandatory = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [hashtable]) {
        $copy = @{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $copy
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $copy
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-Hashtable -InputObject $item)
        }
        return $list
    }

    if ($InputObject.PSObject -and @($InputObject.PSObject.Properties).Count -gt 0 -and $InputObject -isnot [string]) {
        $copy = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $copy[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }
        return $copy
    }

    return $InputObject
}

function Get-HashtableValueOrDefault {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Table,
        [Parameter(Mandatory = $true)][string]$Key,
        $DefaultValue
    )

    if ($Table.ContainsKey($Key)) {
        return $Table[$Key]
    }

    return $DefaultValue
}

function Merge-Hashtable {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Base,
        [Parameter(Mandatory = $true)][hashtable]$Overlay
    )

    foreach ($key in $Overlay.Keys) {
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $Overlay[$key] -is [hashtable]) {
            $Base[$key] = Merge-Hashtable -Base $Base[$key] -Overlay $Overlay[$key]
            continue
        }

        $Base[$key] = $Overlay[$key]
    }

    return $Base
}

function Normalize-VersionConfig {
    param([Parameter(Mandatory = $true)]$VersionConfig)

    $normalized = ConvertTo-Hashtable -InputObject $VersionConfig
    foreach ($key in @('Renames', 'PathRewrites', 'Remove', 'Required')) {
        if (-not $normalized.ContainsKey($key) -or $null -eq $normalized[$key]) {
            $normalized[$key] = @()
        }
    }

    foreach ($key in @('PackMetadata', 'RootMetadata')) {
        if (-not $normalized.ContainsKey($key) -or $null -eq $normalized[$key]) {
            $normalized[$key] = @{}
        }
    }

    if (-not $normalized.ContainsKey('Enabled') -or $null -eq $normalized['Enabled']) {
        $normalized['Enabled'] = $true
    }

    return $normalized
}

function Convert-PackFormatValue {
    param([Parameter(Mandatory = $true)]$Value)

    if ($Value -is [int] -or $Value -is [long]) {
        return [int]$Value
    }

    if (
        $Value -is [hashtable] -or
        $Value -is [System.Collections.IDictionary] -or
        (
            $Value -isnot [string] -and
            $Value -isnot [bool] -and
            @($Value.PSObject.Properties.Name).Count -gt 0
        )
    ) {
        $normalized = ConvertTo-Hashtable -InputObject $Value
        if (-not $normalized.ContainsKey('major')) {
            throw "PackFormat object is missing 'major'."
        }

        if (-not $normalized.ContainsKey('minor')) {
            $normalized['minor'] = 0
        }

        return [ordered]@{
            major = [int]$normalized.major
            minor = [int]$normalized.minor
        }
    }

    throw "Unsupported PackFormat value type: $($Value.GetType().FullName)"
}

function Format-PackFormatValue {
    param([Parameter(Mandatory = $true)]$Value)

    $normalized = Convert-PackFormatValue -Value $Value
    if ($normalized -is [int]) {
        return [string]$normalized
    }

    return "$($normalized.major).$($normalized.minor)"
}

function Convert-PackFormatMetadataValue {
    param([Parameter(Mandatory = $true)]$Value)

    $normalized = Convert-PackFormatValue -Value $Value
    if ($normalized -is [int]) {
        return $normalized
    }

    if ([int]$normalized.minor -eq 0) {
        return [int]$normalized.major
    }

    return @(
        [int]$normalized.major
        [int]$normalized.minor
    )
}

function New-ExactSupportedFormatsRange {
    param([Parameter(Mandatory = $true)]$PackFormat)

    $normalized = Convert-PackFormatValue -Value $PackFormat
    return [ordered]@{
        min_inclusive = $normalized
        max_inclusive = $normalized
    }
}

function Get-EffectiveSupportedFormats {
    param([Parameter(Mandatory = $true)]$VersionConfig)

    if ($VersionConfig.ContainsKey('SupportedFormats') -and $VersionConfig.SupportedFormats) {
        return ConvertTo-Hashtable -InputObject $VersionConfig.SupportedFormats
    }

    if ($VersionConfig.ContainsKey('EmitSupportedFormats') -and $VersionConfig.EmitSupportedFormats) {
        return New-ExactSupportedFormatsRange -PackFormat $VersionConfig.PackFormat
    }

    return $null
}

function Test-RuleMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Rule
    )

    if ($Rule.EndsWith('/')) {
        return $Path.StartsWith($Rule, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return $Path.Equals($Rule, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IgnoredSourceFile {
    param([Parameter(Mandatory = $true)][string]$Name)

    return $Name -in @('.gitkeep', '.gitignore', 'Thumbs.db', '.DS_Store')
}

function Convert-ToPackDisplayName {
    param([Parameter(Mandatory = $true)][string]$PackFolderName)

    $spaced = ($PackFolderName -replace '[_-]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($spaced)) {
        return $PackFolderName
    }

    return [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($spaced.ToLowerInvariant())
}

function Read-RequestedPackNames {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config
    )

    $availablePacks = @(Get-PackDirectories -RepoRoot $RepoRoot -Config $Config -RequestedPackNames @() | Select-Object -ExpandProperty Name)
    if ($availablePacks.Count -eq 0) {
        throw 'No resource packs are available to select.'
    }

    Write-Host 'Available resource packs:'
    foreach ($packName in $availablePacks) {
        Write-Host "  - $packName"
    }
    Write-Host ''

    $inputValue = Read-Host 'Enter resource pack name(s) to build (comma-separated)'
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        throw 'No resource pack names entered.'
    }

    $requestedPacks = @(
        $inputValue.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )

    if ($requestedPacks.Count -eq 0) {
        throw 'No valid resource pack names were entered.'
    }

    return $requestedPacks
}

function Read-RequestedVersions {
    param([Parameter(Mandatory = $true)]$Config)

    Write-Host 'Configured Minecraft versions:'
    foreach ($entry in @($Config.Versions)) {
        if (-not $entry.Enabled) {
            continue
        }

        Write-Host "  - $($entry.Id)"
    }
    Write-Host ''
    Write-Host 'Examples:'
    Write-Host '  all'
    Write-Host '  1.21.11'
    Write-Host '  1.20.4..1.21.11'
    Write-Host '  1.20.4 to 1.21.11'
    Write-Host '  1.20.4, 1.20.6 to 1.21.2'
    Write-Host ''

    $inputValue = Read-Host 'Enter Minecraft versions (all, comma-separated versions, start..end, or start to end)'
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        throw 'No version selection entered.'
    }

    return @(Expand-RequestedVersionSelection -InputValue $inputValue -Config $Config)
}

function Get-PackDirectories {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [string[]]$RequestedPackNames
    )

    $packsRoot = Resolve-FullPath -BasePath $RepoRoot -Path ([string]$Config.PackRoot)
    if (-not (Test-Path -LiteralPath $packsRoot)) {
        throw "Pack root not found: $packsRoot"
    }

    $packDirectories = @(Get-ChildItem -LiteralPath $packsRoot -Directory | Sort-Object Name)
    $packDirectories += @(Get-CombinedPackDirectories -RepoRoot $RepoRoot -Config $Config)

    if ($RequestedPackNames) {
        $lookup = @{}
        foreach ($requested in $RequestedPackNames) {
            $lookup[$requested] = $true
        }

        $packDirectories = @($packDirectories | Where-Object { $lookup.ContainsKey($_.Name) })
        if ($packDirectories.Count -ne $lookup.Keys.Count) {
            $found = @($packDirectories | ForEach-Object { $_.Name })
            $missing = @($lookup.Keys | Where-Object { $_ -notin $found })
            throw "Unknown pack name(s): $($missing -join ', ')"
        }
    }

    return $packDirectories
}

function Get-PackBuildOptions {
    param(
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$Config
    )

    $definitionPath = Get-CombinedDefinitionPath -PackDirectory $PackDirectory
    if ($definitionPath) { return Import-PowerShellDataFile -Path $definitionPath }
    $configFileName = [string]$Config.PackBuildConfigFile
    $configPath = Join-Path -Path $PackDirectory.FullName -ChildPath $configFileName
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @{}
    }

    $options = Import-PowerShellDataFile -Path $configPath
    if ($options.ContainsKey('FileOptionsPath') -and $options.FileOptionsPath) {
        $fileOptionsPath = Resolve-FullPath -BasePath $PackDirectory.FullName -Path ([string]$options.FileOptionsPath)
        $packPrefix = $PackDirectory.FullName.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $fileOptionsPath.StartsWith($packPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "FileOptionsPath must stay inside pack '$($PackDirectory.Name)'."
        }
        $fileOptions = ConvertTo-Hashtable -InputObject ((Get-Content -LiteralPath $fileOptionsPath -Raw -Encoding UTF8) | ConvertFrom-Json)
        foreach ($key in $fileOptions.Keys) {
            if ($key -notin @('FileRules', 'FileVariants')) {
                throw "FileOptionsPath supports only FileRules and FileVariants, not '$key'."
            }
            $existing = @()
            if ($options.ContainsKey($key)) { $existing = @($options[$key]) }
            $options[$key] = @($existing) + @($fileOptions[$key])
        }
    }
    return $options
}

function Get-VersionOrderLookup {
    param([Parameter(Mandatory = $true)]$Config)

    $versionOrder = @{}
    $orderedVersions = @($Config.Versions)
    for ($index = 0; $index -lt $orderedVersions.Count; $index++) {
        $versionOrder[[string]$orderedVersions[$index].Id] = $index
    }

    return $versionOrder
}

function Expand-RequestedVersionSelection {
    param(
        [Parameter(Mandatory = $true)][string]$InputValue,
        [Parameter(Mandatory = $true)]$Config
    )

    $versionOrder = Get-VersionOrderLookup -Config $Config

    $orderedVersions = @($Config.Versions)
    $selectedVersionIds = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $contextDescription = 'Prompted version selection'

    $segments = @(
        $InputValue.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    if ($segments.Count -eq 0) {
        throw 'No valid version selection was entered.'
    }

    foreach ($segment in $segments) {
        if ($segment -ieq 'all') {
            foreach ($versionEntry in @($orderedVersions | Where-Object { $_.Enabled })) {
                $versionId = [string]$versionEntry.Id
                if (-not $seen.ContainsKey($versionId)) {
                    $seen[$versionId] = $true
                    $selectedVersionIds.Add($versionId)
                }
            }

            continue
        }

        if ($segment -match '^(?<start>.+?)\s*(?:\.\.|\s+to\s+)\s*(?<end>.+)$') {
            $startVersionId = $Matches.start.Trim()
            $endVersionId = $Matches.end.Trim()

            Assert-KnownVersionSelectorId -VersionId $startVersionId -OptionName 'VersionRangeStart' -VersionOrder $versionOrder -ContextDescription $contextDescription
            Assert-KnownVersionSelectorId -VersionId $endVersionId -OptionName 'VersionRangeEnd' -VersionOrder $versionOrder -ContextDescription $contextDescription

            $startIndex = [int]$versionOrder[$startVersionId]
            $endIndex = [int]$versionOrder[$endVersionId]
            if ($startIndex -gt $endIndex) {
                throw "Prompted version range start '$startVersionId' comes after end '$endVersionId'. Use the configured version order."
            }

            for ($index = $startIndex; $index -le $endIndex; $index++) {
                $versionId = [string]$orderedVersions[$index].Id
                if (-not $seen.ContainsKey($versionId)) {
                    $seen[$versionId] = $true
                    $selectedVersionIds.Add($versionId)
                }
            }

            continue
        }

        Assert-KnownVersionSelectorId -VersionId $segment -OptionName 'Version' -VersionOrder $versionOrder -ContextDescription $contextDescription
        if (-not $seen.ContainsKey($segment)) {
            $seen[$segment] = $true
            $selectedVersionIds.Add($segment)
        }
    }

    return @($selectedVersionIds)
}

function Assert-KnownVersionSelectorId {
    param(
        [Parameter(Mandatory = $true)][string]$VersionId,
        [Parameter(Mandatory = $true)][string]$OptionName,
        [Parameter(Mandatory = $true)][hashtable]$VersionOrder,
        [Parameter(Mandatory = $true)][string]$ContextDescription
    )

    if (-not $VersionOrder.ContainsKey($VersionId)) {
        throw "$ContextDescription requests unknown version id '$VersionId' in option '$OptionName'."
    }
}

function Test-VersionSelectorMatch {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Options,
        [Parameter(Mandatory = $true)]$VersionConfig,
        [Parameter(Mandatory = $true)][hashtable]$VersionOrder,
        [Parameter(Mandatory = $true)][string]$ContextDescription
    )

    $versionId = [string]$VersionConfig.Id
    $versionIndex = [int]$VersionOrder[$versionId]

    if ($Options.ContainsKey('Versions') -and $Options.Versions) {
        $lookup = @{}
        foreach ($candidateVersionId in @($Options.Versions)) {
            $normalizedVersionId = [string]$candidateVersionId
            Assert-KnownVersionSelectorId -VersionId $normalizedVersionId -OptionName 'Versions' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
            $lookup[$normalizedVersionId] = $true
        }

        if (-not $lookup.ContainsKey($versionId)) {
            return $false
        }
    }

    if ($Options.ContainsKey('ExcludeVersions') -and $Options.ExcludeVersions) {
        $lookup = @{}
        foreach ($candidateVersionId in @($Options.ExcludeVersions)) {
            $normalizedVersionId = [string]$candidateVersionId
            Assert-KnownVersionSelectorId -VersionId $normalizedVersionId -OptionName 'ExcludeVersions' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
            $lookup[$normalizedVersionId] = $true
        }

        if ($lookup.ContainsKey($versionId)) {
            return $false
        }
    }

    if ($Options.ContainsKey('MinVersion') -and $Options.MinVersion) {
        $minVersionId = [string]$Options.MinVersion
        Assert-KnownVersionSelectorId -VersionId $minVersionId -OptionName 'MinVersion' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
        if ($versionIndex -lt [int]$VersionOrder[$minVersionId]) {
            return $false
        }
    }

    if ($Options.ContainsKey('MaxVersion') -and $Options.MaxVersion) {
        $maxVersionId = [string]$Options.MaxVersion
        Assert-KnownVersionSelectorId -VersionId $maxVersionId -OptionName 'MaxVersion' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
        if ($versionIndex -gt [int]$VersionOrder[$maxVersionId]) {
            return $false
        }
    }

    if ($Options.ContainsKey('AfterVersion') -and $Options.AfterVersion) {
        $afterVersionId = [string]$Options.AfterVersion
        Assert-KnownVersionSelectorId -VersionId $afterVersionId -OptionName 'AfterVersion' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
        if ($versionIndex -le [int]$VersionOrder[$afterVersionId]) {
            return $false
        }
    }

    if ($Options.ContainsKey('BeforeVersion') -and $Options.BeforeVersion) {
        $beforeVersionId = [string]$Options.BeforeVersion
        Assert-KnownVersionSelectorId -VersionId $beforeVersionId -OptionName 'BeforeVersion' -VersionOrder $VersionOrder -ContextDescription $ContextDescription
        if ($versionIndex -ge [int]$VersionOrder[$beforeVersionId]) {
            return $false
        }
    }

    return $true
}

function Get-PackCompatibilityRules {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Options,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$VersionConfig,
        [Parameter(Mandatory = $true)][string]$PackName
    )

    if (-not $Options.ContainsKey('Compatibility')) { return @() }
    if ($Options.Compatibility -isnot [System.Collections.IDictionary]) {
        throw "Pack '$PackName' Compatibility must be a table keyed by mod ID."
    }
    $versionOrder = Get-VersionOrderLookup -Config $Config
    foreach ($modId in @($Options.Compatibility.Keys | Sort-Object)) {
        $context = "Pack '$PackName' Compatibility '$modId'"
        if ([string]$modId -cnotmatch '^[a-z0-9_.-]+$') { throw "$context has an invalid mod ID." }
        if ($Options.Compatibility[$modId] -isnot [System.Collections.IDictionary]) {
            throw "$context must be a table."
        }
        $rawEntry = $Options.Compatibility[$modId]
        if ($rawEntry.Contains('Name') -and ($rawEntry['Name'] -isnot [string] -or [string]::IsNullOrWhiteSpace($rawEntry['Name']))) {
            throw "$context Name must be a non-empty text string."
        }
        if ($rawEntry.Contains('Support') -and $rawEntry['Support'] -isnot [string]) {
            throw "$context Support must be a text string or here-string."
        }
        $entry = ConvertTo-Hashtable -InputObject $rawEntry
        foreach ($key in $entry.Keys) {
            if ($key -notin @('Enabled', 'Paths', 'Versions', 'ExcludeVersions', 'MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion', 'Support', 'Name')) {
                throw "$context has an unknown option '$key'."
            }
        }
        $selectors = @{}
        foreach ($key in @('Versions', 'ExcludeVersions')) {
            if ($entry.ContainsKey($key)) {
                $values = @($entry[$key])
                $selectors[$key] = if ($values.Count -eq 0) { @() } else {
                    @(Expand-RequestedVersionSelection -InputValue ($values -join ',') -Config $Config)
                }
            }
        }
        foreach ($key in @('MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion')) {
            if ($entry.ContainsKey($key)) {
                Assert-KnownVersionSelectorId -VersionId ([string]$entry[$key]) -OptionName $key -VersionOrder $versionOrder -ContextDescription $context
                $selectors[$key] = $entry[$key]
            }
        }
        foreach ($pair in @(@('MinVersion', 'MaxVersion'), @('AfterVersion', 'BeforeVersion'))) {
            if ($selectors.ContainsKey($pair[0]) -and $selectors.ContainsKey($pair[1]) -and
                $versionOrder[[string]$selectors[$pair[0]]] -gt $versionOrder[[string]$selectors[$pair[1]]]) {
                throw "$context has reversed version bounds."
            }
        }
        $paths = @("assets/$modId/")
        if ($entry.ContainsKey('Paths')) { $paths = @($entry.Paths) }
        if ($paths.Count -eq 0) { throw "$context Paths must not be empty." }
        foreach ($rulePath in $paths) {
            if ([string]::IsNullOrWhiteSpace([string]$rulePath) -or [string]$rulePath -match '[*?\\]' -or
                [string]$rulePath -match '(^|/)\.\.(/|$)|^/|:') {
                throw "$context Paths must contain relative exact paths or directory prefixes, without wildcards."
            }
        }
        $include = Test-VersionSelectorMatch -Options $selectors -VersionConfig $VersionConfig -VersionOrder $versionOrder -ContextDescription $context
        if ($entry.ContainsKey('Versions') -and @($entry.Versions).Count -eq 0) { $include = $false }
        if ($entry.ContainsKey('Enabled') -and -not $entry.Enabled) { $include = $false }
        [pscustomobject]@{ ModId = [string]$modId; Paths = $paths; IncludeForVersion = [bool]$include;
            Name = [string](Get-HashtableValueOrDefault -Table $entry -Key 'Name' -DefaultValue ([string]$modId))
            Support = [string](Get-HashtableValueOrDefault -Table $entry -Key 'Support' -DefaultValue '') }
    }
}

function Get-PackCompatibilityText {
    param([object[]]$Rules = @())
    $names = @($Rules | Where-Object { $_.IncludeForVersion } | ForEach-Object { $_.Name.Trim() } | Sort-Object -Unique)
    if ($names.Count -eq 0) { return '' }
    return ($names -join [Environment]::NewLine) + [Environment]::NewLine
}

function New-InputFileWithReplacedSource {
    param(
        [Parameter(Mandatory = $true)]$InputFile,
        [Parameter(Mandatory = $true)][string]$NewSourcePath,
        [Parameter(Mandatory = $true)][string]$PackRoot,
        [System.Uri]$BaseUri
    )

    $copy = [ordered]@{}
    foreach ($property in $InputFile.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }

    $copy['SourcePath'] = $NewSourcePath
    $copy['SourceRelativePath'] = Get-NormalizedRelativePath -BasePath $PackRoot -FullPath $NewSourcePath -BaseUri $BaseUri

    return [pscustomobject]$copy
}

function Get-PackSelectedVersions {
    param(
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][object[]]$GloballySelectedVersions,
        [hashtable]$PackOptions
    )

    if ($null -eq $PackOptions) { $PackOptions = Get-PackBuildOptions -PackDirectory $PackDirectory -Config $Config }
    if ($packOptions.Count -eq 0) {
        return @($GloballySelectedVersions)
    }

    $versionOrder = Get-VersionOrderLookup -Config $Config
    $contextDescription = "Pack '$($PackDirectory.Name)' inside $([string]$Config.PackBuildConfigFile)"

    return @($GloballySelectedVersions | Where-Object {
        Test-VersionSelectorMatch -Options $packOptions -VersionConfig $_ -VersionOrder $versionOrder -ContextDescription $contextDescription
    })
}

function Get-PackTokens {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $packName = $PackDirectory.Name
    return @{
        PackName = $packName
        PackDisplayName = Convert-ToPackDisplayName -PackFolderName $packName
        VersionId = [string]$VersionConfig.Id
        BaseDescription = [string]$Config.BaseDescription
    }
}

function Get-TransformedPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $path = $RelativePath

    foreach ($rename in @(Get-HashtableValueOrDefault -Table $VersionConfig -Key 'Renames' -DefaultValue @())) {
        if ($null -eq $rename) {
            continue
        }

        if ($path.Equals([string]$rename.From, [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = [string]$rename.To
        }
    }

    foreach ($rewrite in @(Get-HashtableValueOrDefault -Table $VersionConfig -Key 'PathRewrites' -DefaultValue @())) {
        if ($null -eq $rewrite) {
            continue
        }

        $from = [string]$rewrite.From
        $to = [string]$rewrite.To
        if ($path.StartsWith($from, [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $to + $path.Substring($from.Length)
        }
    }

    foreach ($rule in @(Get-HashtableValueOrDefault -Table $VersionConfig -Key 'Remove' -DefaultValue @())) {
        if (Test-RuleMatch -Path $path -Rule ([string]$rule)) {
            return $null
        }
    }

    return $path
}

function New-PackMcmetaObject {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Tokens,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $description = if ($VersionConfig.ContainsKey('Description') -and $VersionConfig.Description) {
        Convert-Tokens -Value ([string]$VersionConfig.Description) -Tokens $Tokens
    }
    else {
        Convert-Tokens -Value ([string]$Tokens.BaseDescription) -Tokens $Tokens
    }

    $normalizedPackFormat = Convert-PackFormatValue -Value $VersionConfig.PackFormat
    $packNode = [ordered]@{
        description = $description
    }

    if ($normalizedPackFormat -is [int]) {
        $packNode.pack_format = $normalizedPackFormat
    }
    else {
        $packNode.min_format = Convert-PackFormatMetadataValue -Value $normalizedPackFormat
        $packNode.max_format = Convert-PackFormatMetadataValue -Value $normalizedPackFormat
    }

    $supportedFormats = Get-EffectiveSupportedFormats -VersionConfig $VersionConfig
    if ($null -ne $supportedFormats -and $normalizedPackFormat -is [int]) {
        $packNode.supported_formats = $supportedFormats
    }

    if ($VersionConfig.ContainsKey('PackMetadata') -and $VersionConfig.PackMetadata) {
        $packNode = Merge-Hashtable -Base (ConvertTo-Hashtable -InputObject $packNode) -Overlay (ConvertTo-Hashtable -InputObject $VersionConfig.PackMetadata)
    }

    $rootNode = [ordered]@{
        pack = $packNode
    }

    if ($VersionConfig.ContainsKey('RootMetadata') -and $VersionConfig.RootMetadata) {
        $rootNode = Merge-Hashtable -Base (ConvertTo-Hashtable -InputObject $rootNode) -Overlay (ConvertTo-Hashtable -InputObject $VersionConfig.RootMetadata)
    }

    return $rootNode
}

function Get-PackRouteCachePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $cacheRoot = Resolve-FullPath -BasePath $RepoRoot -Path ([string]$Config.VanillaCatalogCacheRoot)
    return Join-Path -Path (Join-Path -Path $cacheRoot -ChildPath 'resolved-pack-routes') -ChildPath (Join-Path -Path $PackDirectory.Name -ChildPath "$([string]$VersionConfig.Id).json")
}

function Get-PackRouteCache {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $cachePath = Get-PackRouteCachePath -RepoRoot $RepoRoot -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig
    if (-not (Test-Path -LiteralPath $cachePath)) {
        return @{}
    }

    return ConvertTo-Hashtable -InputObject ((Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8) | ConvertFrom-Json)
}

function Save-PackRouteCache {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$VersionConfig,
        [Parameter(Mandatory = $true)][hashtable]$RouteCache
    )

    $cachePath = Get-PackRouteCachePath -RepoRoot $RepoRoot -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig
    Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($cachePath))
    Set-Content -LiteralPath $cachePath -Value ($RouteCache | ConvertTo-Json -Depth 100) -Encoding UTF8
}

function Get-MojangVersionManifest {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config
    )

    $cacheRoot = Resolve-FullPath -BasePath $RepoRoot -Path ([string]$Config.VanillaCatalogCacheRoot)
    Ensure-Directory -Path $cacheRoot

    $manifestCachePath = Join-Path -Path $cacheRoot -ChildPath 'version_manifest_v2.json'
    $manifestUrl = [string]$Config.MojangVersionManifestUrl

    try {
        $content = Invoke-WebRequest -UseBasicParsing -Uri $manifestUrl | Select-Object -ExpandProperty Content
        Set-Content -LiteralPath $manifestCachePath -Value $content -Encoding UTF8
    }
    catch {
        if (-not (Test-Path -LiteralPath $manifestCachePath)) {
            throw "Unable to fetch Mojang version manifest from '$manifestUrl' and no local cache exists. $($_.Exception.Message)"
        }

        $content = Get-Content -LiteralPath $manifestCachePath -Raw -Encoding UTF8
    }

    return $content | ConvertFrom-Json
}

function Get-VanillaAssetCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$VersionConfig
    )

    $cacheRoot = Resolve-FullPath -BasePath $RepoRoot -Path ([string]$Config.VanillaCatalogCacheRoot)
    Ensure-Directory -Path $cacheRoot

    $versionId = [string]$VersionConfig.Id
    $cachePath = Join-Path -Path $cacheRoot -ChildPath "$versionId.json"
    if (Test-Path -LiteralPath $cachePath) {
        return ConvertTo-Hashtable -InputObject ((Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8) | ConvertFrom-Json)
    }

    $manifest = Get-MojangVersionManifest -RepoRoot $RepoRoot -Config $Config
    $versionEntry = @($manifest.versions | Where-Object { $_.id -eq $versionId })[0]
    if ($null -eq $versionEntry) {
        throw "Version '$versionId' is not present in Mojang's official version manifest."
    }

    try {
        $versionMetadata = (Invoke-WebRequest -UseBasicParsing -Uri $versionEntry.url | Select-Object -ExpandProperty Content) | ConvertFrom-Json
    }
    catch {
        throw "Unable to fetch Mojang metadata for version '$versionId'. $($_.Exception.Message)"
    }

    $clientJarUrl = $versionMetadata.downloads.client.url
    if (-not $clientJarUrl) {
        throw "Mojang metadata for version '$versionId' does not expose a client jar download."
    }

    $tempJarPath = Join-Path -Path $env:TEMP -ChildPath ("artemis-asset-catalog-" + $versionId + ".jar")

    $zip = $null
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $clientJarUrl -OutFile $tempJarPath
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tempJarPath)

        $byFileName = @{}
        foreach ($entry in $zip.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) {
                continue
            }

            $normalizedPath = ($entry.FullName -replace '\\', '/')
            if (-not $normalizedPath.StartsWith('assets/', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if (-not $byFileName.ContainsKey($entry.Name)) {
                $byFileName[$entry.Name] = @()
            }

            $byFileName[$entry.Name] += ,$normalizedPath
        }

        $catalog = [ordered]@{
            versionId = $versionId
            generatedAtUtc = [DateTime]::UtcNow.ToString('o')
            byFileName = $byFileName
        }

        $catalogJson = $catalog | ConvertTo-Json -Depth 100
        Set-Content -LiteralPath $cachePath -Value $catalogJson -Encoding UTF8
        return $catalog
    }
    catch {
        throw "Unable to build vanilla asset catalog for version '$versionId'. $($_.Exception.Message)"
    }
    finally {
        if ($zip) {
            $zip.Dispose()
        }

        if (Test-Path -LiteralPath $tempJarPath) {
            Remove-Item -LiteralPath $tempJarPath -Force
        }
    }
}

function Resolve-AutoAssetPath {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$HintPath,
        [Parameter(Mandatory = $true)][string]$AssetPrefix,
        [Parameter(Mandatory = $true)]$Catalog,
        [string]$CategoryFolder = '',
        [hashtable]$RouteCache = @{},
        [string]$RouteCacheKey = ''
    )

    $normalizedPrefix = ($AssetPrefix -replace '\\', '/').TrimEnd('/') + '/'

    if ($RouteCacheKey -and $RouteCache.ContainsKey($RouteCacheKey)) {
        $cachedPath = [string]$RouteCache[$RouteCacheKey]
        if (
            $cachedPath.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            $Catalog.byFileName.ContainsKey($FileName) -and
            $cachedPath -in @($Catalog.byFileName[$FileName])
        ) {
            return $cachedPath
        }
    }

    if (-not $Catalog.byFileName.ContainsKey($FileName)) {
        throw "Unable to auto-sort '$FileName'. It does not exist in Mojang's vanilla asset catalog for version '$($Catalog.versionId)'. Put ambiguous or custom files under the pack's assets/ folder with their intended relative path."
    }

    $candidates = @($Catalog.byFileName[$FileName] | Where-Object {
        $_.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    })

    if ($candidates.Count -eq 0) {
        throw "Unable to auto-sort '$FileName'. It exists in vanilla Minecraft, but not under '$normalizedPrefix' for version '$($Catalog.versionId)'."
    }

    if ($HintPath) {
        $normalizedHint = ($HintPath -replace '\\', '/').Trim('/')
        $hinted = @($candidates | Where-Object { $_ -like "$normalizedPrefix$normalizedHint/$FileName" })
        if ($hinted.Count -gt 0) {
            $candidates = $hinted
        }
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    if (
        -not $HintPath -and
        $CategoryFolder.Equals('models', [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        $fileStem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
        $textureCandidates = if ($Catalog.byFileName.ContainsKey("$fileStem.png")) { @($Catalog.byFileName["$fileStem.png"]) } else { @() }
        $jsonCandidates = @($Catalog.byFileName[$FileName])
        $scoredCandidates = @()

        foreach ($candidate in $candidates) {
            $score = 0
            $relativeCandidate = $candidate.Substring($normalizedPrefix.Length)
            $firstSegment = ($relativeCandidate -split '/')[0]

            if (
                $firstSegment -eq 'block' -and
                "assets/minecraft/blockstates/$fileStem.json" -in $jsonCandidates
            ) {
                $score += 20
            }

            if ("assets/minecraft/textures/$firstSegment/$fileStem.png" -in $textureCandidates) {
                $score += 10
            }

            $scoredCandidates += [pscustomobject]@{
                Path = $candidate
                Score = $score
            }
        }

        $maxScore = ($scoredCandidates | Measure-Object -Property Score -Maximum).Maximum
        $bestCandidates = @($scoredCandidates | Where-Object { $_.Score -eq $maxScore } | ForEach-Object { $_.Path })
        if ($bestCandidates.Count -eq 1 -and $maxScore -gt 0) {
            return $bestCandidates[0]
        }
    }

    throw "Unable to auto-sort '$FileName'. Multiple vanilla target paths match: $($candidates -join ', '). Place that file under the pack's assets/ folder with the exact intended relative path."
}

function New-PackPathRuleIndex {
    param(
        [AllowEmptyCollection()][object[]]$Rules = @(),
        [Parameter(Mandatory = $true)][string]$ContextDescription,
        [switch]$Variants
    )

    $exact = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $prefixes = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $ordinal = 0
    foreach ($rawRule in $Rules) {
        if ($null -eq $rawRule) { continue }
        # Normalize once, rather than recursively copying each rule for every file.
        $options = ConvertTo-Hashtable -InputObject $rawRule
        $rulePath = [string](Get-HashtableValueOrDefault -Table $options -Key 'Path' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($rulePath)) { throw "$ContextDescription has an entry without a non-empty 'Path'." }
        if ($Variants -and [string]::IsNullOrWhiteSpace([string](Get-HashtableValueOrDefault -Table $options -Key 'SourcePath' -DefaultValue ''))) {
            throw "$ContextDescription Path '$rulePath' is missing a non-empty 'SourcePath'."
        }
        $entry = [pscustomobject]@{ Ordinal = $ordinal; Path = $rulePath; Options = $options; VersionMatches = $null }
        $ordinal++
        $table = if ($rulePath.EndsWith('/')) { $prefixes } else { $exact }
        if (-not $table.ContainsKey($rulePath)) { $table[$rulePath] = New-Object System.Collections.Generic.List[object] }
        $table[$rulePath].Add($entry)
    }
    return [pscustomobject]@{ Exact = $exact; Prefixes = $prefixes }
}

function Get-PackPathRuleMatches {
    param(
        [Parameter(Mandatory = $true)]$Index,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $matches = @{}
    foreach ($candidatePath in $Paths) {
        if ($Index.Exact.ContainsKey($candidatePath)) {
            foreach ($entry in $Index.Exact[$candidatePath]) { $matches[$entry.Ordinal] = $entry }
        }
        # Only ancestors can match a directory-prefix rule. Look them up directly
        # instead of scanning every prefix in the configuration.
        $slash = $candidatePath.IndexOf('/')
        while ($slash -ge 0) {
            $prefix = $candidatePath.Substring(0, $slash + 1)
            if ($Index.Prefixes.ContainsKey($prefix)) {
                foreach ($entry in $Index.Prefixes[$prefix]) { $matches[$entry.Ordinal] = $entry }
            }
            $slash = $candidatePath.IndexOf('/', $slash + 1)
        }
    }
    # Keep declaration order and count separate declarations separately. The same
    # entry matching both canonical and typed paths must only be applied once.
    foreach ($ordinal in @($matches.Keys | Sort-Object)) { $matches[$ordinal] }
}

function Get-PackInputFiles {
    param(
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$VersionConfig,
        [hashtable]$PackOptions
    )

    $packRoot = $PackDirectory.FullName
    $packBaseUri = New-RelativePathBaseUri -BasePath $packRoot
    $canonicalAssetsFolder = [string]$Config.CanonicalAssetsFolder
    $autoSortFolder = [string]$Config.AutoSortFolder
    $autoSortMappings = @($Config.AutoSortMappings)
    if ($null -eq $PackOptions) { $PackOptions = Get-PackBuildOptions -PackDirectory $PackDirectory -Config $Config }
    $fileRules = @()
    $compatibilityRules = @(Get-PackCompatibilityRules -Options $packOptions -Config $Config -VersionConfig $VersionConfig -PackName $PackDirectory.Name)
    if ($packOptions.ContainsKey('FileRules') -and $packOptions.FileRules) {
        $fileRules = @($packOptions.FileRules)
    }
    $fileVariants = @()
    if ($packOptions.ContainsKey('FileVariants') -and $packOptions.FileVariants) {
        $fileVariants = @($packOptions.FileVariants)
    }
    $versionOrder = Get-VersionOrderLookup -Config $Config

    $contextPrefix = "Pack '$($PackDirectory.Name)' inside $([string]$Config.PackBuildConfigFile)"
    $ruleIndex = New-PackPathRuleIndex -Rules $fileRules -ContextDescription "$contextPrefix FileRules"
    $variantIndex = New-PackPathRuleIndex -Rules $fileVariants -ContextDescription "$contextPrefix FileVariants" -Variants
    $inputFiles = New-Object System.Collections.Generic.List[object]

    $definitions = @(
        @{ Kind = 'auto'; Path = $autoSortFolder; VirtualRoot = ''; Priority = 10 }
        @{ Kind = 'direct'; Path = $canonicalAssetsFolder; VirtualRoot = $canonicalAssetsFolder; Priority = 20 }
        @{ Kind = 'direct'; Path = 'extras'; VirtualRoot = ''; Priority = 30 }
    )

    foreach ($rootFile in Get-ChildItem -LiteralPath $packRoot -File) {
        if ($rootFile.Name -eq [string]$Config.PackBuildConfigFile -or $rootFile.Name -eq 'pack.mcmeta' -or (Test-IgnoredSourceFile -Name $rootFile.Name)) {
            continue
        }
        $definitions += @{ Kind = 'root'; Path = $rootFile.Name; VirtualRoot = $rootFile.Name; Priority = 30 }
    }

    foreach ($definition in $definitions) {
        $fullPath = Resolve-FullPath -BasePath $packRoot -Path ([string]$definition.Path)
        if (-not (Test-Path -LiteralPath $fullPath)) {
            continue
        }

        switch ($definition.Kind) {
            'root' {
                if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                    continue
                }

                $sourceRelative = Get-NormalizedRelativePath -BasePath $packRoot -FullPath $fullPath -BaseUri $packBaseUri
                $inputFiles.Add([pscustomobject]@{
                    SourcePath = $fullPath
                    Kind = 'root'
                    VirtualPath = [string]$definition.VirtualRoot
                    HintPath = ''
                    SourceRelativePath = $sourceRelative
                    RulePaths = @($sourceRelative)
                    Priority = [int]$definition.Priority
                })
            }

            'direct' {
                $sourceBaseUri = New-RelativePathBaseUri -BasePath $fullPath
                $files = Get-ChildItem -LiteralPath $fullPath -File -Recurse
                foreach ($file in $files) {
                    if (Test-IgnoredSourceFile -Name $file.Name) {
                        continue
                    }

                    $relative = Get-NormalizedRelativePath -BasePath $fullPath -FullPath $file.FullName -BaseUri $sourceBaseUri
                    $sourceRelative = Get-NormalizedRelativePath -BasePath $packRoot -FullPath $file.FullName -BaseUri $packBaseUri
                    $virtualPath = if (-not [string]$definition.VirtualRoot) {
                        $relative
                    }
                    elseif ($relative) {
                        ([string]$definition.VirtualRoot).TrimEnd('/') + '/' + $relative
                    }
                    else {
                        [string]$definition.VirtualRoot
                    }

                    $inputFiles.Add([pscustomobject]@{
                        SourcePath = $file.FullName
                        Kind = 'direct'
                        VirtualPath = $virtualPath
                        HintPath = ''
                        SourceRelativePath = $sourceRelative
                        RulePaths = @(
                            $sourceRelative
                            $relative
                        )
                        Priority = [int]$definition.Priority
                    })
                }
            }

            'auto' {
                foreach ($mapping in $autoSortMappings) {
                    if ($null -eq $mapping) {
                        continue
                    }

                    $mappedFolder = Resolve-FullPath -BasePath $fullPath -Path ([string]$mapping.Folder)
                    if (-not (Test-Path -LiteralPath $mappedFolder)) {
                        continue
                    }

                    $mappedBaseUri = New-RelativePathBaseUri -BasePath $mappedFolder
                    $files = Get-ChildItem -LiteralPath $mappedFolder -File -Recurse
                    foreach ($file in $files) {
                        if (Test-IgnoredSourceFile -Name $file.Name) {
                            continue
                        }

                        $relative = Get-NormalizedRelativePath -BasePath $mappedFolder -FullPath $file.FullName -BaseUri $mappedBaseUri
                        $sourceRelative = Get-NormalizedRelativePath -BasePath $packRoot -FullPath $file.FullName -BaseUri $packBaseUri
                        $hintPath = [System.IO.Path]::GetDirectoryName($relative)
                        if ($hintPath) {
                            $hintPath = $hintPath -replace '\\', '/'
                        }
                        else {
                            $hintPath = ''
                        }

                        $inputFiles.Add([pscustomobject]@{
                            SourcePath = $file.FullName
                            Kind = 'auto'
                            VirtualPath = $file.Name
                            HintPath = $hintPath
                            AssetPrefix = [string]$mapping.AssetPrefix
                            CategoryFolder = [string]$mapping.Folder
                            SourceRelativePath = $sourceRelative
                            RulePaths = @(
                                $sourceRelative
                                (([string]$mapping.Folder).TrimEnd('/') + '/' + $relative)
                            )
                            Priority = [int]$definition.Priority
                        })
                    }
                }
            }
        }
    }

    $selectedInputFiles = New-Object System.Collections.Generic.List[object]

    foreach ($inputFile in @($inputFiles | Sort-Object Priority, SourcePath)) {
        $selectedInputFile = $inputFile

        if ($fileVariants.Count -gt 0) {
            $matchingVariants = New-Object System.Collections.Generic.List[hashtable]

            foreach ($entry in @(Get-PackPathRuleMatches -Index $variantIndex -Paths $inputFile.RulePaths)) {
                if ($null -eq $entry.VersionMatches) {
                    $entry.VersionMatches = Test-VersionSelectorMatch -Options $entry.Options -VersionConfig $VersionConfig -VersionOrder $versionOrder -ContextDescription "$contextPrefix FileVariants Path '$($entry.Path)'"
                }
                if ($entry.VersionMatches) { $matchingVariants.Add($entry.Options) }
            }

            if ($matchingVariants.Count -gt 1) {
                $matchingVariantDescriptions = @($matchingVariants | ForEach-Object {
                    "$([string]$_.Path) -> $([string]$_.SourcePath)"
                })

                throw "$contextPrefix matches multiple FileVariants for '$($inputFile.SourceRelativePath)' in version '$([string]$VersionConfig.Id)': $($matchingVariantDescriptions -join ', ')"
            }

            if ($matchingVariants.Count -eq 1) {
                $variant = $matchingVariants[0]
                $variantSourceFullPath = Resolve-FullPath -BasePath $packRoot -Path ([string]$variant.SourcePath)
                if (-not (Test-Path -LiteralPath $variantSourceFullPath -PathType Leaf)) {
                    throw "$contextPrefix FileVariants Path '$([string]$variant.Path)' points to missing SourcePath '$([string]$variant.SourcePath)'."
                }

                $selectedInputFile = New-InputFileWithReplacedSource -InputFile $inputFile -NewSourcePath $variantSourceFullPath -PackRoot $packRoot -BaseUri $packBaseUri
            }
        }

        # Compatibility is an independent gate: permissive FileRules must not
        # reintroduce mod assets for a version the mod does not support.
        $compatibilityAllowed = $true
        foreach ($compatibility in $compatibilityRules) {
            if ($compatibility.IncludeForVersion) { continue }
            foreach ($rulePath in $compatibility.Paths) {
                foreach ($candidatePath in @($selectedInputFile.RulePaths)) {
                    if (Test-RuleMatch -Path ([string]$candidatePath) -Rule ([string]$rulePath)) {
                        $compatibilityAllowed = $false
                        break
                    }
                }
                if (-not $compatibilityAllowed) { break }
            }
            if (-not $compatibilityAllowed) { break }
        }
        if (-not $compatibilityAllowed) { continue }

        if ($fileRules.Count -eq 0) {
            $selectedInputFiles.Add($selectedInputFile)
            continue
        }

        $matchingRules = @(Get-PackPathRuleMatches -Index $ruleIndex -Paths $selectedInputFile.RulePaths)

        if ($matchingRules.Count -eq 0) {
            $selectedInputFiles.Add($selectedInputFile)
            continue
        }

        $includeForVersion = $false
        foreach ($entry in $matchingRules) {
            if ($null -eq $entry.VersionMatches) {
                $entry.VersionMatches = Test-VersionSelectorMatch -Options $entry.Options -VersionConfig $VersionConfig -VersionOrder $versionOrder -ContextDescription "$contextPrefix FileRules Path '$($entry.Path)'"
            }
            if ($entry.VersionMatches) {
                $includeForVersion = $true
                break
            }
        }

        if ($includeForVersion) {
            $selectedInputFiles.Add($selectedInputFile)
        }
    }

    return $selectedInputFiles.ToArray()
}

function Assert-ValidJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Get-Variable -Name BuildJsonValidator -Scope Script -ErrorAction SilentlyContinue)) {
        Add-Type -AssemblyName System.Web.Extensions
        $script:BuildJsonValidator = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    }
    $raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).ProviderPath, [System.Text.Encoding]::UTF8)
    # Get-Content -Raw returns null for an empty file; preserve its rejection.
    if ($raw.Length -eq 0) { throw [System.ArgumentNullException]::new('input') }
    $null = $script:BuildJsonValidator.DeserializeObject($raw)
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($DestinationPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $zipBaseUri = New-RelativePathBaseUri -BasePath $SourceDirectory
        $zipFiles = @(Get-ChildItem -LiteralPath $SourceDirectory -File -Recurse)
        $zipIndex = 0
        foreach ($file in $zipFiles) {
            Show-BuildProgress -Id 3 -Activity 'Creating ZIP' -Stage ([IO.Path]::GetFileName($DestinationPath)) -Completed $zipIndex -Total $zipFiles.Count
            $entryPath = Get-NormalizedRelativePath -BasePath $SourceDirectory -FullPath $file.FullName -BaseUri $zipBaseUri
            $entry = $archive.CreateEntry($entryPath, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                }
                finally {
                    $fileStream.Dispose()
                }
            }
            finally {
                $entryStream.Dispose()
            }
            $zipIndex++
        }
    }
    finally {
        $archive.Dispose()
        Close-BuildProgress -Id 3 -Activity 'Creating ZIP'
    }
}

function Build-PackVersion {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$VersionConfig,
        [hashtable]$PackOptions
    )

    if (-not $VersionConfig.Enabled) {
        return @{
            PackName = $PackDirectory.Name
            VersionId = $VersionConfig.Id
            Status = 'skipped'
            Reason = 'disabled'
        }
    }

    if ($VersionConfig.PackFormat -is [int] -or $VersionConfig.PackFormat -is [long]) {
        if ([int]$VersionConfig.PackFormat -le 0) {
            throw "Version '$($VersionConfig.Id)' is enabled but PackFormat is not set."
        }
    }

    $definitionPath = Get-CombinedDefinitionPath -PackDirectory $PackDirectory
    if ($definitionPath) {
        & (Join-Path $PSScriptRoot 'build-combined-pack.ps1') -DefinitionPath $definitionPath -ConfigPath $ConfigPath -Version $VersionConfig.Id | Out-Host
        if (-not $?) { throw "Combined build failed for '$($PackDirectory.Name)'." }
        $tokens = Get-PackTokens -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig
        $packageName = Convert-Tokens -Value $Config.PackageNameTemplate -Tokens $tokens
        return @{ PackName = $PackDirectory.Name; VersionId = $VersionConfig.Id; Status = 'success'; WarningCount = 0;
            ZipPath = Find-PackBuildZip -BuildZipPath (Join-Path (Resolve-FullPath -BasePath $RepoRoot -Path $Config.BuildRoot) "$($PackDirectory.Name)/$packageName.zip") -MinecraftVersion $VersionConfig.Id }
    }
    $tokens = Get-PackTokens -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig
    $buildRoot = Resolve-FullPath -BasePath $RepoRoot -Path ([string]$Config.BuildRoot)
    Ensure-Directory -Path $buildRoot
    $packageBaseName = Convert-Tokens -Value ([string]$Config.PackageNameTemplate) -Tokens $tokens
    $zipPackRoot = Join-Path -Path $buildRoot -ChildPath $PackDirectory.Name
    $zipPath = Join-Path -Path $zipPackRoot -ChildPath "$packageBaseName.zip"
    if (Test-Path -LiteralPath "$zipPath.versions.json") { Remove-Item -LiteralPath "$zipPath.versions.json" }
    $tempBuildRoot = Get-TemporaryBuildRoot
    $outputFolder = Join-Path -Path (Join-Path -Path $tempBuildRoot -ChildPath $PackDirectory.Name) -ChildPath ([string]$VersionConfig.Id)

    if (Test-Path -LiteralPath $outputFolder) {
        Remove-Item -LiteralPath $outputFolder -Recurse -Force
    }
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Ensure-Directory -Path $zipPackRoot
    Ensure-Directory -Path $outputFolder
    try {
        $activity = "$($PackDirectory.Name) / Minecraft $($VersionConfig.Id)"
        Show-BuildProgress -Id 2 -Activity $activity -Stage 'Selecting source files'
        if ($null -eq $PackOptions) { $PackOptions = Get-PackBuildOptions -PackDirectory $PackDirectory -Config $Config }
        $inputFiles = Get-PackInputFiles -PackDirectory $PackDirectory -Config $Config -VersionConfig $VersionConfig -PackOptions $PackOptions
        $warnings = New-Object System.Collections.Generic.List[string]
        $destinations = @{}
        $catalog = $null
        $routeCache = Get-PackRouteCache -RepoRoot $RepoRoot -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig
        $resolvedRouteCache = @{}

        $inputIndex = 0
        foreach ($inputFile in $inputFiles) {
            Show-BuildProgress -Id 2 -Activity $activity -Stage 'Resolving asset paths' -Completed $inputIndex -Total @($inputFiles).Count
            $inputIndex++
            $resolvedPath = switch ($inputFile.Kind) {
                'root' { $inputFile.VirtualPath }
                'direct' { $inputFile.VirtualPath }
                'auto' {
                    if ($null -eq $catalog) {
                        $catalog = Get-VanillaAssetCatalog -RepoRoot $RepoRoot -Config $Config -VersionConfig $VersionConfig
                    }

                    Resolve-AutoAssetPath -FileName $inputFile.VirtualPath -HintPath $inputFile.HintPath -AssetPrefix $inputFile.AssetPrefix -Catalog $catalog -CategoryFolder $inputFile.CategoryFolder -RouteCache $routeCache -RouteCacheKey $inputFile.SourceRelativePath
                }
                default {
                    throw "Unknown input kind '$($inputFile.Kind)'."
                }
            }

            if ($resolvedPath -ne 'pack.png' -and $resolvedPath.StartsWith('assets/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $resolvedPath = Get-TransformedPath -RelativePath $resolvedPath -VersionConfig $VersionConfig
                if ($null -eq $resolvedPath) {
                    continue
                }
            }

            if ($inputFile.Kind -eq 'auto') {
                $resolvedRouteCache[$inputFile.SourceRelativePath] = $resolvedPath
            }

            if ($resolvedPath -eq 'pack.mcmeta') {
                throw "Supply pack.mcmeta at the source pack root, or use PackMetadata/RootMetadata in pack.build.psd1."
            }
            if ($Config.Validation.RequireLowercasePaths -and $resolvedPath.StartsWith('assets/', [System.StringComparison]::OrdinalIgnoreCase) -and $resolvedPath -cmatch '[A-Z]') {
                throw "Output path contains uppercase characters for pack '$($PackDirectory.Name)' version '$($VersionConfig.Id)': $resolvedPath"
            }

            if ($destinations.ContainsKey($resolvedPath)) {
                $existing = $destinations[$resolvedPath]
                if ([int]$inputFile.Priority -gt [int]$existing.Priority) {
                    $warnings.Add("Overriding '$resolvedPath' with '$($inputFile.SourcePath)' over '$($existing.SourcePath)'")
                    $destinations[$resolvedPath] = [pscustomobject]@{
                        SourcePath = $inputFile.SourcePath
                        Priority = [int]$inputFile.Priority
                    }
                }
                elseif ([int]$inputFile.Priority -eq [int]$existing.Priority) {
                    throw "Two source files resolve to the same output path for pack '$($PackDirectory.Name)' version '$($VersionConfig.Id)': $resolvedPath"
                }

                continue
            }

            $destinations[$resolvedPath] = [pscustomobject]@{
                SourcePath = $inputFile.SourcePath
                Priority = [int]$inputFile.Priority
            }
        }

        $copyIndex = 0
        foreach ($destPath in $destinations.Keys) {
            Show-BuildProgress -Id 2 -Activity $activity -Stage 'Copying assets' -Completed $copyIndex -Total $destinations.Count
            $fullDestPath = Resolve-FullPath -BasePath $outputFolder -Path $destPath
            Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($fullDestPath))
            Copy-Item -LiteralPath $destinations[$destPath].SourcePath -Destination $fullDestPath -Force
            $copyIndex++
        }

        $mcmetaObject = New-PackMcmetaObject -Tokens $tokens -VersionConfig $VersionConfig
        $customMetadata = @{}
        $sourceMcmeta = Join-Path -Path $PackDirectory.FullName -ChildPath 'pack.mcmeta'
        if (Test-Path -LiteralPath $sourceMcmeta -PathType Leaf) {
            $customMetadata = ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $sourceMcmeta -Raw | ConvertFrom-Json)
            if ($customMetadata -isnot [hashtable]) {
                throw "Source pack.mcmeta must contain a JSON object: $sourceMcmeta"
            }
        }
        $compatibilityRules = @(Get-PackCompatibilityRules -Options $packOptions -Config $Config -VersionConfig $VersionConfig -PackName $PackDirectory.Name)
        $supportText = Get-PackCompatibilityText -Rules $compatibilityRules
        if ($supportText) {
            if ($destinations.ContainsKey('compatibility.txt')) {
                throw "Pack '$($PackDirectory.Name)' supplies compatibility.txt and Compatibility. Remove the source compatibility.txt to generate it from compatibility entries."
            }
            [IO.File]::WriteAllText((Join-Path $outputFolder 'compatibility.txt'), $supportText, (New-Object System.Text.UTF8Encoding($false)))
            $destinations['compatibility.txt'] = @{ SourcePath = '<generated compatibility support>'; Priority = 30 }
        }
        if ($packOptions.ContainsKey('RootMetadata')) {
            $customMetadata = Merge-Hashtable -Base $customMetadata -Overlay (ConvertTo-Hashtable -InputObject $packOptions.RootMetadata)
        }
        if ($packOptions.ContainsKey('PackMetadata')) {
            $customMetadata = Merge-Hashtable -Base $customMetadata -Overlay @{ pack = (ConvertTo-Hashtable -InputObject $packOptions.PackMetadata) }
        }
        if ($packOptions.ContainsKey('Description')) {
            $customMetadata = Merge-Hashtable -Base $customMetadata -Overlay @{ pack = @{ description = (Convert-Tokens -Value ([string]$packOptions.Description) -Tokens $tokens) } }
        }
        if ($customMetadata.ContainsKey('pack')) {
            if ($customMetadata.pack -isnot [hashtable]) {
                throw "Custom pack metadata must contain a JSON object for 'pack'."
            }
            # Compatibility values always come from the target version matrix.
            foreach ($formatKey in @('pack_format', 'supported_formats', 'min_format', 'max_format')) {
                $customMetadata.pack.Remove($formatKey)
            }
        }
        $mcmetaObject = Merge-Hashtable -Base (ConvertTo-Hashtable -InputObject $mcmetaObject) -Overlay $customMetadata
        $mcmetaJson = $mcmetaObject | ConvertTo-Json -Depth 100
        Set-Content -LiteralPath (Join-Path -Path $outputFolder -ChildPath 'pack.mcmeta') -Value $mcmetaJson -Encoding UTF8

        Show-BuildProgress -Id 2 -Activity $activity -Stage 'Validating metadata and assets'
        if ($Config.Validation.ParseJsonFiles) {
            foreach ($jsonFile in Get-ChildItem -LiteralPath $outputFolder -File -Recurse -Filter '*.json') {
                try {
                    Assert-ValidJsonFile -Path $jsonFile.FullName
                }
                catch {
                    throw "Invalid JSON in '$($jsonFile.FullName)': $($_.Exception.Message)"
                }
            }
        }

        if ($Config.Validation.ParseMcmetaFiles) {
            foreach ($mcmetaFile in Get-ChildItem -LiteralPath $outputFolder -File -Recurse -Filter '*.mcmeta') {
                try {
                    Assert-ValidJsonFile -Path $mcmetaFile.FullName
                }
                catch {
                    throw "Invalid mcmeta JSON in '$($mcmetaFile.FullName)': $($_.Exception.Message)"
                }
            }
        }

        if ($Config.Validation.RequireTextureForTextureMcmeta) {
            foreach ($mcmetaFile in Get-ChildItem -LiteralPath $outputFolder -File -Recurse -Filter '*.png.mcmeta') {
                $pngPath = $mcmetaFile.FullName.Substring(0, $mcmetaFile.FullName.Length - '.mcmeta'.Length)
                if (-not (Test-Path -LiteralPath $pngPath)) {
                    throw "Texture metadata file is missing its texture pair: $($mcmetaFile.FullName)"
                }
            }
        }

        foreach ($requiredRule in @(Get-HashtableValueOrDefault -Table $VersionConfig -Key 'Required' -DefaultValue @())) {
            $matched = $false
            foreach ($builtPath in $destinations.Keys + @('pack.mcmeta')) {
                if (Test-RuleMatch -Path $builtPath -Rule ([string]$requiredRule)) {
                    $matched = $true
                    break
                }
            }

            if (-not $matched) {
                throw "Required output rule missing for pack '$($PackDirectory.Name)' version '$($VersionConfig.Id)': $requiredRule"
            }
        }

        Show-BuildProgress -Id 2 -Activity $activity -Stage 'Packaging ZIP'
        New-ZipFromDirectory -SourceDirectory $outputFolder -DestinationPath $zipPath
        Save-PackRouteCache -RepoRoot $RepoRoot -Config $Config -PackDirectory $PackDirectory -VersionConfig $VersionConfig -RouteCache $resolvedRouteCache

        return @{
            PackName = $PackDirectory.Name
            VersionId = [string]$VersionConfig.Id
            Status = 'success'
            ZipPath = $zipPath
            WarningCount = $warnings.Count
        }
    }
    finally {
        Close-BuildProgress -Id 2 -Activity 'Building pack'
        if (Test-Path -LiteralPath $outputFolder) {
            Remove-Item -LiteralPath $outputFolder -Recurse -Force
        }
    }
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$configFullPath = Resolve-FullPath -BasePath $repoRoot -Path $ConfigPath
if (-not (Test-Path -LiteralPath $configFullPath)) {
    throw "Config file not found: $configFullPath"
}

$config = Import-PowerShellDataFile -Path $configFullPath

if ($config.ContainsKey('VersionMatrixPath') -and $config.VersionMatrixPath) {
    $versionMatrixPath = Resolve-FullPath -BasePath $repoRoot -Path ([string]$config.VersionMatrixPath)
    if (-not (Test-Path -LiteralPath $versionMatrixPath)) {
        throw "Version matrix file not found: $versionMatrixPath"
    }

    $versionMatrix = Import-PowerShellDataFile -Path $versionMatrixPath
    if (-not $versionMatrix.ContainsKey('Versions') -or @($versionMatrix.Versions).Count -eq 0) {
        throw "Version matrix file does not define any versions: $versionMatrixPath"
    }

    $config['Versions'] = @($versionMatrix.Versions | ForEach-Object { Normalize-VersionConfig -VersionConfig $_ })
}

if (-not $config.ContainsKey('Versions') -or @($config.Versions).Count -eq 0) {
    throw "No Minecraft versions are configured."
}

$config['Versions'] = @($config.Versions | ForEach-Object { Normalize-VersionConfig -VersionConfig $_ })

if ($PromptForPack -and $Pack) {
    throw 'Use either -Pack or -PromptForPack, not both.'
}

if ($PromptForVersion -and $Version) {
    throw 'Use either -Version or -PromptForVersion, not both.'
}

if ($ListVersions) {
    foreach ($entry in @($config.Versions)) {
        $state = if ($entry.Enabled) { 'enabled' } else { 'disabled' }
        Write-Output "$($entry.Id)`t$state`tpack_format=$(Format-PackFormatValue -Value $entry.PackFormat)"
    }
    exit 0
}

if ($PromptForPack) {
    $Pack = @(Read-RequestedPackNames -RepoRoot $repoRoot -Config $config)
}

# Interactive pack selection must also ask which versions to build, even if
# an IDE's saved run configuration supplies only -PromptForPack.
if ($PromptForVersion -or ($PromptForPack -and -not $Version -and -not $ListPacks)) {
    $Version = @(Read-RequestedVersions -Config $config)
}

if ($Version) {
    $Version = @(Expand-RequestedVersionSelection -InputValue ($Version -join ',') -Config $config)
}

$packDirectories = Get-PackDirectories -RepoRoot $repoRoot -Config $config -RequestedPackNames $Pack

if ($ListPacks) {
    foreach ($packDirectory in $packDirectories) {
        Write-Output $packDirectory.Name
    }
    exit 0
}

$buildRoot = Resolve-FullPath -BasePath $repoRoot -Path ([string]$config.BuildRoot)
if ($Clean) {
    foreach ($path in @(Get-TemporaryBuildRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

$selectedVersions = @($config.Versions)
if ($Version) {
    $lookup = @{}
    foreach ($requested in $Version) {
        $lookup[$requested] = $true
    }

    $selectedVersions = @($config.Versions | Where-Object { $lookup.ContainsKey($_.Id) })
    if ($selectedVersions.Count -ne $lookup.Keys.Count) {
        $foundIds = @($selectedVersions | ForEach-Object { $_.Id })
        $missing = @($lookup.Keys | Where-Object { $_ -notin $foundIds })
        throw "Unknown version id(s): $($missing -join ', ')"
    }
}

$results = @()
$failures = New-Object System.Collections.Generic.List[string]

$buildJobs = @(
foreach ($packDirectory in $packDirectories) {
    $packOptions = Get-PackBuildOptions -PackDirectory $packDirectory -Config $config
    $packSelectedVersions = Get-PackSelectedVersions -PackDirectory $packDirectory -Config $config -GloballySelectedVersions $selectedVersions -PackOptions $packOptions
    foreach ($versionConfig in $packSelectedVersions) {
        @{ PackDirectory = $packDirectory; VersionConfig = $versionConfig; PackOptions = $packOptions }
    }
}
)
$jobIndex = 0
try {
    foreach ($job in $buildJobs) {
        $packDirectory = $job.PackDirectory
        $versionConfig = $job.VersionConfig
        Show-BuildProgress -Id 0 -Activity 'Building resource packs' -Stage "$($packDirectory.Name) / Minecraft $($versionConfig.Id)" -Completed $jobIndex -Total $buildJobs.Count
        try {
            $result = Build-PackVersion -RepoRoot $repoRoot -Config $config -PackDirectory $packDirectory -VersionConfig $versionConfig -PackOptions $job.PackOptions
            $results += ,$result
            if ($result.Status -eq 'success') {
                Write-Output "Built $($result.PackName) $($result.VersionId) -> $($result.ZipPath)"
            }
        }
        catch {
            $message = "Build failed for pack '$($packDirectory.Name)' version '$($versionConfig.Id)': $($_.Exception.Message)"
            $failures.Add($message)
            Write-Warning $message
        }
        $jobIndex++
        Show-BuildProgress -Id 0 -Activity 'Building resource packs' -Stage 'Build jobs processed' -Completed $jobIndex -Total $buildJobs.Count
    }
}
finally { Close-BuildProgress -Id 0 -Activity 'Building resource packs' }

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

foreach ($directory in $packDirectories) {
    $options = Get-PackBuildOptions -PackDirectory $directory -Config $config
    Merge-IdenticalPackBuilds -Directory (Join-Path $buildRoot $directory.Name) -PackName $directory.Name -DisplayName (Get-ReleasePackDisplayName -PackDirectory $directory -PackOptions $options) -Config $config
    foreach ($zip in Get-ChildItem -LiteralPath (Join-Path $buildRoot $directory.Name) -File -Filter '*.zip' -ErrorAction SilentlyContinue) {
        Write-Output "Package $($directory.Name) / $(@(Get-PackZipVersions $zip.FullName) -join ', ') -> $($zip.FullName)"
    }
}
