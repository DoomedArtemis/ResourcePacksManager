[CmdletBinding()]
param(
    [string]$ConfigPath = 'config/texture-pack.build.psd1',
    [string]$Pack,
    [string]$Version,
    [ValidateSet('vanilla', 'fabric', 'neoforge', 'forge')][string]$Loader,
    [Alias('Profile')][string]$ModrinthProfile,
    [string]$ModrinthAppData = (Join-Path $env:APPDATA 'ModrinthApp'),
    [string]$NodePath,
    [ValidateRange(1, 3600)][int]$ProfileInstallTimeoutSeconds = 600,
    [switch]$Rebuild,
    [switch]$SkipShaders,
    [switch]$NoLaunch,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
. (Join-Path $PSScriptRoot 'minecraft-test-loaders.ps1')
. (Join-Path $PSScriptRoot 'minecraft-test-shaders.ps1')
. (Join-Path $PSScriptRoot 'minecraft-test-pack-dependencies.ps1')

# Share the builder's discovery, compatibility filters and package naming.
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Build script has syntax errors.' }
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
}

function Read-MinecraftTestChoice {
    param([string]$Prompt, [object[]]$Choices, [string[]]$Labels)
    if (-not $Choices.Count) { throw "No choices available for $Prompt." }
    for ($index = 0; $index -lt $Choices.Count; $index++) { Write-Host "  $($index + 1). $($Labels[$index])" }
    $answer = (Read-Host $Prompt).Trim()
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Choices.Count) { return $Choices[$number - 1] }
    $matchesByName = @(for ($index = 0; $index -lt $Choices.Count; $index++) { if ($Labels[$index] -eq $answer) { $Choices[$index] } })
    if ($matchesByName.Count -eq 1) { return $matchesByName[0] }
    throw "Select one of the listed numbers for $Prompt."
}

function Resolve-MinecraftTestNode {
    param([string]$RequestedPath)
    $candidates = New-Object 'Collections.Generic.List[string]'
    if ($RequestedPath) { $candidates.Add($RequestedPath) }
    else {
        foreach ($command in @(Get-Command node -CommandType Application -All -ErrorAction SilentlyContinue)) { $candidates.Add($command.Source) }
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA/Programs")) {
            if ($root) { $candidates.Add((Join-Path $root 'nodejs/node.exe')) }
        }
        if ($env:NVM_SYMLINK) { $candidates.Add((Join-Path $env:NVM_SYMLINK 'node.exe')) }
        # IntelliJ's agent runtime is not necessarily on the IDE terminal's PATH.
        $jetbrainsRoot = Join-Path $env:LOCALAPPDATA 'JetBrains'
        foreach ($ide in @(Get-ChildItem -LiteralPath $jetbrainsRoot -Directory -ErrorAction SilentlyContinue)) {
            $runtimeRoot = Join-Path $ide.FullName 'acp-agents/.runtimes/node'
            foreach ($runtime in @(Get-ChildItem -LiteralPath $runtimeRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                $candidates.Add((Join-Path $runtime.FullName 'node.exe'))
            }
        }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        & $candidate --no-warnings -e "try { require('node:sqlite'); } catch { process.exit(1); }" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'No Node.js runtime with node:sqlite support was found. Install Node.js 22.13 or newer, or pass -NodePath with the full path to node.exe. Standard installations and IntelliJ bundled runtimes are detected automatically.'
}

function Get-ModrinthTestProfiles {
    param([string]$AppDataRoot)
    $nodeExecutable = Resolve-MinecraftTestNode -RequestedPath $NodePath
    $json = & $nodeExecutable --no-warnings (Join-Path $PSScriptRoot 'modrinth-test-profiles.cjs') $AppDataRoot
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Modrinth profiles. Use a current Modrinth App and Node.js 22.13 or newer, or specify -ModrinthAppData.' }
    foreach ($profileEntry in ($json | ConvertFrom-Json)) { Write-Output $profileEntry }
}

function Get-MinecraftTestZip {
    param([string]$ExpectedPath, [string]$VersionId)
    $directory = Split-Path $ExpectedPath -Parent
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }
    $candidates = @(Get-ChildItem -LiteralPath $directory -File -Filter '*.zip' | Where-Object {
        $_.FullName -eq $ExpectedPath -or $VersionId -in @(Get-PackZipVersions $_.FullName)
    } | Sort-Object LastWriteTimeUtc, Name -Descending)
    if ($candidates.Count) { return $candidates[0].FullName }
    return $null
}

