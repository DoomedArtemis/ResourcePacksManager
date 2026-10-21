[CmdletBinding()]
param(
    [string]$DefinitionPath = 'artemis_enhanced_visuals/artemis_enhanced_visuals.psd1',
    [string]$ConfigPath = 'config/texture-pack.build.psd1',
    [string[]]$Version,
    [switch]$PromptForVersion,
    [switch]$ListPacks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
. (Join-Path $PSScriptRoot 'combined-pack-dependencies.ps1')
. (Join-Path $PSScriptRoot 'combined-pack-compatibility.ps1')

# Reuse the normal builder's functions without executing its build/publish entry point.
function Import-PackBuilderFunctions {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Builder has syntax errors: $Path" }
    # Export into this script's scope, not the caller's global session.
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $body = $node.Body.Extent.Text
            Set-Item -Path ("Function:script:" + $node.Name) -Value ([scriptblock]::Create($body.Substring(1, $body.Length - 2)))
        }
    }
}

function Assert-CombinedDefinition {
    param([hashtable]$Definition, [string[]]$AvailablePacks)
    foreach ($key in $Definition.Keys) {
        if ($key -notin @('Name', 'DisplayName', 'Description', 'PackMetadata', 'IconPath', 'Packs', 'Exclude', 'Modrinth', 'CurseForge', 'Versions', 'ExcludeVersions', 'MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion')) {
            throw "Unknown combined-pack option '$key'."
        }
    }
    if (-not $Definition.ContainsKey('Name') -or [string]$Definition.Name -cnotmatch '^[a-z0-9_]+$') {
        throw 'Combined pack Name must contain only lowercase letters, numbers, and underscores.'
    }
    if ($Definition.Name -in $AvailablePacks) { throw 'Combined pack Name must differ from normal pack names.' }
    if (-not $Definition.ContainsKey('DisplayName') -or -not ([string]$Definition.DisplayName).Trim()) {
        throw 'Combined pack DisplayName is required.'
    }
    if (-not $Definition.ContainsKey('Packs') -or @($Definition.Packs).Count -eq 0) {
        throw 'Combined pack Packs must list at least one pack.'
    }
    $seen = @{}
    if ($Definition.ContainsKey('PackMetadata') -and $Definition.PackMetadata -isnot [hashtable]) {
        throw 'Combined pack PackMetadata must be a table.'
    }
    $enabledCount = 0
    foreach ($entry in $Definition.Packs) {
        if ($entry -isnot [hashtable]) { throw 'Each Packs entry must be a hashtable.' }
        foreach ($key in $entry.Keys) {
            if ($key -notin @('Name', 'Enabled', 'Priority', 'Include', 'Exclude')) { throw "Unknown pack option '$key'." }
        }
        if (-not $entry.ContainsKey('Name') -or $entry.Name -notin $AvailablePacks) { throw "Unknown source pack '$($entry['Name'])'." }
        if ($seen.ContainsKey($entry.Name)) { throw "Duplicate source pack '$($entry.Name)'." }
        $seen[$entry.Name] = $true
        if (-not $entry.ContainsKey('Enabled') -or $entry.Enabled -isnot [bool]) { throw "Pack '$($entry.Name)' needs Enabled = `$true or `$false." }
        if (-not $entry.ContainsKey('Priority') -or $entry.Priority -isnot [int]) { throw "Pack '$($entry.Name)' needs an integer Priority." }
        if ($entry.Enabled) { $enabledCount++ }
        foreach ($key in @('Include', 'Exclude')) {
            if ($entry.ContainsKey($key)) {
                foreach ($rule in @($entry[$key])) {
                    if ($rule -isnot [string] -or -not $rule.Trim()) { throw "$key rules must be nonempty path strings." }
                }
            }
        }
    }
    if ($enabledCount -eq 0) { throw 'Enable at least one source pack.' }
    foreach ($rule in @($Definition['Exclude'])) {
        if ($null -ne $rule -and ($rule -isnot [string] -or -not $rule.Trim())) { throw 'Exclude rules must be nonempty path strings.' }
    }
}

function Test-CombinedRule {
    param([string]$Path, [string]$Rule)
    if ($Rule.EndsWith('/')) { return $Path.StartsWith($Rule, [StringComparison]::OrdinalIgnoreCase) }
    return $Path -like $Rule
}

