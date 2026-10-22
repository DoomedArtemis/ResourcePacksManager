$script:MinecraftTestApiCache = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)

function Invoke-ShaderModrinthApi {
    param([string]$Path, $Body)
    $cacheKey = $Path + $(if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 20 -Compress } else { '' })
    if ($script:MinecraftTestApiCache.ContainsKey($cacheKey)) { return $script:MinecraftTestApiCache[$cacheKey] }
    $arguments = @{ Uri = "https://api.modrinth.com/v2/$Path"; Headers = @{ 'User-Agent' = 'resource-packs-manager/1.0 (local Minecraft shader tests)' }; TimeoutSec = 30 }
    if ($null -ne $Body) { $arguments.Method = 'Post'; $arguments.ContentType = 'application/json'; $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
    $response = Invoke-RestMethod @arguments
    $script:MinecraftTestApiCache[$cacheKey] = $response
    return $response
}

function Convert-ShaderSemanticVersion {
    param([string]$Value)
    if ($Value -notmatch '^(?:mc[0-9.]+-)?(?<core>\d+\.\d+(?:\.\d+)?(?:\.\d+)?)') { throw "Cannot read shader mod version '$Value'." }
    $parts = @($Matches.core.Split('.') | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 4) { $parts += 0 }
    return [Version]::new($parts[0], $parts[1], $parts[2], $parts[3])
}

function Test-ShaderVersionConstraint {
    param([string]$Value, [string[]]$Constraints)
    $number = Convert-ShaderSemanticVersion $Value
    foreach ($constraint in $Constraints) {
        $constraint = $constraint.Trim()
        if ($constraint -in @('*','')) { return $true }
        if ($constraint -match '^([\[\(])([^,]*),([^\]\)]*)([\]\)])$') {
            $leftClosed = $Matches[1] -eq '['; $rightClosed = $Matches[4] -eq ']'
            $left = $Matches[2]; $right = $Matches[3]
            if ($left -and $(if ($leftClosed) { $number -lt (Convert-ShaderSemanticVersion $left) } else { $number -le (Convert-ShaderSemanticVersion $left) })) { continue }
            if ($right -and $(if ($rightClosed) { $number -gt (Convert-ShaderSemanticVersion $right) } else { $number -ge (Convert-ShaderSemanticVersion $right) })) { continue }
            return $true
        }
        $matchesAll = $true
        foreach ($token in @($constraint -split '\s+' | Where-Object { $_ -and $_ -ne '&' })) {
            if ($token -match '^(?<base>\d+(?:\.\d+)*)(?:\.[xX*])$') {
                $prefix = $Matches.base.Split('.')
                $components = @($number.Major,$number.Minor,$number.Build,$number.Revision)
                for ($i = 0; $i -lt $prefix.Count; $i++) { if ([int]$prefix[$i] -ne $components[$i]) { $matchesAll = $false } }
            } elseif ($token -match '^(?<operator>>=|<=|>|<|=|~|\^)?(?<version>\d+\.\d+(?:\.\d+)?)$') {
                $operator = $Matches.operator; $minimum = Convert-ShaderSemanticVersion $Matches.version
                switch ($operator) {
                    '>=' { if ($number -lt $minimum) { $matchesAll = $false } }
                    '<=' { if ($number -gt $minimum) { $matchesAll = $false } }
                    '>' { if ($number -le $minimum) { $matchesAll = $false } }
                    '<' { if ($number -ge $minimum) { $matchesAll = $false } }
                    '~' { if ($number -lt $minimum -or $number -ge [Version]::new($minimum.Major,$minimum.Minor+1,0,0)) { $matchesAll = $false } }
                    '^' {
                        $upper = if ($minimum.Major) { [Version]::new($minimum.Major+1,0,0,0) } elseif ($minimum.Minor) { [Version]::new(0,$minimum.Minor+1,0,0) } else { [Version]::new(0,0,$minimum.Build+1,0) }
                        if ($number -lt $minimum -or $number -ge $upper) { $matchesAll = $false }
                    }
                    default { if ($number -ne $minimum) { $matchesAll = $false } }
                }
            } else { throw "Unsupported shader dependency version constraint '$constraint'." }
        }
        if ($matchesAll) { return $true }
    }
    return $false
}

