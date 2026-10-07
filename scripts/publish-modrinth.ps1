[CmdletBinding()]
param(
    [string]$ConfigPath = 'config/texture-pack.build.psd1',
    [string[]]$Version,
    [string[]]$Pack,
    [switch]$PromptForPack,
    [switch]$PromptForVersion,
    [switch]$PromptForProject,
    [switch]$Build,
    [switch]$SkipBuild,
    [switch]$Publish,
    [switch]$Yes,
    [switch]$CheckRemote,
    [switch]$PromptForToken,
    [switch]$PromptForChangelog,
    [AllowEmptyString()][string]$Changelog,
    [switch]$PromptForReleaseVersion,
    [Alias('UploadVersion')][string]$ReleaseVersion,
    [string]$ArchiveRoot = 'archive',
    [string]$LocalModrinthStatePath = 'config/modrinth.local.psd1',
    [string]$ApiBaseUrl = 'https://api.modrinth.com/v2',
    [string]$TokenEnvironmentVariable = 'MODRINTH_TOKEN',
    [string]$DefaultReleaseVersion = '1.0.0',
    [string]$DefaultStatus = 'listed',
    [string]$DefaultVersionType = 'release',
    [string]$DefaultEnvironment = 'client_only',
    [string]$UserAgent = 'grego/resource-packs-manager/1.0 (Modrinth publishing script)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Net.Http

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

function Get-RepoRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $repoFullPath = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if (-not $fullPath.StartsWith($repoFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    return $fullPath.Substring($repoFullPath.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ).Replace('\', '/')
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function ConvertTo-Hashtable {
    param($InputObject)

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

function ConvertTo-Psd1StringLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return '$null'
    }

    return "'$($Value.Replace("'", "''"))'"
}

function Get-ModrinthZipFileName {
    param([Parameter(Mandatory = $true)]$Item)

    return "$($Item.PackName)-$($Item.VersionNumber).zip"
}

function Get-HashtableValueOrDefault {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Table,
        [Parameter(Mandatory = $true)][string]$Key,
        $DefaultValue
    )

    if ($Table.ContainsKey($Key) -and $null -ne $Table[$Key]) {
        return $Table[$Key]
    }

    return $DefaultValue
}

function Convert-Tokens {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $result = $Value
    foreach ($entry in $Tokens.GetEnumerator()) {
        $result = $result.Replace("{$($entry.Key)}", [string]$entry.Value)
    }

    return $result
}

function Convert-ToPackDisplayName {
    param([Parameter(Mandatory = $true)][string]$PackFolderName)

    $spaced = ($PackFolderName -replace '[_-]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($spaced)) {
        return $PackFolderName
    }

    return [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($spaced.ToLowerInvariant())
}

function Normalize-VersionConfig {
    param($VersionConfig)

    $normalized = ConvertTo-Hashtable -InputObject $VersionConfig
    if (-not $normalized.ContainsKey('Enabled') -or $null -eq $normalized['Enabled']) {
        $normalized['Enabled'] = $true
    }

    return $normalized
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

function Read-RequestedPackNames {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Config
    )

    $availablePacks = @(Get-PackDirectories -RepoRoot $RepoRoot -Config $Config -RequestedPackNames @() | Select-Object -ExpandProperty Name)
    if ($availablePacks.Count -eq 0) {
        throw 'No texture packs are available to select.'
    }

    Write-Host 'Available texture packs:'
    foreach ($packName in $availablePacks) {
        Write-Host "  - $packName"
    }
    Write-Host ''

    $inputValue = Read-Host 'Enter texture pack name(s) to publish (comma-separated)'
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        throw 'No texture pack names entered.'
    }

    return @(
        $inputValue.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
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

    $inputValue = Read-Host 'Enter version or version range'
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        throw 'No version selection entered.'
    }

    return @(Expand-RequestedVersionSelection -InputValue $inputValue -Config $Config)
}

function Read-RequestedModrinthProjectReference {
    param(
        [Parameter(Mandatory = $true)][string]$PackName,
        [AllowEmptyString()][string]$DefaultProjectReference
    )

    Write-Host ''
    Write-Host "Modrinth project for pack '$PackName':"
    Write-Host '  Paste a full project URL, slug, or project ID.'
    Write-Host '  Example URL: https://modrinth.com/resourcepack/alternative-birch-leaves'
    if (-not [string]::IsNullOrWhiteSpace($DefaultProjectReference)) {
        Write-Host "  Press Enter to use: $DefaultProjectReference"
    }

    $inputValue = Read-Host 'Enter Modrinth project'
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        if ([string]::IsNullOrWhiteSpace($DefaultProjectReference)) {
            throw "No Modrinth project entered for pack '$PackName'."
        }

        $inputValue = $DefaultProjectReference
    }

    return ConvertFrom-ModrinthProjectReference -ProjectReference $inputValue
}

function Assert-LocalModrinthStateIsNotTracked {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $relativePath = Get-RepoRelativePath -RepoRoot $RepoRoot -Path $StatePath
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        return
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        return
    }

    $trackedPaths = @(& git -C $RepoRoot ls-files -- $relativePath)
    if ($LASTEXITCODE -eq 0 -and $trackedPaths -contains $relativePath) {
        throw "Refusing to use local Modrinth state because it is tracked by git: $relativePath. Remove it from git history/index before storing tokens there."
    }
}