function Add-MinecraftTestProfileToLoaderGroup {
    param([string]$AppDataRoot, [string]$InstanceId, $LoaderInfo)
    $nodeExecutable = Resolve-MinecraftTestNode -RequestedPath $NodePath
    & $nodeExecutable --no-warnings (Join-Path $PSScriptRoot 'modrinth-test-profiles.cjs') $AppDataRoot --group-loader $InstanceId $LoaderInfo.Id | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cannot add the test profile to the $($LoaderInfo.Group) group." }
    Write-Host "Test profile added to the $($LoaderInfo.Group) group."
}

function New-MinecraftTestProfileImport {
    param([string]$Destination, [string]$Name, [string]$VersionId, $LoaderInfo)
    # A content-free mrpack lets Modrinth install Minecraft and its Java runtime.
    # No unverified mod files or launcher database writes are needed.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Ensure-Directory (Split-Path $Destination -Parent)
    $index = @{ formatVersion = 1; game = 'minecraft'; versionId = 'rpm-test-profile-v1'; name = $Name;
        summary = 'Minecraft test profile created by Resource Packs Manager'; files = @(); dependencies = @{ minecraft = $VersionId } }
    if ($LoaderInfo.Id -ne 'vanilla') { $index.dependencies[$LoaderInfo.Dependency] = $LoaderInfo.LoaderVersion }
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination }
    $archive = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $writer = [IO.StreamWriter]::new($archive.CreateEntry('modrinth.index.json').Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write((ConvertTo-Json -InputObject $index -Depth 10)) } finally { $writer.Dispose() }
    }
    finally { $archive.Dispose() }
    return $Destination
}

function Start-MinecraftTestProfileImport {
    param([string]$ImportPath)
    $registration = Get-ItemProperty -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\Classes\modrinth\shell\open\command' -ErrorAction SilentlyContinue
    $executable = Join-Path $env:LOCALAPPDATA 'Modrinth App/Modrinth App.exe'
    if ($registration -and $registration.'(default)' -match '^"([^"]+)"') { $executable = $Matches[1] }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Cannot locate Modrinth App to create the test profile. Install or repair the app first.' }
    Start-Process -FilePath $executable -ArgumentList ('"' + $ImportPath + '"')
}