function Get-ShaderProjectVersion {
    param([string]$Project, [string]$MinecraftVersion, [string]$LoaderId, [string[]]$VersionConstraints)
    if ($Project -match '^curseforge:(\d+)$') { return Get-TestCurseForgeVersion -ProjectId $Matches[1] -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId }
    $game = [Uri]::EscapeDataString((ConvertTo-Json -InputObject @($MinecraftVersion) -Compress))
    $loader = [Uri]::EscapeDataString((ConvertTo-Json -InputObject @($LoaderId) -Compress))
    $versions = Invoke-ShaderModrinthApi -Path "project/$([Uri]::EscapeDataString($Project))/version?game_versions=$game&loaders=$loader"
    $compatible = @($versions | Where-Object { $null -ne $_ -and $MinecraftVersion -cin @($_.game_versions) -and $LoaderId -cin @($_.loaders) })
    if ($VersionConstraints) { $compatible = @($compatible | Where-Object { Test-ShaderVersionConstraint -Value $_.version_number -Constraints $VersionConstraints }) }
    $releases = @($compatible | Where-Object { $_.version_type -eq 'release' })
    if ($releases.Count) { $compatible = $releases }
    return $compatible | Sort-Object { [DateTimeOffset]$_.date_published } -Descending | Select-Object -First 1
}

function Get-IrisSodiumConstraints {
    param($Version)
    $file = Get-ShaderDownloadFile -Version $Version -Folder mods -Extension '.jar'
    $cache = Join-Path ([IO.Path]::GetTempPath()) 'rpm-shader-metadata'
    Ensure-Directory $cache
    $cachedJar = Join-Path $cache "$($file.Sha512).jar"
    if (-not (Test-Path -LiteralPath $cachedJar) -or (Get-FileHash -LiteralPath $cachedJar -Algorithm SHA512).Hash -ine $file.Sha512) {
        $pending = Join-Path $cache ([Guid]::NewGuid().ToString('N') + '.download')
        try {
            Save-MinecraftShaderDownload -Url $file.Url -Destination $pending
            if ((Get-FileHash -LiteralPath $pending -Algorithm SHA512).Hash -ine $file.Sha512) { throw 'Iris metadata download checksum failed.' }
            Move-Item -LiteralPath $pending -Destination $cachedJar -Force
        } finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending } }
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($cachedJar)
    try {
        $fabric = $zip.GetEntry('fabric.mod.json')
        if ($fabric) {
            $reader = [IO.StreamReader]::new($fabric.Open())
            try { $metadata = ConvertFrom-Json -InputObject $reader.ReadToEnd() } finally { $reader.Dispose() }
            if ($metadata.depends.PSObject.Properties['sodium']) { return @($metadata.depends.sodium) }
        }
        foreach ($name in @('META-INF/neoforge.mods.toml','META-INF/mods.toml')) {
            $entry = $zip.GetEntry($name)
            if (-not $entry) { continue }
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            foreach ($block in @($text -split '\[\[dependencies\.iris\]\]')) {
                if ($block -match 'modId\s*=\s*"sodium"' -and $block -match 'versionRange\s*=\s*"([^"]+)"') { return @($Matches[1]) }
            }
        }
    } finally { $zip.Dispose() }
    throw 'Iris does not declare a readable Sodium version constraint; automatic installation cannot select a safe dependency.'
}

function Add-ShaderRequiredVersion {
    param($Version, [string]$MinecraftVersion, [string]$LoaderId, $Resolved)
    if ($MinecraftVersion -cnotin @($Version.game_versions) -or $LoaderId -cnotin @($Version.loaders)) { throw "Shader dependency '$($Version.name)' does not support Minecraft $MinecraftVersion / $LoaderId." }
    $projectId = [string]$Version.project_id
    if ($Resolved.ContainsKey($projectId)) {
        if ($Resolved[$projectId].id -cne $Version.id) { throw "Conflicting required versions for shader dependency '$projectId'." }
        return
    }
    $Resolved.Add($projectId, $Version)
    foreach ($dependency in @($Version.dependencies | Where-Object { $_.dependency_type -eq 'required' })) {
        $required = if ($dependency.version_id) {
            Invoke-ShaderModrinthApi -Path "version/$([Uri]::EscapeDataString($dependency.version_id))"
        } elseif ($dependency.project_id -and $Resolved.ContainsKey([string]$dependency.project_id)) {
            $Resolved[[string]$dependency.project_id]
        } elseif ($dependency.project_id) {
            Get-ShaderProjectVersion -Project $dependency.project_id -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId
        } else { throw "Shader dependency '$($dependency.file_name)' has no downloadable project or version ID." }
        if ($null -eq $required) { throw "No compatible required shader dependency '$($dependency.project_id)' for $MinecraftVersion / $LoaderId." }
        if ($dependency.project_id -and $dependency.project_id -notlike 'curseforge:*' -and $required.project_id -cne $dependency.project_id) { throw 'Shader dependency project/version IDs do not match.' }
        Add-ShaderRequiredVersion -Version $required -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -Resolved $Resolved
    }
}