function Read-LocalModrinthState {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    Assert-LocalModrinthStateIsNotTracked -RepoRoot $RepoRoot -StatePath $StatePath

    $state = @{
        Projects = @{}
    }

    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        $state = ConvertTo-Hashtable -InputObject (Import-PowerShellDataFile -Path $StatePath)
    }

    if (-not $state.ContainsKey('Projects') -or $null -eq $state.Projects) {
        $state['Projects'] = @{}
    }
    else {
        $state['Projects'] = ConvertTo-Hashtable -InputObject $state.Projects
    }

    return $state
}

function Get-LocalModrinthPackState {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$PackName
    )

    if (-not $State.ContainsKey('Projects') -or -not $State.Projects.ContainsKey($PackName)) {
        return @{}
    }

    return ConvertTo-Hashtable -InputObject $State.Projects[$PackName]
}

function Write-LocalModrinthState {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    $parentPath = Split-Path -Path $StatePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        Ensure-Directory -Path $parentPath
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@{') | Out-Null
    $lines.Add('    Projects = @{') | Out-Null

    foreach ($packName in @($State.Projects.Keys | Sort-Object)) {
        $packState = ConvertTo-Hashtable -InputObject $State.Projects[$packName]
        $projectId = [string](Get-HashtableValueOrDefault -Table $packState -Key 'ProjectId' -DefaultValue '')
        $tokenValue = [string](Get-HashtableValueOrDefault -Table $packState -Key 'Token' -DefaultValue '')
        $updatedAt = [string](Get-HashtableValueOrDefault -Table $packState -Key 'UpdatedAt' -DefaultValue '')

        $lines.Add("        $(ConvertTo-Psd1StringLiteral -Value $packName) = @{") | Out-Null
        $lines.Add("            ProjectId = $(ConvertTo-Psd1StringLiteral -Value $projectId)") | Out-Null
        $lines.Add("            Token = $(ConvertTo-Psd1StringLiteral -Value $tokenValue)") | Out-Null
        $lines.Add("            UpdatedAt = $(ConvertTo-Psd1StringLiteral -Value $updatedAt)") | Out-Null
        $lines.Add('        }') | Out-Null
    }

    $lines.Add('    }') | Out-Null
    $lines.Add('}') | Out-Null

    Set-Content -LiteralPath $StatePath -Value $lines -Encoding UTF8
}

function Save-LocalModrinthPackState {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$PackName,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Token
    )

    $State.Projects[$PackName] = @{
        ProjectId = $ProjectId
        Token = $Token
        UpdatedAt = [System.DateTimeOffset]::UtcNow.ToString('o')
    }

    Write-LocalModrinthState -State $State -StatePath $StatePath
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

    $configPath = Join-Path -Path $PackDirectory.FullName -ChildPath ([string]$Config.PackBuildConfigFile)
    if (-not (Test-Path -LiteralPath $configPath)) {
        return @{}
    }

    return ConvertTo-Hashtable -InputObject (Import-PowerShellDataFile -Path $configPath)
}

function Get-PackSelectedVersions {
    param(
        [Parameter(Mandatory = $true)]$PackDirectory,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][object[]]$GloballySelectedVersions
    )

    $packOptions = Get-PackBuildOptions -PackDirectory $PackDirectory -Config $Config
    if ($packOptions.Count -eq 0) {
        return @($GloballySelectedVersions)
    }

    $versionOrder = Get-VersionOrderLookup -Config $Config
    $contextDescription = "Pack '$($PackDirectory.Name)' inside $([string]$Config.PackBuildConfigFile)"

    return @($GloballySelectedVersions | Where-Object {
        Test-VersionSelectorMatch -Options $packOptions -VersionConfig $_ -VersionOrder $versionOrder -ContextDescription $contextDescription
    })
}

