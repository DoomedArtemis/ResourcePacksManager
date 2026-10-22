[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'minecraft-test-shaders.ps1')
function Ensure-Directory { param($Path) if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('rpm-shader-test-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory $fixture
$script:downloadSources = @{}; $script:downloadCount = 0; $script:corruptDownloads = $false
$script:knownInstalled = [pscustomobject]@{}
$script:versions = @{}
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $irisSource = Join-Path $fixture 'iris.jar'
    $jar = [IO.Compression.ZipFile]::Open($irisSource, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $writer = [IO.StreamWriter]::new($jar.CreateEntry('fabric.mod.json').Open())
        try { $writer.Write('{"id":"iris","version":"1.8.8","depends":{"sodium":["0.6.x"]}}') } finally { $writer.Dispose() }
    } finally { $jar.Dispose() }
    function New-FixtureVersion {
        param($Id, $Project, $Number, $FileName, $Source = '', $Loaders = @('fabric','neoforge','forge'), $Dependencies = @())
        if (-not $Source) { $Source = Join-Path $fixture "$Id.bin"; [IO.File]::WriteAllText($Source, "contents-$Id") }
        $url = "https://example.invalid/$FileName"
        $script:downloadSources[$url] = $Source
        $data = @{ id = $Id; project_id = $Project; name = $Id; version_number = $Number; version_type = 'release'; date_published = '2026-01-01T00:00:00Z'; game_versions = @('1.21.1'); loaders = $Loaders;
            dependencies = @($Dependencies); files = @(@{ primary = $true; filename = $FileName; url = $url; hashes = @{ sha512 = (Get-FileHash -LiteralPath $Source -Algorithm SHA512).Hash } }) }
        $version = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $data -Depth 12)
        $script:versions[$Id] = $version
        return $version
    }
    function Required { param($Project, $VersionId = $null) return @{ dependency_type = 'required'; project_id = $Project; version_id = $VersionId; file_name = $null } }
    $iris = New-FixtureVersion iris1 YL57xq9U 1.8.8 iris.jar -Source $irisSource -Dependencies @((Required AANobbMI))
    $sodiumNew = New-FixtureVersion sodium-new AANobbMI mc1.21.1-0.8.0 sodium-new.jar
    $sodium = New-FixtureVersion sodium1 AANobbMI mc1.21.1-0.6.13 sodium.jar -Dependencies @((Required fabric-api api1))
    $api = New-FixtureVersion api1 fabric-api 1.0.0 fabric-api.jar -Dependencies @((Required library library1), @{ dependency_type = 'optional'; project_id = 'optional'; version_id = $null; file_name = $null })
    $library = New-FixtureVersion library1 library 1.0.0 library.jar -Dependencies @((Required AANobbMI sodium1))
    $oculus = New-FixtureVersion oculus1 oculus-project 1.8.0 oculus.jar -Loaders @('forge') -Dependencies @((Required embeddium-project))
    $embeddium = New-FixtureVersion embeddium1 embeddium-project 0.3.31 embeddium.jar
    $shader = New-FixtureVersion shader1 complementary-project r5.9.0 complementary.zip -Loaders @('iris')
    $script:projectVersions = @{ iris = @($iris); sodium = @($sodiumNew, $sodium); AANobbMI = @($sodiumNew, $sodium); oculus = @($oculus); 'embeddium-project' = @($embeddium); 'complementary-reimagined' = @($shader) }
    function Invoke-ShaderModrinthApi {
        param($Path, $Body)
        if ($Path -eq 'version_files') { return $script:knownInstalled }
        if ($Path -match '^project/([^/]+)/version\?') { return $script:projectVersions[[Uri]::UnescapeDataString($Matches[1])] }
        if ($Path -match '^version/(.+)$') { return $script:versions[[Uri]::UnescapeDataString($Matches[1])] }
        throw "Unexpected fixture API call: $Path"
    }
    function Save-MinecraftShaderDownload {
        param($Url, $Destination)
        $script:downloadCount++
        if ($script:corruptDownloads) { [IO.File]::WriteAllText($Destination, 'corrupt') } else { Copy-Item -LiteralPath $script:downloadSources[$Url] -Destination $Destination }
    }
    if ((Get-MinecraftTestShaderPlan -MinecraftVersion 1.21.1 -LoaderId vanilla).Supported) { throw 'Vanilla was treated as shader capable.' }
    if ((Get-MinecraftTestShaderPlan -MinecraftVersion 1.13 -LoaderId fabric).Supported) { throw 'An unsupported game version got shader mods.' }
    foreach ($value in @('0.6.0','0.6.13')) { if (-not (Test-ShaderVersionConstraint $value @('0.6.x'))) { throw 'Sodium wildcard range rejected a matching version.' } }
    if ((Test-ShaderVersionConstraint '0.8.0' @('0.6.x')) -or -not (Test-ShaderVersionConstraint '0.6.13' @('[0.6.0,0.7)'))) { throw 'Sodium version bounds failed.' }
    $plan = Get-MinecraftTestShaderPlan -MinecraftVersion 1.21.1 -LoaderId fabric
    if (-not $plan.Supported -or @($plan.Mods).Count -ne 4 -or 'sodium1' -cnotin @($plan.Mods.id) -or 'sodium-new' -cin @($plan.Mods.id)) { throw 'Recursive dependencies or Sodium manifest constraints were lost.' }
    $profile = Join-Path $fixture 'profile'
    Ensure-Directory "$profile/config"
    [IO.File]::WriteAllText("$profile/config/iris.properties", "otherSetting=unchanged`nshaderPack=old.zip`nenableShaders=false`n")
    Install-MinecraftTestShaders -ProfileDirectory $profile -Plan $plan -LoaderId fabric
    if (@(Get-ChildItem "$profile/mods" -Filter '*.jar').Count -ne 4 -or -not (Test-Path "$profile/shaderpacks/complementary.zip")) { throw 'Shader or transitive dependencies were not installed.' }
    $configuration = [IO.File]::ReadAllText("$profile/config/iris.properties")
    if ($configuration -notmatch 'otherSetting=unchanged' -or $configuration -notmatch 'shaderPack=complementary.zip' -or $configuration -notmatch 'enableShaders=true') { throw 'Shader selection or existing configuration was lost.' }
    $downloads = $script:downloadCount
    Install-MinecraftTestShaders -ProfileDirectory $profile -Plan $plan -LoaderId fabric
    if ($script:downloadCount -ne $downloads) { throw 'Unchanged shader setup downloaded files again.' }
    # A shader update retires its old managed ZIP and keeps unrelated shaders.
    [IO.File]::WriteAllText("$profile/shaderpacks/personal.zip", 'personal shader')
    $nextShader = New-FixtureVersion shader2 complementary-project r5.9.1 complementary-next.zip -Loaders @('iris')
    $plan.Shader = $nextShader
    Install-MinecraftTestShaders -ProfileDirectory $profile -Plan $plan -LoaderId fabric
    if ((Test-Path "$profile/shaderpacks/complementary.zip") -or -not (Test-Path "$profile/shaderpacks/personal.zip")) { throw 'Shader update removed unrelated files or retained the old managed shader.' }
    $script:corruptDownloads = $true
    $failed = $false
    $badProfile = Join-Path $fixture 'bad-download'
    try { Install-MinecraftTestShaders -ProfileDirectory $badProfile -Plan $plan -LoaderId fabric } catch { $failed = $_.Exception.Message -match 'checksum' }
    if (-not $failed -or (Test-Path "$badProfile/mods")) { throw 'A bad checksum installed partial shader files.' }
    $script:corruptDownloads = $false
    # Existing incompatible, unowned versions are rejected before files are changed.
    $conflictProfile = Join-Path $fixture 'conflicting-profile'
    Ensure-Directory "$conflictProfile/mods"
    [IO.File]::WriteAllText("$conflictProfile/mods/personal-sodium.jar", 'unmanaged older sodium')
    $hash = (Get-FileHash "$conflictProfile/mods/personal-sodium.jar" -Algorithm SHA512).Hash.ToLowerInvariant()
    $script:knownInstalled = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject @{ $hash = @{ id = 'different-version'; project_id = 'AANobbMI' } })
    $failed = $false
    try { Install-MinecraftTestShaders -ProfileDirectory $conflictProfile -Plan $plan -LoaderId fabric } catch { $failed = $_.Exception.Message -match 'conflicts with required' }
    if (-not $failed -or @(Get-ChildItem "$conflictProfile/mods").Count -ne 1) { throw 'Existing conflicting Sodium was overwritten or duplicated.' }
    $script:knownInstalled = [pscustomobject]@{}
    $forgePlan = Get-MinecraftTestShaderPlan -MinecraftVersion 1.21.1 -LoaderId forge
    if ('oculus1' -cnotin @($forgePlan.Mods.id) -or 'embeddium1' -cnotin @($forgePlan.Mods.id)) { throw 'Forge shader dependencies were not resolved.' }
    $forgeProfile = Join-Path $fixture 'forge'
    Install-MinecraftTestShaders -ProfileDirectory $forgeProfile -Plan $forgePlan -LoaderId forge
    if (-not (Test-Path "$forgeProfile/config/oculus.properties")) { throw 'Oculus configuration was not generated.' }
    # Pinned dependencies must support the chosen loader, and conflicts must fail.
    $api.loaders = @('forge')
    $failed = $false
    try { Get-MinecraftTestShaderPlan -MinecraftVersion 1.21.1 -LoaderId fabric | Out-Null } catch { $failed = $_.Exception.Message -match 'does not support' }
    if (-not $failed) { throw 'An incompatible pinned dependency was accepted.' }
    $api.loaders = @('fabric','neoforge','forge')

    # Pack-declared optional roots share the shader graph and use the publishing selectors.
    . (Join-Path $PSScriptRoot 'minecraft-test-pack-dependencies.ps1')
    $parseTokens = $null; $parseErrors = $null
    $builderAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$parseTokens, [ref]$parseErrors)
    foreach ($definition in $builderAst.EndBlock.Statements) {
        if ($definition -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $definition.Extent.Text }
    }
    $packMod = New-FixtureVersion packmod1 Mod00001 1.0.0 pack-mod.jar -Dependencies @((Required fabric-api api1))
    $script:projectVersions.Mod00001 = @($packMod)
    $matrix = @{ Versions = @(@{ Id = '1.20.1' }, @{ Id = '1.21.1' }) }
    $packOptions = @{ Modrinth = @{ Dependencies = @(
        @{ ProjectId = 'Mod00001'; Type = 'optional'; Versions = @('1.21.1') },
        @{ ProjectId = 'Old00001'; Type = 'optional'; Versions = @('1.20.1') },
        @{ ProjectId = 'Missing1'; Type = 'optional' },
        @{ ProjectId = 'Ignore01'; Type = 'embedded' },
        @{ ProjectId = 'Ignore02'; Type = 'optional'; Enabled = $false }
    ) } }
    $combinedPlan = Get-MinecraftPackDependencyPlan -PackOptions $packOptions -Config $matrix -PackName fixture -MinecraftVersion 1.21.1 -LoaderId fabric
    if ($combinedPlan.Mods.Count -ne 5 -or 'packmod1' -cnotin @($combinedPlan.Mods.id) -or @($combinedPlan.Mods | Where-Object { $_.id -eq 'api1' }).Count -ne 1) { throw 'Optional pack mod, transitive library, or shared dependency deduplication failed.' }
    if ($combinedPlan.Skipped.Count -ne 1 -or $combinedPlan.Skipped[0] -notlike 'Missing1*') { throw 'Unavailable optional dependency was not reported.' }
    Install-MinecraftTestShaders -ProfileDirectory $profile -Plan $combinedPlan -LoaderId fabric
    $packOnly = Get-MinecraftPackDependencyPlan -PackOptions $packOptions -Config $matrix -PackName fixture -MinecraftVersion 1.21.1 -LoaderId fabric -SkipShaders
    if ($null -ne $packOnly.Shader -or 'packmod1' -cnotin @($packOnly.Mods.id)) { throw 'SkipShaders disabled pack dependencies.' }
    Install-MinecraftTestShaders -ProfileDirectory $profile -Plan $packOnly -LoaderId fabric
    if (-not (Test-Path "$profile/shaderpacks/complementary.zip") -or -not (Test-Path "$profile/mods/iris.jar")) { throw 'Pack-only setup removed existing shader support.' }
    $newProfile = Join-Path $fixture 'pack-only'
    Install-MinecraftTestShaders -ProfileDirectory $newProfile -Plan $packOnly -LoaderId fabric
    if (-not (Test-Path "$newProfile/mods/pack-mod.jar") -or (Test-Path "$newProfile/config/iris.properties")) { throw 'Pack-only installation incorrectly requires or enables shaders.' }
    $vanillaPlan = Get-MinecraftPackDependencyPlan -PackOptions $packOptions -Config $matrix -PackName fixture -MinecraftVersion 1.21.1 -LoaderId vanilla -SkipShaders
    if ($vanillaPlan.Mods.Count -or $vanillaPlan.Skipped.Count -ne 2) { throw 'Vanilla received mods or failed to report skipped mods.' }
    $packOptions.Modrinth.Dependencies = @(@{ ProjectId = 'Missing1'; Type = 'required' })
    $failed = $false
    try { Get-MinecraftPackDependencyPlan -PackOptions $packOptions -Config $matrix -PackName fixture -MinecraftVersion 1.21.1 -LoaderId fabric -SkipShaders | Out-Null } catch { $failed = $_.Exception.Message -like 'Required pack dependency*' }
    if (-not $failed) { throw 'Missing required pack dependency was silently skipped.' }

    # CurseForge-only mods and their required libraries use SHA1, verified before installation.
    $cfSource = Join-Path $fixture 'cf-source.jar'
    [IO.File]::WriteAllText($cfSource, 'CurseForge-only mod fixture')
    $script:downloadSources['https://example.invalid/cf-only.jar'] = $cfSource
    function Invoke-TestCurseForgeApi {
        param($Path)
        if ($Path -notlike 'mods/900001/files?*' -and $Path -notlike 'mods/900002/files?*') { throw "Unexpected CurseForge fixture request: $Path" }
        $isRoot = $Path -like 'mods/900001/*'
        return [pscustomobject]@{ data = @([pscustomobject]@{
            id = $(if ($isRoot) { 900011 } else { 900012 }); displayName = 'CF-only'; fileName = $(if ($isRoot) { 'cf-only.jar' } else { 'cf-library.jar' });
            gameVersions = @('1.21.1'); isAvailable = $true; releaseType = 1; fileDate = '2026-01-01T00:00:00Z'; downloadUrl = 'https://example.invalid/cf-only.jar';
            hashes = @([pscustomobject]@{ algo = 1; value = (Get-FileHash -LiteralPath $cfSource -Algorithm SHA1).Hash });
            dependencies = $(if ($isRoot) { @([pscustomobject]@{ modId = 900002; relationType = 3 }) } else { @() })
        }) }
    }
    $cfOptions = @{ CurseForge = @{ Dependencies = @(@{ ProjectId = '900001'; Slug = 'cf-only'; Type = 'optionalDependency' }) } }
    $cfPlan = Get-MinecraftPackDependencyPlan -PackOptions $cfOptions -Config $matrix -PackName fixture -MinecraftVersion 1.21.1 -LoaderId neoforge -SkipShaders
    if ($cfPlan.Mods.Count -ne 2 -or 'curseforge:900002' -cnotin @($cfPlan.Mods.project_id)) { throw 'CurseForge required libraries were not resolved.' }
    $cfProfile = Join-Path $fixture 'curseforge'
    Install-MinecraftTestShaders -ProfileDirectory $cfProfile -Plan $cfPlan -LoaderId neoforge
    Install-MinecraftTestShaders -ProfileDirectory $cfProfile -Plan $cfPlan -LoaderId neoforge
    if (@(Get-ChildItem "$cfProfile/mods" -Filter '*.jar').Count -ne 2) { throw 'CurseForge-only mods failed installation or repeated checksum checks.' }
    $script:corruptDownloads = $true
    $failed = $false
    try { Install-MinecraftTestShaders -ProfileDirectory (Join-Path $fixture 'bad-cf') -Plan $cfPlan -LoaderId neoforge } catch { $failed = $_.Exception.Message -match 'checksum' }
    if (-not $failed) { throw 'Corrupt CurseForge download was accepted.' }
    Write-Output 'Minecraft shader setup tests passed.'
}
finally {
    if (Get-Variable iris -ErrorAction SilentlyContinue) {
        $cacheFile = Join-Path ([IO.Path]::GetTempPath()) "rpm-shader-metadata/$($iris.files[0].hashes.sha512).jar"
        if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile }
    }
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe shader fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