function Test-CombinedPath {
    param([string]$Path, [hashtable]$Entry, [hashtable]$Definition)
    $include = @('*')
    if ($Entry.ContainsKey('Include')) { $include = @($Entry.Include) }
    $matches = $false
    foreach ($rule in $include) { if (Test-CombinedRule -Path $Path -Rule $rule) { $matches = $true; break } }
    if (-not $matches) { return $false }
    foreach ($rule in @($Entry['Exclude']) + @($Definition['Exclude'])) {
        if ($null -ne $rule -and (Test-CombinedRule -Path $Path -Rule $rule)) { return $false }
    }
    return $true
}

function Merge-CombinedArchive {
    param([string]$ZipPath, [hashtable]$Entry, [hashtable]$Definition, [string]$Destination, [hashtable]$Owners, [hashtable]$Component)
    if ($Component) {
        foreach ($path in $Component.Included.Keys) {
            if ($Owners.ContainsKey($path)) {
                if ($Owners[$path].Priority -eq $Entry.Priority) { throw "Equal priority conflict at '$path': '$($Owners[$path].Pack)' and '$($Entry.Name)'. Give one pack a higher Priority." }
                if ($Owners[$path].Priority -gt $Entry.Priority) { continue }
            }
            $target = Join-Path $Destination $path
            Ensure-Directory -Path ([IO.Path]::GetDirectoryName($target))
            Copy-Item -LiteralPath $Component.Files[$path] -Destination $target -Force
            $Owners[$path] = @{ Pack = [string]$Entry.Name; Priority = [int]$Entry.Priority }
        }
        return
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($file in $archive.Entries) {
            $path = $file.FullName.Replace('\', '/')
            # Component icons and metadata belong to the individual packs only.
            if (-not $path.StartsWith('assets/') -or $path.EndsWith('/')) { continue }
            if ($path.Split('/') -contains '..' -or $path.Contains(':')) { throw "Unsafe archive path '$path'." }
            if (-not (Test-CombinedPath -Path $path -Entry $Entry -Definition $Definition)) { continue }
            if ($Owners.ContainsKey($path)) {
                if ($Owners[$path].Priority -eq $Entry.Priority) {
                    throw "Equal priority conflict at '$path': '$($Owners[$path].Pack)' and '$($Entry.Name)'. Give one pack a higher Priority."
                }
                if ($Owners[$path].Priority -gt $Entry.Priority) { continue }
            }
            $target = Join-Path $Destination $path
            Ensure-Directory -Path ([IO.Path]::GetDirectoryName($target))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($file, $target, $true)
            $Owners[$path] = @{ Pack = [string]$Entry.Name; Priority = [int]$Entry.Priority }
        }
    }
    finally { $archive.Dispose() }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
Import-PackBuilderFunctions -Path (Join-Path $PSScriptRoot 'build-texture-packs.ps1')
$config = Import-PowerShellDataFile -Path (Resolve-FullPath -BasePath $repoRoot -Path $ConfigPath)
if ($config.ContainsKey('VersionMatrixPath') -and $config.VersionMatrixPath) {
    $matrix = Import-PowerShellDataFile -Path (Resolve-FullPath -BasePath $repoRoot -Path $config.VersionMatrixPath)
    $config['Versions'] = $matrix.Versions
}
$config['Versions'] = @($config.Versions | ForEach-Object { Normalize-VersionConfig -VersionConfig $_ })
$definition = Import-PowerShellDataFile -Path (Resolve-FullPath -BasePath $repoRoot -Path $DefinitionPath)
$directories = @(Get-PackDirectories -RepoRoot $repoRoot -Config $config | Where-Object { -not (Get-CombinedDefinitionPath -PackDirectory $_) })
Assert-CombinedDefinition -Definition $definition -AvailablePacks @($directories.Name)
if ($ListPacks) {
    foreach ($entry in $definition.Packs) {
        $state = if ($entry.Enabled) { 'included' } else { 'excluded' }
        Write-Output "$($entry.Name)`t$state`tpriority=$($entry.Priority)"
    }
    foreach ($directory in $directories) {
        if ($directory.Name -notin @($definition.Packs.Name)) { Write-Output "$($directory.Name)`texcluded (not listed)" }
    }
    return
}
if ($PromptForVersion -and $Version) { throw 'Use either -Version or -PromptForVersion.' }
if ($PromptForVersion) { $Version = @(Read-RequestedVersions -Config $config) }
$selectedVersions = @($config.Versions | Where-Object { $_.Enabled })
if ($Version) {
    $requested = @(Expand-RequestedVersionSelection -InputValue ($Version -join ',') -Config $config)
    $selectedVersions = @($selectedVersions | Where-Object { $_.Id -in $requested })
}
if ($selectedVersions.Count -eq 0) { throw 'No enabled Minecraft versions selected.' }
$order = Get-VersionOrderLookup -Config $config
$selectedVersions = @($selectedVersions | Where-Object { Test-VersionSelectorMatch -Options $definition -VersionConfig $_ -VersionOrder $order -ContextDescription $DefinitionPath })
if ($selectedVersions.Count -eq 0) { throw 'No Minecraft versions selected within the combined pack version filters.' }
$outputRoot = Join-Path (Resolve-FullPath -BasePath $repoRoot -Path $config.BuildRoot) $definition.Name
Ensure-Directory -Path $outputRoot
$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('artemis-combined-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
Ensure-Directory -Path $workRoot
# Component builds use unique temporary ZIPs/staging, leaving normal outputs untouched.
$componentConfig = @{} + $config
$componentConfig.BuildRoot = Join-Path $workRoot 'components'
function Get-TemporaryBuildRoot { return Join-Path $workRoot 'staging' }
try {
    $versionIndex = 0
    $enabledEntries = @($definition.Packs | Where-Object { $_.Enabled } | Sort-Object Priority, Name)
    $componentOptions = @{}
    foreach ($versionConfig in $selectedVersions) {
        $combinedActivity = "$($definition.DisplayName) / Minecraft $($versionConfig.Id)"
        Show-BuildProgress -Id 1 -Activity $definition.DisplayName -Stage "Minecraft $($versionConfig.Id)" -Completed $versionIndex -Total $selectedVersions.Count
        $componentIndex = 0
        $owners = @{}
        $components = @{}
        $componentSources = @{}
        $included = @()
        $skipped = @()
        $mergedRoot = Join-Path $workRoot ('m/' + $versionConfig.Id)
        Ensure-Directory -Path $mergedRoot
        foreach ($entry in $enabledEntries) {
            Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage "Finding archived component: $($entry.Name)" -Completed $componentIndex -Total $enabledEntries.Count
            $componentIndex++
            $directory = $directories | Where-Object { $_.Name -eq $entry.Name } | Select-Object -First 1
            if (-not $componentOptions.ContainsKey($entry.Name)) {
                $componentOptions[$entry.Name] = Get-PackBuildOptions -PackDirectory $directory -Config $config
            }
            $supported = @(Get-PackSelectedVersions -PackDirectory $directory -Config $config -GloballySelectedVersions @($versionConfig) -PackOptions $componentOptions[$entry.Name])
            if ($supported.Count -eq 0) {
                $skipped += $entry.Name
                Write-Output "Skipping $($entry.Name) for $($versionConfig.Id): outside its supported versions."
                continue
            }
            $archived = Get-CombinedArchivedComponent -RepoRoot $repoRoot -PackName $entry.Name -MinecraftVersion $versionConfig.Id
            if ($archived) {
                $componentZipPath = $archived.ZipPath
                Write-Host "Using archived $($entry.Name) $($archived.ReleaseVersion) for Minecraft $($versionConfig.Id)."
                $componentSources[$entry.Name] = @{ Source = 'archive'; ReleaseVersion = $archived.ReleaseVersion; ZipPath = $componentZipPath }
            }
            else {
                Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage "Building component without matching archive: $($entry.Name)" -Completed ($componentIndex - 1) -Total $enabledEntries.Count
                $result = Build-PackVersion -RepoRoot $repoRoot -Config $componentConfig -PackDirectory $directory -VersionConfig $versionConfig -PackOptions $componentOptions[$entry.Name]
                $componentZipPath = $result.ZipPath
                $componentSources[$entry.Name] = @{ Source = 'source'; ReleaseVersion = 'unreleased' }
            }
            Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage "Merging component: $($entry.Name)" -Completed $componentIndex -Total $enabledEntries.Count
            $components[$entry.Name] = Read-CombinedComponent -ZipPath $componentZipPath -Entry $entry -Definition $definition -Root (Join-Path $workRoot "dependency-inputs/$($versionConfig.Id)/$($entry.Name)") -Validation $config.Validation -VersionConfig $versionConfig
            $components[$entry.Name].ReleaseVersion = $componentSources[$entry.Name].ReleaseVersion
            Merge-CombinedArchive -ZipPath $componentZipPath -Entry $entry -Definition $definition -Destination $mergedRoot -Owners $owners -Component $components[$entry.Name]
            $included += $entry.Name
        }
        $definitionDirectory = Split-Path (Resolve-FullPath -BasePath $repoRoot -Path $DefinitionPath) -Parent
        Merge-CombinedCompatibilityAssets -Components $components -Destination $mergedRoot -Owners $owners -DefinitionDirectory $definitionDirectory -Definition $definition
        if ($owners.Count -eq 0) { throw "No assets included for Minecraft $($versionConfig.Id)." }
        Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage 'Loading vanilla dependency definitions'
        $vanilla = Get-CombinedVanillaDependencies -RepoRoot $repoRoot -Config $config -VersionConfig $versionConfig
        Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage 'Checking models, textures and blockstates'
        $dependencyReport = Complete-CombinedDependencies -Name $definition.Name -Components $components -Vanilla $vanilla -Destination $mergedRoot -Owners $owners
        Close-BuildProgress -Id 5 -Activity 'Checking dependencies'
        Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage 'Writing metadata, credits and README'
        $tokens = @{ PackName = $definition.Name; PackDisplayName = $definition.DisplayName; VersionId = $versionConfig.Id; BaseDescription = '{PackDisplayName} for Minecraft {VersionId}' }
        if ($definition.ContainsKey('Description')) { $tokens.BaseDescription = $definition.Description }
        $metadata = New-PackMcmetaObject -Tokens $tokens -VersionConfig $versionConfig
        $metadata.pack.description = Convert-Tokens -Value $tokens.BaseDescription -Tokens $tokens
        $documentationDescription = [string]$metadata.pack.description
        if ($definition.ContainsKey('PackMetadata')) {
            $overrides = ConvertTo-Hashtable -InputObject $definition.PackMetadata
            foreach ($formatKey in @('pack_format', 'supported_formats', 'min_format', 'max_format')) { $overrides.Remove($formatKey) }
            $metadata = Merge-Hashtable -Base (ConvertTo-Hashtable -InputObject $metadata) -Overlay @{ pack = $overrides }
        }
        $metadata | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $mergedRoot 'pack.mcmeta') -Encoding UTF8
        if ($definition.ContainsKey('IconPath') -and $definition.IconPath) {
            $icon = Resolve-FullPath -BasePath $repoRoot -Path $definition.IconPath
            Copy-Item -LiteralPath $icon -Destination (Join-Path $mergedRoot 'pack.png')
        }
        $definitionDirectory = Split-Path (Resolve-FullPath -BasePath $repoRoot -Path $DefinitionPath) -Parent
        $componentVersions = Copy-CombinedPackDocumentation -RepoRoot $repoRoot -DefinitionDirectory $definitionDirectory -Destination $mergedRoot -Components $components -DisplayName $definition.DisplayName -MinecraftVersion $versionConfig.Id -Description $documentationDescription
        $packageTokens = Get-PackTokens -Config $config -PackDirectory ([pscustomobject]@{ Name = $definition.Name }) -VersionConfig $versionConfig
        $baseName = Convert-Tokens -Value $config.PackageNameTemplate -Tokens $packageTokens
        $stagedZip = Join-Path $workRoot "$baseName.zip"
        Show-BuildProgress -Id 4 -Activity $combinedActivity -Stage 'Packaging ZIP and build report'
        New-ZipFromDirectory -SourceDirectory $mergedRoot -DestinationPath $stagedZip
        $report = @{ Name = $definition.Name; Version = $versionConfig.Id; IncludedPacks = $included; ComponentVersions = $componentVersions; ComponentSources = $componentSources; UnsupportedPacks = $skipped; Files = $owners; Dependencies = $dependencyReport }
        $reportPath = Get-CombinedBuildReportPath -ZipPath (Join-Path $outputRoot "$baseName.zip")
        Ensure-Directory -Path (Split-Path $reportPath -Parent)
        $report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        Move-Item -LiteralPath $stagedZip -Destination (Join-Path $outputRoot "$baseName.zip") -Force
        Write-Output "Built $($definition.DisplayName) $($versionConfig.Id) -> $(Join-Path $outputRoot "$baseName.zip")"
        $versionIndex++
        Show-BuildProgress -Id 1 -Activity $definition.DisplayName -Stage 'Versions completed' -Completed $versionIndex -Total $selectedVersions.Count
    }
}
finally {
    foreach ($progressId in @(1, 4, 5)) { Close-BuildProgress -Id $progressId -Activity 'Building combined pack' }
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolvedWorkRoot = [IO.Path]::GetFullPath($workRoot)
    if (-not $resolvedWorkRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedWorkRoot -Leaf) -notlike 'artemis-combined-*') {
        throw 'Refusing to remove work files outside the combined build temporary directory.'
    }
    Remove-Item -LiteralPath $resolvedWorkRoot -Recurse -Force
}