function ConvertFrom-ModrinthProjectReference {
    param([Parameter(Mandatory = $true)][string]$ProjectReference)

    $value = $ProjectReference.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $value
    }

    if ($value -match '^https?://') {
        try {
            $uri = [System.Uri]$value
            $segments = @(
                $uri.AbsolutePath.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
            )

            if ($uri.Host -notmatch '(^|\.)modrinth\.com$') {
                throw "Project URL host must be modrinth.com: $value"
            }

            if ($segments.Count -lt 2) {
                throw "Project URL must look like https://modrinth.com/resourcepack/<slug>: $value"
            }

            $projectType = $segments[0].ToLowerInvariant()
            if ($projectType -notin @('resourcepack', 'mod', 'plugin', 'datapack', 'shader')) {
                throw "Unsupported Modrinth project URL type '$projectType' in: $value"
            }

            return [System.Uri]::UnescapeDataString($segments[1])
        }
        catch {
            throw "Invalid Modrinth project reference '$ProjectReference': $($_.Exception.Message)"
        }
    }

    return $value
}

function Get-PackModrinthConfig {
    param(
        [Parameter(Mandatory = $true)][string]$PackName,
        [Parameter(Mandatory = $true)][hashtable]$PackOptions
    )

    $modrinthConfig = @{}
    if ($PackOptions.ContainsKey('Modrinth') -and $PackOptions.Modrinth) {
        $modrinthConfig = ConvertTo-Hashtable -InputObject $PackOptions.Modrinth
    }

    if ($modrinthConfig.ContainsKey('Enabled') -and -not [bool]$modrinthConfig.Enabled) {
        return $null
    }

    $projectId = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'ProjectUrl' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($projectId)) {
        $projectId = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Url' -DefaultValue '')
    }
    if ([string]::IsNullOrWhiteSpace($projectId)) {
        $projectId = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'ProjectId' -DefaultValue '')
    }
    if ([string]::IsNullOrWhiteSpace($projectId)) {
        $projectId = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Project' -DefaultValue '')
    }
    if ([string]::IsNullOrWhiteSpace($projectId)) {
        $projectId = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Slug' -DefaultValue '')
    }
    if ([string]::IsNullOrWhiteSpace($projectId)) {
        $projectId = $PackName
    }

    $projectId = ConvertFrom-ModrinthProjectReference -ProjectReference $projectId

    $releaseVersion = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'ReleaseVersion' -DefaultValue $DefaultReleaseVersion)
    $versionNumberTemplate = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'VersionNumberTemplate' -DefaultValue '{ReleaseVersion}-mc.{MinecraftVersion}')
    $nameTemplate = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'NameTemplate' -DefaultValue '{PackDisplayName} {ReleaseVersion} for Minecraft {MinecraftVersion}')
    $changelog = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Changelog' -DefaultValue '')
    $status = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Status' -DefaultValue $DefaultStatus)
    $versionType = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'VersionType' -DefaultValue $DefaultVersionType)
    $environment = [string](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Environment' -DefaultValue $DefaultEnvironment)
    $featured = [bool](Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Featured' -DefaultValue $false)
    $loaders = @(Get-HashtableValueOrDefault -Table $modrinthConfig -Key 'Loaders' -DefaultValue @('minecraft')) | ForEach-Object { [string]$_ }

    return [pscustomobject]@{
        ProjectId = $projectId
        ReleaseVersion = $releaseVersion
        VersionNumberTemplate = $versionNumberTemplate
        NameTemplate = $nameTemplate
        Changelog = $changelog
        Status = $status
        VersionType = $versionType
        Environment = $environment
        Featured = $featured
        Loaders = @($loaders)
    }
}

function Test-ZipHasRootPackMcmeta {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -eq 'pack.mcmeta') {
                return $true
            }
        }

        return $false
    }
    finally {
        $archive.Dispose()
    }
}

function New-ModrinthHttpClient {
    param([string]$Token)

    $client = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $UserAgent) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $client.DefaultRequestHeaders.TryAddWithoutValidation('Authorization', $Token) | Out-Null
    }

    return $client
}