function Get-MinecraftTestShaderPlan {
    param([string]$MinecraftVersion, [string]$LoaderId)
    if ($LoaderId -eq 'vanilla') { return [pscustomobject]@{ Supported = $false; Reason = 'Vanilla cannot load shader mods. Choose Fabric, NeoForge, or Forge for automatic shader setup.' } }
    $backendProject = if ($LoaderId -eq 'forge') { 'oculus' } else { 'iris' }
    $backend = Get-ShaderProjectVersion -Project $backendProject -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId
    if ($null -eq $backend) { return [pscustomobject]@{ Supported = $false; Reason = "No compatible $backendProject shader loader is published for Minecraft $MinecraftVersion / $LoaderId; shader setup skipped." } }
    $shader = Get-ShaderProjectVersion -Project 'complementary-reimagined' -MinecraftVersion $MinecraftVersion -LoaderId 'iris'
    if ($null -eq $shader) { return [pscustomobject]@{ Supported = $false; Reason = "No compatible Complementary Reimagined release for Minecraft $MinecraftVersion; shader setup skipped." } }
    if ($backendProject -eq 'iris') {
        $sodiumDependencies = @($backend.dependencies | Where-Object { $_.dependency_type -eq 'required' -and $_.project_id -ceq 'AANobbMI' })
        if (-not @($sodiumDependencies | Where-Object { $_.version_id }).Count) {
            # Older Iris releases omit Sodium's range in the Modrinth API. Read the mod's own manifest.
            $constraints = @(Get-IrisSodiumConstraints -Version $backend)
            $sodium = Get-ShaderProjectVersion -Project sodium -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -VersionConstraints $constraints
            if ($null -eq $sodium) { throw "No Sodium release satisfies Iris requirements: $($constraints -join ' or ')." }
            $backend.dependencies = @($backend.dependencies | Where-Object { $_.project_id -cne 'AANobbMI' }) + @([pscustomobject]@{ project_id = 'AANobbMI'; version_id = $sodium.id; dependency_type = 'required'; file_name = $null })
        }
    }
    $resolved = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    Add-ShaderRequiredVersion -Version $backend -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -Resolved $resolved
    foreach ($dependency in @($shader.dependencies | Where-Object { $_.dependency_type -eq 'required' })) {
        $required = if ($dependency.version_id) { Invoke-ShaderModrinthApi -Path "version/$([Uri]::EscapeDataString($dependency.version_id))" }
            elseif ($dependency.project_id) { Get-ShaderProjectVersion -Project $dependency.project_id -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId }
            else { throw 'A required shader-pack dependency has no downloadable project or version ID.' }
        if ($null -eq $required) { throw 'A required shader-pack dependency is unavailable for this Minecraft version and loader.' }
        Add-ShaderRequiredVersion -Version $required -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId -Resolved $resolved
    }
    foreach ($version in $resolved.Values) {
        foreach ($conflict in @($version.dependencies | Where-Object { $_.dependency_type -eq 'incompatible' })) {
            foreach ($other in $resolved.Values) {
                if (($conflict.version_id -and $other.id -ceq $conflict.version_id) -or (-not $conflict.version_id -and $other.project_id -ceq $conflict.project_id)) { throw 'Shader dependencies declare an incompatible combination.' }
            }
        }
    }
    [pscustomobject]@{ Supported = $true; Mods = @($resolved.Values); Shader = $shader }
}

