function Import-MinecraftTestDependencySelectors {
    foreach ($entry in @(@{ File = 'publish-modrinth.ps1'; Name = 'Get-ModrinthDependencies' }, @{ File = 'publish-curseforge.ps1'; Name = 'Get-CurseForgeDependencies' })) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $entry.File), [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "Dependency selector script has syntax errors: $($entry.File)" }
        $definition = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $entry.Name }
        $body = $definition.Body.Extent.Text
        Set-Item -Path ("Function:script:" + $entry.Name) -Value ([scriptblock]::Create($body.Substring(1, $body.Length - 2)))
    }
}

function Invoke-TestCurseForgeApi {
    param([string]$Path)
    $key = [Environment]::GetEnvironmentVariable('CURSEFORGE_API_KEY')
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'CurseForge-only dependencies require a CurseForge Core API key in CURSEFORGE_API_KEY (the publishing token is a different credential).' }
    try { return Invoke-RestMethod -Uri "https://api.curseforge.com/v1/$Path" -Headers @{ 'x-api-key' = $key; 'User-Agent' = 'resource-packs-manager/1.0' } -TimeoutSec 30 }
    catch { throw "CurseForge dependency request failed for '$Path'; check API access and connectivity." }
}

function Get-TestCurseForgeVersion {
    param([string]$ProjectId, [string]$MinecraftVersion, [string]$LoaderId)
    $loaderType = @{ forge = 1; fabric = 4; neoforge = 6 }[$LoaderId]
    if (-not $loaderType) { return $null }
    $allFiles = @(); $index = 0
    do {
        $response = Invoke-TestCurseForgeApi -Path "mods/$ProjectId/files?gameVersion=$([Uri]::EscapeDataString($MinecraftVersion))&modLoaderType=$loaderType&pageSize=50&index=$index"
        $page = @($response.data | Where-Object { $null -ne $_ })
        $allFiles += $page
        $index += $page.Count
    } while ($page.Count -eq 50 -and $index -lt 10000)
    $compatible = @($allFiles | Where-Object { $MinecraftVersion -cin @($_.gameVersions) -and $_.isAvailable })
    $stable = @($compatible | Where-Object { $_.releaseType -eq 1 })
    if ($stable.Count) { $compatible = $stable }
    $file = $compatible | Sort-Object { [DateTimeOffset]$_.fileDate } -Descending | Select-Object -First 1
    if ($null -eq $file) { return $null }
    if (-not $file.downloadUrl) { throw "CurseForge does not provide an authorized API download for '$($file.displayName)'." }
    $sha1 = @($file.hashes | Where-Object { $_.algo -eq 1 })
    if ($sha1.Count -ne 1) { throw "CurseForge file '$($file.displayName)' has no SHA1 checksum." }
    # If this exact file also exists on Modrinth, use its canonical identity and dependency metadata.
    try { $mirrored = Invoke-ShaderModrinthApi -Path "version_file/$($sha1[0].value)?algorithm=sha1" }
    catch { $mirrored = $null }
    if ($mirrored -and $MinecraftVersion -cin @($mirrored.game_versions) -and $LoaderId -cin @($mirrored.loaders)) { return $mirrored }
    $dependencies = @(foreach ($dependency in $file.dependencies) {
        $type = switch ($dependency.relationType) { 3 { 'required' }; 5 { 'incompatible' }; default { 'optional' } }
        [pscustomobject]@{ project_id = "curseforge:$($dependency.modId)"; version_id = $null; file_name = $null; dependency_type = $type }
    })
    [pscustomobject]@{ id = "curseforge-file:$($file.id)"; project_id = "curseforge:$ProjectId"; name = $file.displayName; version_number = $file.displayName;
        game_versions = @($MinecraftVersion); loaders = @($LoaderId); dependencies = $dependencies;
        files = @([pscustomobject]@{ primary = $true; filename = $file.fileName; url = $file.downloadUrl; hashes = [pscustomobject]@{ sha1 = $sha1[0].value } }) }
}