function Read-PlainTextSecret {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $secureValue = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Invoke-ModrinthGetProjectVersions {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$ProjectId
    )

    $encodedProjectId = [System.Uri]::EscapeDataString($ProjectId)
    $encodedLoaders = [System.Uri]::EscapeDataString('["minecraft"]')
    $uri = "$($ApiBaseUrl.TrimEnd('/'))/project/$encodedProjectId/version?loaders=$encodedLoaders&include_changelog=false"
    $response = $Client.GetAsync($uri).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if (-not $response.IsSuccessStatusCode) {
        throw "Failed to read Modrinth versions for project '$ProjectId' ($([int]$response.StatusCode) $($response.ReasonPhrase)): $body"
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        return @()
    }

    return @($body | ConvertFrom-Json)
}

function Invoke-ModrinthGetProject {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$ProjectId
    )

    $encodedProjectId = [System.Uri]::EscapeDataString($ProjectId)
    $uri = "$($ApiBaseUrl.TrimEnd('/'))/project/$encodedProjectId"
    $response = $Client.GetAsync($uri).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if (-not $response.IsSuccessStatusCode) {
        throw "Failed to read Modrinth project '$ProjectId' ($([int]$response.StatusCode) $($response.ReasonPhrase)): $body"
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "Modrinth project '$ProjectId' returned an empty response."
    }

    return ($body | ConvertFrom-Json)
}

function Publish-ModrinthVersion {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]$Item
    )

    $data = [ordered]@{
        name = $Item.VersionName
        version_number = $Item.VersionNumber
        changelog = $Item.Changelog
        dependencies = @()
        game_versions = @($Item.MinecraftVersion)
        version_type = $Item.VersionType
        loaders = @($Item.Loaders)
        status = $Item.Status
        featured = [bool]$Item.Featured
        project_id = $Item.ProjectId
        file_parts = @('file')
        primary_file = 'file'
        environment = $Item.Environment
    }

    $json = $data | ConvertTo-Json -Depth 20 -Compress
    $multipart = [System.Net.Http.MultipartFormDataContent]::new()
    $fileStream = [System.IO.File]::OpenRead($Item.ZipPath)
    try {
        $dataContent = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
        $multipart.Add($dataContent, 'data')

        $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/zip')
        $multipart.Add($fileContent, 'file', (Get-ModrinthZipFileName -Item $Item))

        $uri = "$($ApiBaseUrl.TrimEnd('/'))/version"
        $response = $Client.PostAsync($uri, $multipart).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode) {
            throw "Failed to create Modrinth version '$($Item.VersionNumber)' for '$($Item.PackName)' ($([int]$response.StatusCode) $($response.ReasonPhrase)): $body"
        }

        if ([string]::IsNullOrWhiteSpace($body)) {
            return $null
        }

        return ($body | ConvertFrom-Json)
    }
    finally {
        $multipart.Dispose()
        $fileStream.Dispose()
    }
}

function Assert-ValidUploadItem {
    param([Parameter(Mandatory = $true)]$Item)

    if ($Item.VersionNumber -notmatch '^[0-9A-Za-z][0-9A-Za-z._+\-]*$') {
        throw "Invalid Modrinth version number for pack '$($Item.PackName)' Minecraft '$($Item.MinecraftVersion)': '$($Item.VersionNumber)'. Use letters, numbers, dots, underscores, plus signs, and hyphens only."
    }

    if ($Item.VersionType -notin @('release', 'beta', 'alpha')) {
        throw "Invalid Modrinth version type for pack '$($Item.PackName)': '$($Item.VersionType)'."
    }

    if ($Item.Status -notin @('listed', 'archived', 'draft', 'unlisted', 'scheduled')) {
        throw "Invalid Modrinth status for pack '$($Item.PackName)': '$($Item.Status)'."
    }

    if (-not (Test-Path -LiteralPath $Item.ZipPath -PathType Leaf)) {
        throw "Upload ZIP not found for pack '$($Item.PackName)' Minecraft '$($Item.MinecraftVersion)': $($Item.ZipPath)"
    }

    if (-not (Test-ZipHasRootPackMcmeta -ZipPath $Item.ZipPath)) {
        throw "Build ZIP does not contain root pack.mcmeta: $($Item.ZipPath)"
    }
}