function Wait-MinecraftTestProfile {
    param([string]$AppDataRoot, [string]$Name, [string]$VersionId, [int]$TimeoutSeconds,
        [string]$InstanceId, [string[]]$ExcludedInstanceIds = @(), [string]$LoaderId = 'vanilla')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastProgress = -30
    do {
        $found = @(Get-ModrinthTestProfiles -AppDataRoot $AppDataRoot | Where-Object {
            $_.name -eq $Name -and $_.minecraftVersion -eq $VersionId -and $_.loader -eq $LoaderId -and
            (-not $InstanceId -or $_.id -eq $InstanceId) -and $_.id -notin $ExcludedInstanceIds
        })
        if ($found.Count -gt 1) { throw "Multiple profiles named '$Name' were found. Select the intended profile explicitly on the next run." }
        if ($found.Count -eq 1 -and $found[0].installStage -eq 'installed') { return $found[0] }
        if ($timer.Elapsed.TotalSeconds - $lastProgress -ge 15) {
            Write-Host "Waiting for Modrinth to install '$Name' (Minecraft $VersionId)..."
            $lastProgress = $timer.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Modrinth did not finish installing '$Name' within $TimeoutSeconds seconds. Check the app for download errors or prompts, then retry; existing profiles are reused."
}

function Assert-MinecraftTestProfileStopped {
    param([string]$Directory)
    # Minecraft writes options.txt when it exits; do not race a running game.
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.IndexOf($Directory, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($running.Count) { throw "Close Minecraft for this profile before installing a test pack: $Directory" }
}

function Install-MinecraftTestPack {
    param([string]$ZipPath, [string]$ProfileDirectory, [string]$PackName)
    if ($PackName -notmatch '^[a-z0-9_-]+$') { throw 'Invalid test pack name.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try { if ($null -eq $zip.GetEntry('pack.mcmeta')) { throw 'Test ZIP is missing root pack.mcmeta.' } }
    finally { $zip.Dispose() }
    $fileName = "rpm-test-$PackName.zip"
    $packId = "file/$fileName"
    $optionsPath = Join-Path $ProfileDirectory 'options.txt'
    $lines = if (Test-Path -LiteralPath $optionsPath) { @([IO.File]::ReadAllLines($optionsPath)) } else { @() }
    $resourceLines = @($lines | Where-Object { $_.StartsWith('resourcePacks:') })
    if ($resourceLines.Count -gt 1) { throw "Duplicate resourcePacks entries in $optionsPath" }
    $enabled = @()
    if ($resourceLines.Count) {
        $raw = $resourceLines[0].Substring('resourcePacks:'.Length)
        if (-not $raw.Trim().StartsWith('[')) { throw "Invalid resourcePacks list in $optionsPath" }
        $parsed = ConvertFrom-Json -InputObject $raw
        $enabled = @(foreach ($entry in $parsed) { $entry })
    }
    $enabled = @($enabled | Where-Object { $_ -cne $packId }) + @($packId)
    $replacement = 'resourcePacks:' + (ConvertTo-Json -InputObject $enabled -Compress)
    $updated = @(foreach ($line in $lines) { if ($line.StartsWith('resourcePacks:')) { $replacement } else { $line } })
    if (-not $resourceLines.Count) { $updated += $replacement }
    # Minecraft stores FOV as (degrees - 70) / 40, so 95 degrees is 0.625.
    $updated = @($updated | Where-Object { $_ -notmatch '^(soundCategory_music|fov|guiScale|narrator|onboardAccessibility):' }) + @(
        'soundCategory_music:0.0'
        'fov:0.625'
        'guiScale:4'
        'narrator:0'
        'onboardAccessibility:false'
    )
    $resourcepacks = Join-Path $ProfileDirectory 'resourcepacks'
    Ensure-Directory $resourcepacks
    $destination = Join-Path $resourcepacks $fileName
    Copy-Item -LiteralPath $ZipPath -Destination $destination -Force
    # Retain a recoverable copy of the profile's options before changing selection.
    if (Test-Path -LiteralPath $optionsPath) { Copy-Item -LiteralPath $optionsPath -Destination "$optionsPath.rpm-test.bak" -Force }
    [IO.File]::WriteAllLines($optionsPath, [string[]]$updated, [Text.UTF8Encoding]::new($false))
    return $destination
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$config = Import-PowerShellDataFile (Resolve-FullPath -BasePath $repoRoot -Path $ConfigPath)
if ($config.ContainsKey('VersionMatrixPath') -and $config.VersionMatrixPath) {
    $config.Versions = (Import-PowerShellDataFile (Resolve-FullPath -BasePath $repoRoot -Path $config.VersionMatrixPath)).Versions
}
$config.Versions = @($config.Versions | ForEach-Object { Normalize-VersionConfig $_ })
$directories = @(Get-PackDirectories -RepoRoot $repoRoot -Config $config)
if ($Pack) {
    $directory = @($directories | Where-Object { $_.Name -eq $Pack })
    if ($directory.Count -ne 1) { throw "Unknown pack: $Pack" }
    $directory = $directory[0]
} else {
    $directory = Read-MinecraftTestChoice -Prompt 'Pack to test' -Choices $directories -Labels @($directories | ForEach-Object { $_.Name })
    $Pack = $directory.Name
}
$options = Get-PackBuildOptions -PackDirectory $directory -Config $config
$supported = @(Get-PackSelectedVersions -PackDirectory $directory -Config $config -GloballySelectedVersions @($config.Versions | Where-Object { $_.Enabled }) -PackOptions $options)
$profiles = @(Get-ModrinthTestProfiles -AppDataRoot $ModrinthAppData)
if (-not $Version) {
    $available = @($supported)
    if (-not $available.Count) { throw "Pack '$Pack' has no enabled supported Minecraft versions." }
    $entry = Read-MinecraftTestChoice -Prompt 'Minecraft version' -Choices $available -Labels @($available | ForEach-Object { $_.Id })
    $Version = $entry.Id
}
if ($Version -notin @($supported | ForEach-Object { $_.Id })) { throw "Pack '$Pack' does not support enabled Minecraft version '$Version'." }
$availableLoaders = @(Get-MinecraftTestLoaders -VersionId $Version -RequestedLoader $Loader)
if (-not $availableLoaders.Count) { throw "Loader '$Loader' is not available for Minecraft $Version." }
$loaderChoice = if ($Loader) { $availableLoaders[0] } else {
    Read-MinecraftTestChoice -Prompt 'Minecraft loader' -Choices $availableLoaders -Labels @($availableLoaders | ForEach-Object { $_.Group })
}
$Loader = $loaderChoice.Id
if (-not $DryRun) {
    $nodeExecutable = Resolve-MinecraftTestNode -RequestedPath $NodePath
    & $nodeExecutable --no-warnings (Join-Path $PSScriptRoot 'modrinth-test-profiles.cjs') $ModrinthAppData --ensure-loader-groups | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare the four Modrinth loader groups.' }
    $profiles = @(Get-ModrinthTestProfiles -AppDataRoot $ModrinthAppData)
}
$matchingProfiles = @($profiles | Where-Object { $_.minecraftVersion -eq $Version -and $_.loader -eq $Loader -and $loaderChoice.Group -in @($_.groups) })
if ($ModrinthProfile) {
    $namedProfiles = @($profiles | Where-Object { $_.id -eq $ModrinthProfile -or $_.name -eq $ModrinthProfile -or (Split-Path $_.profileDirectory -Leaf) -eq $ModrinthProfile })
    if ($namedProfiles.Count -and -not @($namedProfiles | Where-Object { $loaderChoice.Group -in @($_.groups) }).Count) { throw "Profile '$ModrinthProfile' is outside the $($loaderChoice.Group) group and cannot be used for testing." }
    if ($namedProfiles.Count -and -not @($namedProfiles | Where-Object { $_.loader -eq $Loader }).Count) { throw "Profile '$ModrinthProfile' does not use $($loaderChoice.Group)." }
    if ($namedProfiles.Count -and -not @($namedProfiles | Where-Object { $_.minecraftVersion -eq $Version }).Count) { throw "Profile '$ModrinthProfile' uses a different Minecraft version than '$Version'." }
    $matchingProfiles = @($matchingProfiles | Where-Object { $_.id -eq $ModrinthProfile -or $_.name -eq $ModrinthProfile -or (Split-Path $_.profileDirectory -Leaf) -eq $ModrinthProfile })
}
$needsProfile = $matchingProfiles.Count -eq 0
$defaultName = if ($Loader -eq 'vanilla') { "Resource Pack Test $Version" } else { "Resource Pack Test $($loaderChoice.Group) $Version" }
$newProfileName = if ($ModrinthProfile) { $ModrinthProfile } else { $defaultName }
if ($needsProfile -and -not $ModrinthProfile) {
    $suffix = 2
    while ($newProfileName -in @($profiles | ForEach-Object { $_.name })) {
        $newProfileName = "$defaultName ($suffix)"
        $suffix++
    }
}
if ($needsProfile -and ($newProfileName -match '[<>:"/\\|?*\x00-\x1f]' -or $newProfileName -match '[. ]$')) { throw 'Specify a valid profile name when creating a missing profile.' }
$selectedProfile = if ($needsProfile) { $null } elseif ($matchingProfiles.Count -eq 1) { $matchingProfiles[0] } else {
    Read-MinecraftTestChoice -Prompt 'Modrinth profile' -Choices $matchingProfiles -Labels @($matchingProfiles | ForEach-Object { "$($_.name) [$($_.loader)] - $(Split-Path $_.profileDirectory -Leaf)" })
}
$displayName = Get-ReleasePackDisplayName -PackDirectory $directory -PackOptions $options
$baseName = Convert-Tokens -Value $config.PackageNameTemplate -Tokens @{ PackName = $Pack; PackDisplayName = $displayName; VersionId = $Version }
$expectedPath = Join-Path (Resolve-FullPath -BasePath $repoRoot -Path $config.BuildRoot) "$Pack/$baseName.zip"
$zipPath = Get-MinecraftTestZip -ExpectedPath $expectedPath -VersionId $Version
# Modrinth's supported deep link uses the stable instance ID, not its display name.
# https://github.com/modrinth/code/blob/main/packages/app-lib/src/api/handler.rs
if ($DryRun) {
    Write-Output 'Would ensure exactly one Vanilla, Fabric, NeoForge, and Forge loader group.'
    Write-Output 'Would set test-profile music and narrator off, skip accessibility onboarding, set FOV 95, and GUI scale 4.'
    Initialize-MinecraftTestEnvironment -PackOptions $options -Config $config -PackName $Pack -MinecraftVersion $Version -LoaderId $Loader -SkipShaders:$SkipShaders -DryRun
    if ($Rebuild -or -not $zipPath) { Write-Output "Would build $Pack for $Version." } else { Write-Output "Would use build: $zipPath" }
    if ($needsProfile) {
        Write-Output "Would create $Loader Modrinth profile '$newProfileName' for Minecraft $Version and wait for installation."
        Write-Output "Would add the new profile to the $($loaderChoice.Group) group."
        Write-Output "Would install and enable rpm-test-$Pack.zip in the new profile."
        if (-not $NoLaunch) { Write-Output 'Would launch the newly installed profile.' }
    } else {
        Write-Output "Would install and enable rpm-test-$Pack.zip in $($selectedProfile.profileDirectory)"
        if (-not $NoLaunch) { Write-Output ('Would launch: modrinth://launch/instance/' + [Uri]::EscapeDataString($selectedProfile.id)) }
    }
    return
}
if ($selectedProfile) { Assert-MinecraftTestProfileStopped -Directory $selectedProfile.profileDirectory }
if ($Rebuild -or -not $zipPath) {
    & (Join-Path $PSScriptRoot 'build-texture-packs.ps1') -ConfigPath $ConfigPath -Pack $Pack -Version $Version | Out-Host
    if (-not $?) { throw 'Test pack build failed.' }
    $zipPath = Get-MinecraftTestZip -ExpectedPath $expectedPath -VersionId $Version
}
if (-not $zipPath) { throw "No build ZIP found for '$Pack' / '$Version' after building." }
if ($needsProfile) {
    $importFileName = if ($Loader -eq 'vanilla') { "minecraft-$Version.mrpack" } else { "minecraft-$Version-$Loader.mrpack" }
    $importPath = Join-Path (Resolve-FullPath -BasePath $repoRoot -Path $config.BuildRoot) "test-profiles/$importFileName"
    $null = New-MinecraftTestProfileImport -Destination $importPath -Name $newProfileName -VersionId $Version -LoaderInfo $loaderChoice
    Write-Host "Creating $Loader Modrinth profile '$newProfileName' for Minecraft $Version..."
    Start-MinecraftTestProfileImport -ImportPath $importPath
    $selectedProfile = Wait-MinecraftTestProfile -AppDataRoot $ModrinthAppData -Name $newProfileName -VersionId $Version -TimeoutSeconds $ProfileInstallTimeoutSeconds -ExcludedInstanceIds @($profiles | ForEach-Object { $_.id }) -LoaderId $Loader
} elseif ($selectedProfile.installStage -ne 'installed') {
    $selectedProfile = Wait-MinecraftTestProfile -AppDataRoot $ModrinthAppData -Name $selectedProfile.name -VersionId $Version -TimeoutSeconds $ProfileInstallTimeoutSeconds -InstanceId $selectedProfile.id -LoaderId $Loader
}
$launchUri = 'modrinth://launch/instance/' + [Uri]::EscapeDataString($selectedProfile.id)
if ($needsProfile) {
    Add-MinecraftTestProfileToLoaderGroup -AppDataRoot $ModrinthAppData -InstanceId $selectedProfile.id -LoaderInfo $loaderChoice
}
$allowedProfile = @(Get-ModrinthTestProfiles -AppDataRoot $ModrinthAppData | Where-Object { $_.id -eq $selectedProfile.id -and $_.minecraftVersion -eq $Version -and $_.loader -eq $Loader -and $loaderChoice.Group -in @($_.groups) })
if ($allowedProfile.Count -ne 1) { throw "The selected profile does not match Minecraft $Version, loader $Loader, and group $($loaderChoice.Group). No test pack will be installed or launched." }
Write-Host "Testing $Pack / Minecraft $Version in $($selectedProfile.name) [$($selectedProfile.loader)]"
Assert-MinecraftTestProfileStopped -Directory $selectedProfile.profileDirectory
$installed = Install-MinecraftTestPack -ZipPath $zipPath -ProfileDirectory $selectedProfile.profileDirectory -PackName $Pack
Write-Output "Installed and enabled: $installed (from $zipPath)"
Initialize-MinecraftTestEnvironment -ProfileDirectory $selectedProfile.profileDirectory -PackOptions $options -Config $config -PackName $Pack -MinecraftVersion $Version -LoaderId $Loader -SkipShaders:$SkipShaders
if (-not $NoLaunch) { Start-Process -FilePath $launchUri }
