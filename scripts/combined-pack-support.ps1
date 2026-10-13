# Shared discovery for builds and publishers. Definitions stay outside resource_packs.
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

function Get-CombinedArchivedComponent {
    param([string]$RepoRoot, [string]$PackName, [string]$MinecraftVersion)
    $root = Join-Path $RepoRoot "archive/$PackName"
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $latest = $null
    foreach ($folder in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
        $release = Convert-ArchivedPackRelease $folder.Name
        if ($null -eq $release) { continue }
        $pattern = '^' + [regex]::Escape("$PackName-$($folder.Name)-mc") + '\.?' + [regex]::Escape($MinecraftVersion) + '(?:-uploaded-[0-9]{14})?\.zip$'
        $zip = Get-ChildItem -LiteralPath $folder.FullName -File -Filter '*.zip' |
            Where-Object { $_.Name -match $pattern } |
            Sort-Object LastWriteTimeUtc, Name -Descending | Select-Object -First 1
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
    $creditsPath = Join-Path $DefinitionDirectory 'credits.txt'
    if (Test-Path -LiteralPath $creditsPath -PathType Leaf) {
        $credits.Add((Get-Content -LiteralPath $creditsPath -Raw -Encoding UTF8).Trim())
        $credits.Add('')
    }
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
    $hasLicenseNotices = $false
    # The repository license remains authoritative if it changes in a future release.
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Destination (Join-Path $Destination 'license.txt') -Force
    foreach ($pack in @($Components.Keys | Sort-Object)) {
        $versions[$pack] = if ($Components[$pack].ContainsKey('ReleaseVersion')) { $Components[$pack].ReleaseVersion } else { Get-LatestArchivedPackVersion -RepoRoot $RepoRoot -PackName $pack }
        $packTitle = Convert-ToPackDisplayName -PackFolderName $pack
        $readme.Add("$($packTitle): $($versions[$pack])")
        $creditNames = @($Components[$pack].Notices.Keys | Where-Object { $_ -imatch '^credits?(\.|$)' } | Sort-Object)
        if ($creditNames.Count) {
            $credits.Add("$($pack):")
            foreach ($name in $creditNames) { $credits.Add((Get-Content -LiteralPath $Components[$pack].Notices[$name] -Raw -Encoding UTF8).Trim()) }
            $credits.Add('')
        }
        foreach ($name in @($Components[$pack].Notices.Keys | Where-Object { $_ -inotmatch '^credits?(\.|$)' } | Sort-Object)) {
            $hasLicenseNotices = $true
            $folder = Join-Path $Destination "licenses/$pack"
            Ensure-Directory -Path $folder
            Copy-Item -LiteralPath $Components[$pack].Notices[$name] -Destination (Join-Path $folder $name) -Force
        }
    }
    $readme.Add('')
    $readme.Add('Credits and license')
    $readme.Add('See credits.txt for the artists and original creators whose work is included in this pack.')
    $readme.Add('See license.txt for license information.')
    if ($hasLicenseNotices) { $readme.Add('Additional license notices are included in the licenses folder.') }
    Set-Content -LiteralPath (Join-Path $Destination 'credits.txt') -Value ($credits -join [Environment]::NewLine) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Destination 'readme.txt') -Value ($readme -join [Environment]::NewLine) -Encoding UTF8
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