function Move-UploadedZipToArchive {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$ArchiveRootPath
    )

    $destinationDirectory = Join-Path -Path (Join-Path -Path $ArchiveRootPath -ChildPath $Item.PackName) -ChildPath $Item.ReleaseVersion
    Ensure-Directory -Path $destinationDirectory

    $destinationFileName = Get-ModrinthZipFileName -Item $Item
    $destinationPath = Join-Path -Path $destinationDirectory -ChildPath $destinationFileName
    if ([System.IO.Path]::GetFullPath($Item.ZipPath).Equals([System.IO.Path]::GetFullPath($destinationPath), [System.StringComparison]::OrdinalIgnoreCase)) {
        return $destinationPath
    }

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $sourceHash = (Get-FileHash -LiteralPath $Item.ZipPath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash) {
            Remove-Item -LiteralPath $Item.ZipPath
            return $destinationPath
        }

        $timestamp = [System.DateTimeOffset]::UtcNow.ToString('yyyyMMddHHmmss')
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($destinationFileName)
        $extension = [System.IO.Path]::GetExtension($Item.ZipPath)
        $destinationPath = Join-Path -Path $destinationDirectory -ChildPath "$baseName-uploaded-$timestamp$extension"
    }

    Move-Item -LiteralPath $Item.ZipPath -Destination $destinationPath
    return $destinationPath
}

function Invoke-BuildForPublishItem {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$PackName,
        [Parameter(Mandatory = $true)][string]$VersionId
    )

    $buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'build-texture-packs.ps1'
    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
        throw "Build script not found: $buildScript"
    }

    Write-Host "Building $PackName $VersionId because no archive or build ZIP exists..."
    & $buildScript -ConfigPath $ConfigPath -Pack $PackName -Version $VersionId
    if (-not $?) {
        throw "Build failed for pack '$PackName' Minecraft '$VersionId'."
    }
}

function Resolve-PublishZipPath {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$BuildZipPath,
        [Parameter(Mandatory = $true)][string]$ArchiveRootPath,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][bool]$ShouldBuildIfMissing
    )

    $archiveZipPath = Join-Path -Path (Join-Path -Path (Join-Path -Path $ArchiveRootPath -ChildPath $Item.PackName) -ChildPath $Item.ReleaseVersion) -ChildPath (Get-ModrinthZipFileName -Item $Item)
    if (Test-Path -LiteralPath $archiveZipPath -PathType Leaf) {
        return [pscustomobject]@{
            Path = $archiveZipPath
            Source = 'archive'
        }
    }

    if (Test-Path -LiteralPath $BuildZipPath -PathType Leaf) {
        return [pscustomobject]@{
            Path = $BuildZipPath
            Source = 'build'
        }
    }

    if ($ShouldBuildIfMissing) {
        Invoke-BuildForPublishItem -ConfigPath $ConfigPath -PackName $Item.PackName -VersionId $Item.MinecraftVersion
        if (Test-Path -LiteralPath $BuildZipPath -PathType Leaf) {
            return [pscustomobject]@{
                Path = $BuildZipPath
                Source = 'build'
            }
        }
    }

    throw "Upload ZIP not found for pack '$($Item.PackName)' Minecraft '$($Item.MinecraftVersion)'. Checked archive '$archiveZipPath' and build '$BuildZipPath'."
}

function New-VersionedUploadZipCopy {
    param([Parameter(Mandatory = $true)]$Item)

    $uploadDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath (Join-Path -Path 'resource-packs-manager-modrinth-upload' -ChildPath ([System.Guid]::NewGuid().ToString('N')))
    Ensure-Directory -Path $uploadDirectory

    $uploadPath = Join-Path -Path $uploadDirectory -ChildPath (Get-ModrinthZipFileName -Item $Item)
    Copy-Item -LiteralPath $Item.ZipPath -Destination $uploadPath
    return $uploadPath
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$configFullPath = Resolve-FullPath -BasePath $repoRoot -Path $ConfigPath
if (-not (Test-Path -LiteralPath $configFullPath)) {
    throw "Config file not found: $configFullPath"
}

$config = ConvertTo-Hashtable -InputObject (Import-PowerShellDataFile -Path $configFullPath)
$archiveRootPath = Resolve-FullPath -BasePath $repoRoot -Path $ArchiveRoot
$localModrinthStateFullPath = Resolve-FullPath -BasePath $repoRoot -Path $LocalModrinthStatePath
$localModrinthState = Read-LocalModrinthState -RepoRoot $repoRoot -StatePath $localModrinthStateFullPath
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
    throw 'No Minecraft versions are configured.'
}

$config['Versions'] = @($config.Versions | ForEach-Object { Normalize-VersionConfig -VersionConfig $_ })

if ($PromptForPack -and $Pack) {
    throw 'Use either -Pack or -PromptForPack, not both.'
}

if ($PromptForVersion -and $Version) {
    throw 'Use either -Version or -PromptForVersion, not both.'
}