function Get-ShaderDownloadFile {
    param($Version, [string]$Folder, [string]$Extension)
    $files = @($Version.files | Where-Object { $_.primary })
    if (-not $files.Count -and @($Version.files).Count -eq 1) { $files = @($Version.files) }
    if ($files.Count -ne 1) { throw "Cannot identify the primary download for '$($Version.name)'." }
    $file = $files[0]
    if ([IO.Path]::GetFileName($file.filename) -cne $file.filename -or $file.filename -match '[<>:"/\\|?*\x00-\x1f]' -or [IO.Path]::GetExtension($file.filename) -cne $Extension) { throw 'Invalid shader dependency download filename.' }
    $algorithm = if ($file.hashes.PSObject.Properties['sha512'] -and $file.hashes.sha512 -cmatch '^[0-9a-fA-F]{128}$') { 'SHA512' }
        elseif ($file.hashes.PSObject.Properties['sha1'] -and $file.hashes.sha1 -cmatch '^[0-9a-fA-F]{40}$') { 'SHA1' } else { throw 'Dependency download is missing a valid checksum.' }
    if (([Uri]$file.url).Scheme -ne 'https') { throw 'Dependency download requires an HTTPS URL.' }
    [pscustomobject]@{ Path = "$Folder/$($file.filename)"; Sha512 = $(if ($algorithm -eq 'SHA512') { $file.hashes.sha512 } else { $null }); HashAlgorithm = $algorithm; ExpectedHash = $file.hashes.($algorithm.ToLowerInvariant()); Url = $file.url; VersionId = $Version.id; ProjectId = $Version.project_id }
}

function Test-MinecraftManagedFileHash {
    param([string]$Path, $File)
    $algorithm = if ($File.PSObject.Properties['HashAlgorithm']) { $File.HashAlgorithm } else { 'SHA512' }
    if ($algorithm -notin @('SHA512','SHA1')) { throw 'Invalid managed dependency checksum algorithm.' }
    $expected = if ($File.PSObject.Properties['ExpectedHash']) { $File.ExpectedHash } else { $File.Sha512 }
    return (Get-FileHash -LiteralPath $Path -Algorithm $algorithm).Hash -ieq $expected
}

function Save-MinecraftShaderDownload {
    param([string]$Url, [string]$Destination)
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -TimeoutSec 180 | Out-Null
}

