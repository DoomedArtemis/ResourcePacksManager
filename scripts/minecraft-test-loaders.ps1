function Get-MinecraftLoaderMetadata {
    param([string]$Kind)
    $urls = @{
        'fabric-games' = 'https://meta.fabricmc.net/v2/versions/game'
        fabric = 'https://launcher-meta.modrinth.com/fabric/v0/manifest.json'
        forge = 'https://launcher-meta.modrinth.com/forge/v0/manifest.json'
        neoforge = 'https://launcher-meta.modrinth.com/neo/v0/manifest.json'
    }
    Invoke-RestMethod -Uri $urls[$Kind] -TimeoutSec 20
}

function Get-MinecraftTestLoaders {
    param([string]$VersionId, [string]$RequestedLoader)
    $definitions = @(
        @{ Id = 'vanilla'; Group = 'Vanilla'; Dependency = '' }
        @{ Id = 'fabric'; Group = 'Fabric'; Dependency = 'fabric-loader' }
        @{ Id = 'neoforge'; Group = 'NeoForge'; Dependency = 'neoforge' }
        @{ Id = 'forge'; Group = 'Forge'; Dependency = 'forge' }
    )
    foreach ($definition in $definitions) {
        if ($RequestedLoader -and $definition.Id -ne $RequestedLoader) { continue }
        if ($definition.Id -eq 'vanilla') {
            [pscustomobject]@{ Id = 'vanilla'; Group = 'Vanilla'; Dependency = ''; LoaderVersion = '' }
            continue
        }
        try {
            if ($definition.Id -eq 'fabric') {
                # Fabric's universal launcher profile is not proof that a game version is supported.
                $games = @(Get-MinecraftLoaderMetadata -Kind 'fabric-games')
                if (-not @($games | Where-Object { $_.version -ceq $VersionId }).Count) { continue }
            }
            $manifest = Get-MinecraftLoaderMetadata -Kind $definition.Id
            $gameIds = @($VersionId)
            # NeoForge metadata uses 1.21.0 for Minecraft's release ID 1.21.
            if ($definition.Id -eq 'neoforge' -and $VersionId -match '^1\.\d+$') { $gameIds += "$VersionId.0" }
            $entries = @($manifest.gameVersions | Where-Object { $_.id -cin $gameIds })
            if (-not $entries.Count -and $definition.Id -eq 'fabric') {
                $entries = @($manifest.gameVersions | Where-Object { $_.id -ceq '${modrinth.gameVersion}' })
            }
            $versions = @(foreach ($entry in $entries) {
                $entry.loaders
                if ($entry.PSObject.Properties['versionGroup'] -and $entry.versionGroup -and $manifest.PSObject.Properties['versionGroups']) {
                    foreach ($group in @($manifest.versionGroups | Where-Object { $_.id -ceq $entry.versionGroup })) { $group.loaders }
                }
            })
            if (-not $versions.Count -and $definition.Id -eq 'fabric') {
                $versions = @(foreach ($entry in @($manifest.gameVersions | Where-Object { $_.id -ceq '${modrinth.gameVersion}' })) { $entry.loaders })
            }
            if (-not $versions.Count) { continue }
            # Manifests list newest first; prefer a stable loader when available.
            $stable = @($versions | Where-Object { $_.stable })
            $selected = if ($stable.Count) { $stable[0] } else { $versions[0] }
            [pscustomobject]@{ Id = $definition.Id; Group = $definition.Group; Dependency = $definition.Dependency; LoaderVersion = $selected.id }
        }
        catch {
            if ($RequestedLoader) { throw "Cannot verify $($definition.Group) support for Minecraft $VersionId. $($_.Exception.Message)" }
            Write-Warning "Could not check $($definition.Group) support for $VersionId; it will not be offered. $($_.Exception.Message)"
        }
    }
}