if ($PromptForChangelog -and $PSBoundParameters.ContainsKey('Changelog')) {
    throw 'Use either -Changelog or -PromptForChangelog, not both.'
}

if ($PromptForReleaseVersion -and $PSBoundParameters.ContainsKey('ReleaseVersion')) {
    throw 'Use either -ReleaseVersion or -PromptForReleaseVersion, not both.'
}

if ($PromptForPack) {
    $Pack = @(Read-RequestedPackNames -RepoRoot $repoRoot -Config $config)
}

if ($PromptForVersion) {
    $Version = @(Read-RequestedVersions -Config $config)
}

if ($Version) {
    $Version = @(Expand-RequestedVersionSelection -InputValue ($Version -join ',') -Config $config)
}

$releaseVersionOverride = $null
if ($PromptForReleaseVersion) {
    Write-Host ''
    Write-Host "Enter the release version for this upload run, such as '1.0.0'."
    Write-Host "The Minecraft version is added automatically, producing values like '1.0.0-mc.26.3'."
    $releaseVersionInput = Read-Host 'Release version'
    if (-not [string]::IsNullOrWhiteSpace($releaseVersionInput)) {
        $releaseVersionOverride = $releaseVersionInput.Trim()
    }
}
elseif ($PSBoundParameters.ContainsKey('ReleaseVersion')) {
    if ([string]::IsNullOrWhiteSpace($ReleaseVersion)) {
        throw 'ReleaseVersion cannot be empty.'
    }

    $releaseVersionOverride = $ReleaseVersion.Trim()
}

$packDirectories = Get-PackDirectories -RepoRoot $repoRoot -Config $config -RequestedPackNames $Pack
$selectedVersions = @($config.Versions | Where-Object { $_.Enabled })
if ($Version) {
    $lookup = @{}
    foreach ($requested in $Version) {
        $lookup[$requested] = $true
    }

    $selectedVersions = @($selectedVersions | Where-Object { $lookup.ContainsKey($_.Id) })
    if ($selectedVersions.Count -ne $lookup.Keys.Count) {
        $foundIds = @($selectedVersions | ForEach-Object { $_.Id })
        $missing = @($lookup.Keys | Where-Object { $_ -notin $foundIds })
        throw "Unknown version id(s): $($missing -join ', ')"
    }
}

$projectOverrides = @{}
if ($PromptForProject) {
    foreach ($packDirectory in $packDirectories) {
        $packOptions = Get-PackBuildOptions -PackDirectory $packDirectory -Config $config
        $modrinth = Get-PackModrinthConfig -PackName $packDirectory.Name -PackOptions $packOptions
        if ($null -eq $modrinth) {
            continue
        }

        $savedPackState = Get-LocalModrinthPackState -State $localModrinthState -PackName $packDirectory.Name
        $savedProjectId = [string](Get-HashtableValueOrDefault -Table $savedPackState -Key 'ProjectId' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($savedProjectId)) {
            $modrinth.ProjectId = $savedProjectId
        }

        $projectOverrides[$packDirectory.Name] = Read-RequestedModrinthProjectReference -PackName $packDirectory.Name -DefaultProjectReference ([string]$modrinth.ProjectId)
    }
}

$uploadItems = New-Object System.Collections.Generic.List[object]
$buildRoot = Resolve-FullPath -BasePath $repoRoot -Path ([string]$config.BuildRoot)
$packageNameTemplate = [string]$config.PackageNameTemplate