function Install-MinecraftTestShaders {
    param([string]$ProfileDirectory, $Plan, [string]$LoaderId)
    $files = @(foreach ($version in $Plan.Mods) { Get-ShaderDownloadFile -Version $version -Folder mods -Extension '.jar' })
    $shader = if ($null -ne $Plan.Shader) { Get-ShaderDownloadFile -Version $Plan.Shader -Folder shaderpacks -Extension '.zip' } else { $null }
    if ($shader) { $files += $shader }
    $manifestPath = Join-Path $ProfileDirectory 'config/rpm-test-shaders.json'
    $previous = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } else { $null }
    $oldFiles = @()
    if ($previous) { $oldFiles = @($previous.Files) }
    if ($Plan.PSObject.Properties['PreserveExisting'] -and $Plan.PreserveExisting) {
        $files += @($oldFiles | Where-Object { $_.ProjectId -cnotin @($files.ProjectId) })
    }
    if (@($files.Path | Select-Object -Unique).Count -ne $files.Count) { throw 'Test dependencies have colliding filenames.' }
    foreach ($old in $oldFiles) {
        if ($old.Path -cnotmatch '^(mods|shaderpacks)/[^/\\]+\.(jar|zip)$' -or $old.Path -match '\.\.') { throw 'Invalid managed shader file path.' }
        $path = Join-Path $ProfileDirectory $old.Path
        if ((Test-Path -LiteralPath $path) -and -not (Test-MinecraftManagedFileHash -Path $path -File $old)) { throw "Managed dependency file '$($old.Path)' was changed outside the test launcher. Restore or remove it before updating." }
    }
    # Resolve existing, unowned mods by hash to prevent duplicate versions of a dependency.
    $modRoot = Join-Path $ProfileDirectory 'mods'
    $existing = @()
    if (Test-Path -LiteralPath $modRoot) {
        $existing = @(Get-ChildItem -LiteralPath $modRoot -File -Filter '*.jar' | Where-Object { "mods/$($_.Name)" -cnotin @($oldFiles | ForEach-Object { $_.Path }) } | ForEach-Object {
            [pscustomobject]@{ File = $_; Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA512).Hash.ToLowerInvariant() }
        })
    }
    $alreadyInstalled = New-Object 'Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    if ($existing.Count) {
        $known = Invoke-ShaderModrinthApi -Path 'version_files' -Body @{ hashes = @($existing | ForEach-Object { $_.Hash }); algorithm = 'sha512' }
        foreach ($entry in $existing) {
            $property = $known.PSObject.Properties[$entry.Hash]
            if ($null -eq $property) {
                if ($entry.File.Name -match '^(iris|sodium|oculus|embeddium|rubidium)[-_+.]') { throw "Cannot verify existing shader mod '$($entry.File.Name)' against Modrinth. Remove it before automatic shader setup, or use -SkipShaders." }
                continue
            }
            $installedVersion = $property.Value
            foreach ($version in $Plan.Mods) {
                if ($installedVersion.project_id -ceq $version.project_id) {
                    if ($installedVersion.id -cne $version.id) { throw "Existing mod '$($entry.File.Name)' conflicts with required shader dependency '$($version.name)'. Remove or update that mod first." }
                    $alreadyInstalled[$version.id] = $true
                }
                foreach ($conflict in @($version.dependencies | Where-Object { $_.dependency_type -eq 'incompatible' })) {
                    if (($conflict.version_id -and $conflict.version_id -ceq $installedVersion.id) -or (-not $conflict.version_id -and $conflict.project_id -ceq $installedVersion.project_id)) { throw "Existing mod '$($entry.File.Name)' is incompatible with the shader setup." }
                }
            }
        }
    }
    $staging = Join-Path ([IO.Path]::GetTempPath()) ('rpm-shaders-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        foreach ($file in $files) {
            if ($alreadyInstalled.ContainsKey($file.VersionId)) { continue }
            $destination = Join-Path $ProfileDirectory $file.Path
            if (Test-Path -LiteralPath $destination) {
                if (Test-MinecraftManagedFileHash -Path $destination -File $file) { continue }
                if ($file.Path -cnotin @($oldFiles | ForEach-Object { $_.Path })) { throw "Existing file '$($file.Path)' has different contents; it will not be overwritten." }
            }
            $download = Join-Path $staging ([IO.Path]::GetFileName($file.Path))
            Write-Host "Downloading test dependency: $([IO.Path]::GetFileName($file.Path))"
            Save-MinecraftShaderDownload -Url $file.Url -Destination $download
            if (-not (Test-MinecraftManagedFileHash -Path $download -File $file)) { throw "Shader download checksum failed: $($file.Path)" }
        }
        # All downloads are verified before installed files are changed.
        foreach ($old in $oldFiles) {
            if ($old.Path -cnotin @($files.Path)) {
                $path = Join-Path $ProfileDirectory $old.Path
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            }
        }
        foreach ($file in $files) {
            $download = Join-Path $staging ([IO.Path]::GetFileName($file.Path))
            if (Test-Path -LiteralPath $download) {
                $destination = Join-Path $ProfileDirectory $file.Path
                Ensure-Directory (Split-Path $destination -Parent)
                Copy-Item -LiteralPath $download -Destination $destination -Force
            }
        }
        Ensure-Directory (Split-Path $manifestPath -Parent)
        if ($shader) {
        $configPath = Join-Path $ProfileDirectory $(if ($LoaderId -eq 'forge') { 'config/oculus.properties' } else { 'config/iris.properties' })
        $lines = if (Test-Path -LiteralPath $configPath) { @([IO.File]::ReadAllLines($configPath)) } else { @() }
        $lines = @($lines | Where-Object { $_ -notmatch '^\s*(shaderPack|enableShaders)\s*=' }) + @("shaderPack=$([IO.Path]::GetFileName($shader.Path))", 'enableShaders=true')
        if (Test-Path -LiteralPath $configPath) { Copy-Item -LiteralPath $configPath -Destination "$configPath.rpm-test.bak" -Force }
        [IO.File]::WriteAllLines($configPath, [string[]]$lines, [Text.UTF8Encoding]::new($false))
        }
        @{ Files = @($files | Where-Object { -not $alreadyInstalled.ContainsKey($_.VersionId) }); Loader = $LoaderId } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }
    finally {
        $resolvedStaging = [IO.Path]::GetFullPath($staging)
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedStaging.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedStaging -Leaf) -notlike 'rpm-shaders-*') { throw 'Unsafe shader staging cleanup path.' }
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}

function Initialize-MinecraftTestShaders {
    param([string]$ProfileDirectory, [string]$MinecraftVersion, [string]$LoaderId, [switch]$DryRun)
    $plan = Get-MinecraftTestShaderPlan -MinecraftVersion $MinecraftVersion -LoaderId $LoaderId
    if (-not $plan.Supported) { Write-Host $plan.Reason; return }
    Write-Host "Shader setup: $(@($plan.Mods | ForEach-Object { $_.name }) -join ', '), Complementary Reimagined $($plan.Shader.version_number)"
    if (-not $DryRun) { Install-MinecraftTestShaders -ProfileDirectory $ProfileDirectory -Plan $plan -LoaderId $LoaderId }
}