function Get-MinecraftPackDependencyRelations {
    param([hashtable]$PackOptions, $Config, [string]$PackName, [string]$MinecraftVersion)
    Import-MinecraftTestDependencySelectors
    $version = @($Config.Versions | Where-Object { $_.Id -eq $MinecraftVersion })[0]
    $order = Get-VersionOrderLookup -Config $Config
    $modrinth = if ($PackOptions.ContainsKey('Modrinth') -and $PackOptions.Modrinth.ContainsKey('Dependencies')) {
        @(Get-ModrinthDependencies -Dependencies $PackOptions.Modrinth.Dependencies -PackName $PackName -VersionConfig $version -VersionOrder $order)
    } else { @() }
    $curseforge = if ($PackOptions.ContainsKey('CurseForge') -and $PackOptions.CurseForge.ContainsKey('Dependencies')) {
        @(Get-CurseForgeDependencies -Dependencies $PackOptions.CurseForge.Dependencies -PackName $PackName -VersionConfig $version -VersionOrder $order)
    } else { @() }
    [pscustomobject]@{ Modrinth = @($modrinth); CurseForge = @($curseforge) }
}

function Get-MinecraftPackDependencyPlan {
    param([hashtable]$PackOptions, $Config, [string]$PackName, [string]$MinecraftVersion, [string]$LoaderId, [switch]$SkipShaders)
    $shaderPlan = if ($SkipShaders) { $null } else { Get-MinecraftTestShaderPlan -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId }
    if ($shaderPlan -and -not $shaderPlan.Supported) { Write-Host $shaderPlan.Reason }
    $resolved = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    if ($shaderPlan -and $shaderPlan.Supported) { foreach ($version in $shaderPlan.Mods) { $resolved[$version.project_id] = $version } }
    $relations = Get-MinecraftPackDependencyRelations -PackOptions $PackOptions -Config $Config -PackName $PackName -MinecraftVersion $MinecraftVersion
    $skipped = New-Object 'Collections.Generic.List[string]'
    $included = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($relation in @($relations.Modrinth | Where-Object { $_.dependency_type -in @('required','optional') })) {
        $identity = if ($relation.project_id) { $relation.project_id } elseif ($relation.version_id) { $relation.version_id } else { $relation.file_name }
        if ($LoaderId -eq 'vanilla') {
            if ($relation.dependency_type -eq 'required') { throw "Required pack dependency '$identity' needs a mod loader; select Fabric, NeoForge, or Forge." }
            $skipped.Add("$identity (mods require a mod loader)"); continue
        }
        Write-Host "Resolving pack dependency: $identity"
        try {
            $version = if ($relation.version_id) { Invoke-ShaderModrinthApi -Path "version/$($relation.version_id)" }
                elseif ($relation.project_id -and $resolved.ContainsKey([string]$relation.project_id)) { $resolved[[string]$relation.project_id] }
                elseif ($relation.project_id) { Get-ShaderProjectVersion -Project $relation.project_id -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId }
                else { $null }
        } catch {
            if ($relation.dependency_type -eq 'required') { throw }
            $skipped.Add("$identity (Modrinth lookup failed: $($_.Exception.Message))"); continue
        }
        if ($version -and $relation.project_id -and $version.project_id -cne $relation.project_id) { throw "Pack dependency '$identity' has mismatched project/version IDs." }
        if ($version -and ($MinecraftVersion -cnotin @($version.game_versions) -or $LoaderId -cnotin @($version.loaders))) { $version = $null }
        if ($null -eq $version) {
            if ($relation.dependency_type -eq 'required') { throw "Required pack dependency '$identity' is unavailable for $MinecraftVersion / $LoaderId." }
            $skipped.Add("$identity (no compatible Modrinth file for $MinecraftVersion / $LoaderId)"); continue
        }
        Add-ShaderRequiredVersion -Version $version -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -Resolved $resolved
        $null = $included.Add([string]$version.project_id)
    }
    # The checked-in synchronization map identifies the same project across services.
    $crosswalk = @{}
    $mapPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/compatibility-sync.json'
    if (Test-Path -LiteralPath $mapPath) {
        $map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
        foreach ($pack in $map.packs) { foreach ($group in $pack.groups) { foreach ($project in $group.projects) {
            if ($project.PSObject.Properties['curseforge'] -and $project.PSObject.Properties['modrinth']) { $crosswalk[[string]$project.curseforge] = [string]$project.modrinth }
        } } }
    }
    foreach ($relation in @($relations.CurseForge | Where-Object { $_.type -in @('requiredDependency','optionalDependency') })) {
        $projectId = if ($relation.Contains('projectID')) { [string]$relation.projectID } else { '' }
        if ($projectId -and $crosswalk.ContainsKey($projectId) -and $included.Contains($crosswalk[$projectId])) { continue }
        if ($LoaderId -eq 'vanilla') {
            if ($relation.type -eq 'requiredDependency') { throw "Required pack dependency '$($relation.slug)' needs a mod loader; select Fabric, NeoForge, or Forge." }
            $skipped.Add("CurseForge $($relation.slug) (mods require a mod loader)"); continue
        }
        # Most paired projects can be installed from Modrinth without CurseForge API access.
        $version = if ($projectId -and $crosswalk.ContainsKey($projectId)) { Get-ShaderProjectVersion -Project $crosswalk[$projectId] -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId } else { $null }
        if (-not $version) {
            try {
                if (-not $projectId) {
                    $lookup = Invoke-TestCurseForgeApi -Path "mods/search?gameId=432&slug=$([Uri]::EscapeDataString($relation.slug))"
                    $matches = @($lookup.data | Where-Object { $null -ne $_ -and $_.slug -ceq $relation.slug })
                    if ($matches.Count -ne 1) { throw "Cannot identify CurseForge project '$($relation.slug)'." }
                    $projectId = [string]$matches[0].id
                }
                $version = Get-TestCurseForgeVersion -ProjectId $projectId -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId
            }
            catch {
                if ($relation.type -eq 'requiredDependency') { throw }
                $skipped.Add("CurseForge $($relation.slug): $($_.Exception.Message)"); continue
            }
        }
        if ($null -eq $version) {
            if ($relation.type -eq 'requiredDependency') { throw "Required CurseForge dependency '$($relation.slug)' is unavailable for this Minecraft version and loader." }
            $skipped.Add("CurseForge $($relation.slug) (no compatible file for $MinecraftVersion / $LoaderId)"); continue
        }
        Add-ShaderRequiredVersion -Version $version -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -Resolved $resolved
    }
    foreach ($version in $resolved.Values) {
        foreach ($conflict in @($version.dependencies | Where-Object { $_.dependency_type -eq 'incompatible' })) {
            foreach ($other in $resolved.Values) {
                if (($conflict.version_id -and $conflict.version_id -ceq $other.id) -or (-not $conflict.version_id -and $conflict.project_id -ceq $other.project_id)) { throw "Pack dependency '$($version.name)' is incompatible with '$($other.name)'." }
            }
        }
        foreach ($conflict in @($relations.Modrinth | Where-Object { $_.dependency_type -eq 'incompatible' })) {
            if (($conflict.version_id -and $conflict.version_id -ceq $version.id) -or (-not $conflict.version_id -and $conflict.project_id -ceq $version.project_id)) { throw "Pack '$PackName' declares '$($version.name)' incompatible." }
        }
    }
    [pscustomobject]@{ Supported = $true; Mods = @($resolved.Values); Shader = $(if ($shaderPlan -and $shaderPlan.Supported) { $shaderPlan.Shader } else { $null }); PreserveExisting = [bool]$SkipShaders; Skipped = $skipped.ToArray() }
}

function Initialize-MinecraftTestEnvironment {
    param([string]$ProfileDirectory, [hashtable]$PackOptions, $Config, [string]$PackName, [string]$MinecraftVersion, [string]$LoaderId, [switch]$SkipShaders, [switch]$DryRun)
    $plan = Get-MinecraftPackDependencyPlan -PackOptions $PackOptions -Config $Config -PackName $PackName -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -SkipShaders:$SkipShaders
    foreach ($message in $plan.Skipped) { Write-Warning "Optional test dependency not installed: $message" }
    Write-Host "Test-profile mods: $(@($plan.Mods | ForEach-Object { $_.name }) -join ', ')"
    if (-not $DryRun -and ($plan.Mods.Count -or $null -ne $plan.Shader)) {
        Install-MinecraftTestShaders -ProfileDirectory $ProfileDirectory -Plan $plan -LoaderId $LoaderId
    }
}