foreach ($packDirectory in $packDirectories) {
    $packOptions = Get-PackBuildOptions -PackDirectory $packDirectory -Config $config
    $modrinth = Get-PackModrinthConfig -PackName $packDirectory.Name -PackOptions $packOptions
    if ($null -eq $modrinth) {
        Write-Host "Skipping $($packDirectory.Name): Modrinth.Enabled is false."
        continue
    }
    if ($releaseVersionOverride) {
        $modrinth.ReleaseVersion = $releaseVersionOverride
    }

    $savedPackState = Get-LocalModrinthPackState -State $localModrinthState -PackName $packDirectory.Name
    $savedProjectId = [string](Get-HashtableValueOrDefault -Table $savedPackState -Key 'ProjectId' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($savedProjectId)) {
        $modrinth.ProjectId = $savedProjectId
    }

    if ($projectOverrides.ContainsKey($packDirectory.Name)) {
        $modrinth.ProjectId = [string]$projectOverrides[$packDirectory.Name]
    }

    $packSelectedVersions = @(Get-PackSelectedVersions -PackDirectory $packDirectory -Config $config -GloballySelectedVersions $selectedVersions)
    foreach ($versionConfig in $packSelectedVersions) {
        $minecraftVersion = [string]$versionConfig.Id
        $tokens = @{
            PackName = $packDirectory.Name
            PackDisplayName = Convert-ToPackDisplayName -PackFolderName $packDirectory.Name
            VersionId = $minecraftVersion
            MinecraftVersion = $minecraftVersion
            ReleaseVersion = $modrinth.ReleaseVersion
        }

        $packageBaseName = Convert-Tokens -Value $packageNameTemplate -Tokens @{
            PackName = $packDirectory.Name
            PackDisplayName = $tokens.PackDisplayName
            VersionId = $minecraftVersion
        }
        $zipPath = Join-Path -Path (Join-Path -Path $buildRoot -ChildPath $packDirectory.Name) -ChildPath "$packageBaseName.zip"

        $versionNumber = Convert-Tokens -Value $modrinth.VersionNumberTemplate -Tokens $tokens
        $versionName = Convert-Tokens -Value $modrinth.NameTemplate -Tokens $tokens
        $changelog = Convert-Tokens -Value $modrinth.Changelog -Tokens $tokens

        $item = [pscustomobject]@{
            PackName = $packDirectory.Name
            ProjectId = $modrinth.ProjectId
            MinecraftVersion = $minecraftVersion
            ReleaseVersion = $modrinth.ReleaseVersion
            VersionNumber = $versionNumber
            VersionName = $versionName
            Changelog = $changelog
            VersionType = $modrinth.VersionType
            Status = $modrinth.Status
            Environment = $modrinth.Environment
            Featured = $modrinth.Featured
            Loaders = @($modrinth.Loaders)
            ZipPath = $zipPath
            ZipSource = ''
            Token = ''
        }

        $resolvedZip = Resolve-PublishZipPath -Item $item -BuildZipPath $zipPath -ArchiveRootPath $archiveRootPath -ConfigPath $ConfigPath -ShouldBuildIfMissing ([bool]($Build -and -not $SkipBuild))
        $item.ZipPath = [string]$resolvedZip.Path
        $item.ZipSource = [string]$resolvedZip.Source
        Assert-ValidUploadItem -Item $item
        $uploadItems.Add($item) | Out-Null
    }
}

if ($uploadItems.Count -eq 0) {
    Write-Host 'No Modrinth upload items were selected.'
    exit 0
}

if ($PromptForChangelog) {
    Write-Host ''
    Write-Host 'Enter a changelog for this upload run, or press Enter to leave it empty.'
    $Changelog = Read-Host 'Changelog'
    foreach ($item in $uploadItems) {
        $item.Changelog = $Changelog
    }
}
elseif ($PSBoundParameters.ContainsKey('Changelog')) {
    foreach ($item in $uploadItems) {
        $item.Changelog = $Changelog
    }
}

$token = ''
if (-not $PromptForToken) {
    $token = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariable, 'Process')
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariable, 'User')
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariable, 'Machine')
    }
}

foreach ($item in $uploadItems) {
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $item.Token = $token
        continue
    }

    $savedPackState = Get-LocalModrinthPackState -State $localModrinthState -PackName $item.PackName
    $savedToken = [string](Get-HashtableValueOrDefault -Table $savedPackState -Key 'Token' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($savedToken)) {
        $item.Token = $savedToken
    }
}

$missingTokenItems = @($uploadItems | Where-Object { [string]::IsNullOrWhiteSpace($_.Token) })
if ($PromptForToken -and $missingTokenItems.Count -gt 0) {
    $token = Read-PlainTextSecret -Prompt 'Enter Modrinth token'
    foreach ($item in $missingTokenItems) {
        $item.Token = $token
    }
}

if (($Publish -or $CheckRemote) -and @($uploadItems | Where-Object { [string]::IsNullOrWhiteSpace($_.Token) }).Count -gt 0) {
    throw "Publishing or remote duplicate checks require a Modrinth token from -PromptForToken, the $TokenEnvironmentVariable environment variable, or $LocalModrinthStatePath."
}

if ($Publish -and -not $Yes) {
    Write-Host ''
    Write-Host "This will create $($uploadItems.Count) Modrinth version(s) with status '$DefaultStatus' unless overridden per pack."
    Write-Host 'Type PUBLISH to continue.'
    $confirmation = Read-Host 'Confirmation'
    if ($confirmation -ne 'PUBLISH') {
        throw 'Publishing cancelled.'
    }
}

