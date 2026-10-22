[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = 'config/texture-pack.build.psd1',
    [string[]]$Pack,
    [string[]]$Version,
    [string]$ReleaseVersion,
    [string]$ArchiveRoot = 'archive'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')

# Reuse discovery, version selection, and naming without executing the builder.
$parseTokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Build script has syntax errors.' }
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$config = Import-PowerShellDataFile -Path (Resolve-FullPath -BasePath $repoRoot -Path $ConfigPath)
if ($config.ContainsKey('VersionMatrixPath') -and $config.VersionMatrixPath) {
    $matrix = Import-PowerShellDataFile -Path (Resolve-FullPath -BasePath $repoRoot -Path $config.VersionMatrixPath)
    $config['Versions'] = $matrix.Versions
}
if (-not $config.ContainsKey('Versions') -or @($config.Versions).Count -eq 0) { throw 'No Minecraft versions are configured.' }
$config['Versions'] = @($config.Versions | ForEach-Object { Normalize-VersionConfig -VersionConfig $_ })

if (-not $Pack) {
    Write-Host 'Available packs:'
    Get-PackDirectories -RepoRoot $repoRoot -Config $config | ForEach-Object { Write-Host "  - $($_.Name)" }
    $Pack = @((Read-Host 'Pack(s) to archive (comma-separated, or all)').Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $Pack) { throw 'No pack names entered.' }
}
if ($Pack.Count -eq 1 -and $Pack[0] -eq 'all') { $Pack = @() }
$directories = @(Get-PackDirectories -RepoRoot $repoRoot -Config $config -RequestedPackNames $Pack)
if (-not $Version) { $Version = @(Read-RequestedVersions -Config $config) }
$requested = @(Expand-RequestedVersionSelection -InputValue ($Version -join ',') -Config $config)
$versions = @($config.Versions | Where-Object { $_.Enabled -and $_.Id -in $requested })
if ($versions.Count -eq 0) { throw 'No enabled Minecraft versions selected.' }
if (-not $PSBoundParameters.ContainsKey('ReleaseVersion')) { $ReleaseVersion = Read-Host 'Pack release version (for example, 1.0.0)' }
$ReleaseVersion = $ReleaseVersion.Trim()
if ($null -eq (Convert-ArchivedPackRelease -Name $ReleaseVersion)) {
    throw 'Use a numeric release version such as 1.0.0 or 1.0.0-beta.1.'
}

$buildRoot = Resolve-FullPath -BasePath $repoRoot -Path $config.BuildRoot
$archiveRootPath = Resolve-FullPath -BasePath $repoRoot -Path $ArchiveRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem
$items = @(
    foreach ($directory in $directories) {
        $options = Get-PackBuildOptions -PackDirectory $directory -Config $config
        $displayName = Get-ReleasePackDisplayName -PackDirectory $directory -PackOptions $options
        foreach ($versionConfig in @(Get-PackSelectedVersions -PackDirectory $directory -Config $config -GloballySelectedVersions $versions)) {
            $tokens = @{ PackName = $directory.Name; PackDisplayName = $displayName; VersionId = $versionConfig.Id }
            $baseName = Convert-Tokens -Value $config.PackageNameTemplate -Tokens $tokens
            $zipPath = Join-Path (Join-Path $buildRoot $directory.Name) "$baseName.zip"
            $zipPath = Find-PackBuildZip -BuildZipPath $zipPath -MinecraftVersion $versionConfig.Id
            if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
                Write-Host "Skipping $($directory.Name) / $($versionConfig.Id): no build ZIP."
                continue
            }
            $item = [pscustomobject]@{ PackName = $directory.Name; PackDisplayName = $displayName; MinecraftVersion = $versionConfig.Id; ReleaseVersion = $ReleaseVersion; ZipPath = $zipPath; ZipSource = 'build' }
            # Validate every selected ZIP and filename before moving any files.
            $null = Get-ReleaseZipFileName -Item $item
            $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
            try {
                if ($null -eq $zip.GetEntry('pack.mcmeta')) { throw "Build ZIP does not contain root pack.mcmeta: $zipPath" }
            }
            finally { $zip.Dispose() }
            $item
        }
    }
)
if ($items.Count -eq 0) { Write-Host 'No matching build ZIPs to archive.'; return }
foreach ($item in @($items | Sort-Object ZipPath -Unique)) {
    $destination = Join-Path (Join-Path (Join-Path $archiveRootPath $item.PackName) $ReleaseVersion) (Get-ReleaseZipFileName -Item $item)
    if ($PSCmdlet.ShouldProcess($item.ZipPath, "Archive as $destination")) {
        $path = Move-ReleaseZipToArchive -Item $item -ArchiveRootPath $archiveRootPath
        Write-Output "Archived $($item.PackName) / $($item.MinecraftVersion) -> $path"
    }
}