$shouldReadRemote = $Publish -or $CheckRemote
$existingVersionsByProject = @{}
$resolvedProjectIds = @{}
if ($shouldReadRemote) {
    foreach ($projectId in @($uploadItems | Select-Object -ExpandProperty ProjectId -Unique)) {
        $projectItems = @($uploadItems | Where-Object { $_.ProjectId -eq $projectId })
        $projectToken = [string]$projectItems[0].Token
        $client = New-ModrinthHttpClient -Token $projectToken
        try {
            $project = Invoke-ModrinthGetProject -Client $client -ProjectId $projectId
            $resolvedProjectIds[$projectId] = [string]$project.id

            $versionsForProject = Invoke-ModrinthGetProjectVersions -Client $client -ProjectId ([string]$project.id)
            $lookup = @{}
            foreach ($remoteVersion in @($versionsForProject)) {
                $lookup[[string]$remoteVersion.version_number] = $remoteVersion
            }
            $existingVersionsByProject[$projectId] = $lookup
        }
        finally {
            $client.Dispose()
        }
    }
}

$summary = New-Object System.Collections.Generic.List[object]

foreach ($item in $uploadItems) {
    $alreadyExists = $false
    if ($existingVersionsByProject.ContainsKey($item.ProjectId)) {
        $alreadyExists = $existingVersionsByProject[$item.ProjectId].ContainsKey($item.VersionNumber)
    }

    if ($alreadyExists) {
        Write-Host "Skipping existing $($item.PackName) $($item.MinecraftVersion): $($item.VersionNumber)"
        $summary.Add([pscustomobject]@{
            Pack = $item.PackName
            MinecraftVersion = $item.MinecraftVersion
            VersionNumber = $item.VersionNumber
            ZipSource = $item.ZipSource
            Action = 'skipped-existing'
        }) | Out-Null
        continue
    }

    if (-not $Publish) {
        Write-Host "Dry run: would publish $($item.PackName) $($item.MinecraftVersion) as $($item.VersionNumber) using $($item.ZipSource) file $(Get-ModrinthZipFileName -Item $item) -> project $($item.ProjectId)"
        $summary.Add([pscustomobject]@{
            Pack = $item.PackName
            MinecraftVersion = $item.MinecraftVersion
            VersionNumber = $item.VersionNumber
            ZipSource = $item.ZipSource
            Action = 'dry-run'
        }) | Out-Null
        continue
    }

    if ($resolvedProjectIds.ContainsKey($item.ProjectId)) {
        $item.ProjectId = [string]$resolvedProjectIds[$item.ProjectId]
    }

    Write-Host "Publishing $($item.PackName) $($item.MinecraftVersion) as $($item.VersionNumber) using $($item.ZipSource) file $(Get-ModrinthZipFileName -Item $item)..."
    $originalZipPath = $item.ZipPath
    $uploadZipPath = New-VersionedUploadZipCopy -Item $item
    $item.ZipPath = $uploadZipPath
    $client = New-ModrinthHttpClient -Token ([string]$item.Token)
    try {
        $createdVersion = Publish-ModrinthVersion -Client $client -Item $item
    }
    finally {
        $client.Dispose()
        $item.ZipPath = $originalZipPath
        if (Test-Path -LiteralPath $uploadZipPath -PathType Leaf) {
            Remove-Item -LiteralPath $uploadZipPath
        }
        $uploadDirectory = Split-Path -Path $uploadZipPath -Parent
        if (Test-Path -LiteralPath $uploadDirectory -PathType Container) {
            Remove-Item -LiteralPath $uploadDirectory -Force
        }
    }

    Save-LocalModrinthPackState -State $localModrinthState -StatePath $localModrinthStateFullPath -PackName $item.PackName -ProjectId $item.ProjectId -Token ([string]$item.Token)
    $archivePath = Move-UploadedZipToArchive -Item $item -ArchiveRootPath $archiveRootPath

    $summary.Add([pscustomobject]@{
        Pack = $item.PackName
        MinecraftVersion = $item.MinecraftVersion
        VersionNumber = $item.VersionNumber
        ZipSource = $item.ZipSource
        Action = 'published'
        ModrinthVersionId = if ($createdVersion) { $createdVersion.id } else { $null }
        ArchivePath = $archivePath
    }) | Out-Null
}

Write-Host ''
Write-Host 'Modrinth publish summary:'
$summary | Format-Table -AutoSize

if (-not $Publish) {
    Write-Host ''
    Write-Host 'No files were uploaded. Re-run with -Publish to create Modrinth versions.'
}
