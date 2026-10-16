[CmdletBinding()]
param([switch]$BuildSources)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
$repoRoot = Split-Path $PSScriptRoot -Parent
$config = Import-PowerShellDataFile (Join-Path $repoRoot 'config/texture-pack.build.psd1')
$config.Versions = (Import-PowerShellDataFile (Join-Path $repoRoot $config.VersionMatrixPath)).Versions
$definitionPath = Join-Path $repoRoot 'artemis_enhanced_visuals/artemis_enhanced_visuals.psd1'
$definition = Import-PowerShellDataFile $definitionPath
$directory = [pscustomobject]@{ Name = $definition.Name; FullName = Split-Path $definitionPath -Parent; CombinedDefinitionPath = $definitionPath }

foreach ($scriptName in @('publish-modrinth.ps1', 'publish-curseforge.ps1')) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Syntax errors in $scriptName" }
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
    $platform = if ($scriptName -eq 'publish-modrinth.ps1') { 'Modrinth' } else { 'CurseForge' }
    $resolver = "Get-$($platform)Dependencies"
    $options = Get-PackBuildOptions -PackDirectory $directory -Config $config
    $order = Get-VersionOrderLookup $config
    foreach ($version in $config.Versions) {
        $expected = @()
        foreach ($entry in $definition.Packs) {
            if (-not $entry.Enabled) { continue }
            $path = Join-Path $repoRoot "resource_packs/$($entry.Name)/pack.build.psd1"
            if (-not (Test-Path $path)) { continue }
            $component = Import-PowerShellDataFile $path
            if (-not (Test-VersionSelectorMatch $component $version $order 'component')) { continue }
            if ($component.ContainsKey($platform) -and $component[$platform].ContainsKey('Dependencies')) {
                $expected += @(& $resolver -Dependencies $component[$platform].Dependencies -PackName $entry.Name -VersionConfig $version -VersionOrder $order)
            }
        }
        $actual = @(& $resolver -Dependencies $options[$platform].Dependencies -PackName $directory.Name -VersionConfig $version -VersionOrder $order)
        $expectedJson = @($expected | ForEach-Object { $_ | ConvertTo-Json -Compress } | Sort-Object -Unique) -join "`n"
        $actualJson = @($actual | ForEach-Object { $_ | ConvertTo-Json -Compress } | Sort-Object -Unique) -join "`n"
        if ($expectedJson -cne $actualJson) { throw "$platform inherited dependencies differ for $($version.Id)." }
        if ($version.Id -eq '1.20.1' -and $actual.Count -lt 4) { throw "$platform lost Artemis mod dependencies." }
        if ($version.Id -eq '1.21.11' -and $actual.Count) { throw "$platform included unsupported mod dependencies." }
    }
    Write-Output "Passed Artemis $platform dependency inheritance across the complete Minecraft version matrix."
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $fixture = Join-Path $temporaryRoot ('artemis-compatibility-test-' + [Guid]::NewGuid().ToString('N'))
    try {
        foreach ($name in @('enabled', 'disabled', 'empty')) { Ensure-Directory (Join-Path $fixture "resource_packs/$name") }
        Ensure-Directory (Join-Path $fixture 'artemis_enhanced_visuals')
        $id = if ($platform -eq 'Modrinth') { 'Ab12Cd34' } else { '12345' }
        $otherId = if ($platform -eq 'Modrinth') { 'Zz12Cd34' } else { '54321' }
        Set-Content (Join-Path $fixture 'resource_packs/enabled/pack.build.psd1') "@{ MinVersion = '1.20.1'; MaxVersion = '1.20.1'; $platform = @{ Dependencies = @(@{ ProjectId = '$id' }) } }"
        foreach ($name in @('disabled', 'empty')) {
            Set-Content (Join-Path $fixture "resource_packs/$name/pack.build.psd1") "@{ $platform = @{ Dependencies = @(@{ ProjectId = '$otherId' }) } }"
        }
        $fixtureDefinition = Join-Path $fixture 'artemis_enhanced_visuals/combined.psd1'
        $fixtureText = @'
@{ Name = 'combined'; Packs = @(
    @{ Name = 'enabled'; Enabled = $true }
    @{ Name = 'disabled'; Enabled = $false }
    @{ Name = 'empty'; Enabled = $true; Include = @() }
); PLATFORM = @{ Dependencies = @(@{ ProjectId = 'PROJECT_ID'; Versions = @('1.20.1') }) } }
'@
        Set-Content $fixtureDefinition $fixtureText.Replace('PLATFORM', $platform).Replace('PROJECT_ID', $id)
        $fixtureDirectory = [pscustomobject]@{ Name = 'combined'; CombinedDefinitionPath = $fixtureDefinition }
        $inherited = Get-PackBuildOptions $fixtureDirectory $config
        foreach ($versionId in @('1.13', '1.20.1', '1.21.11')) {
            $relations = @(& $resolver -Dependencies $inherited[$platform].Dependencies -PackName 'combined' -VersionConfig @{ Id = $versionId } -VersionOrder $order)
            if ($relations.Count -ne [int]($versionId -eq '1.20.1')) { throw "$platform failed component bounds, disabled/empty components, or duplicate relations for $versionId." }
        }
    }
    finally {
        $resolved = [IO.Path]::GetFullPath($fixture)
        if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'artemis-compatibility-test-*') { throw 'Unsafe fixture cleanup path.' }
        if (Test-Path $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}

if ($BuildSources) {
    . (Join-Path $PSScriptRoot 'combined-pack-dependencies.ps1')
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-combined-pack.ps1'), [ref]$tokens, [ref]$errors)
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
    Import-PackBuilderFunctions (Join-Path $PSScriptRoot 'build-texture-packs.ps1')
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $fixture = Join-Path $temporaryRoot ('artemis-compatibility-test-' + [Guid]::NewGuid().ToString('N'))
    $config.BuildRoot = Join-Path $fixture 'build'
    function Get-TemporaryBuildRoot { return Join-Path $fixture 'staging' }
    try {
        foreach ($versionId in @('1.20.1', '1.21.11')) {
            $version = Normalize-VersionConfig ($config.Versions | Where-Object { $_.Id -eq $versionId })
            $components = @{}; $owners = @{}
            $destination = Join-Path $fixture "merged/$versionId"
            Ensure-Directory $destination
            foreach ($pack in @('alternative_ores', 'better_candles')) {
                $entry = $definition.Packs | Where-Object { $_.Name -eq $pack }
                $source = Get-Item (Join-Path $repoRoot "resource_packs/$pack")
                $result = Build-PackVersion -RepoRoot $repoRoot -Config $config -PackDirectory $source -VersionConfig $version
                $component = Read-CombinedComponent -ZipPath $result.ZipPath -Entry $entry -Definition $definition -Root (Join-Path $fixture "inputs/$versionId/$pack") -Validation $config.Validation -VersionConfig $version
                $components[$pack] = $component
                Merge-CombinedArchive -Entry $entry -Definition $definition -Destination $destination -Owners $owners -Component $component
            }
            $vanilla = Get-CombinedVanillaDependencies -RepoRoot $repoRoot -Config $config -VersionConfig $version
            $null = Complete-CombinedDependencies -Name $definition.Name -Components $components -Vanilla $vanilla -Destination $destination -Owners $owners
            $null = Copy-CombinedPackDocumentation -RepoRoot $repoRoot -DefinitionDirectory $directory.FullName -Destination $destination -Components $components
            foreach ($mod in @('create', 'mekanism', 'dye_depot')) {
                $present = @($owners.Keys | Where-Object { $_.StartsWith("assets/$mod/") }).Count -gt 0
                if ($present -ne ($versionId -eq '1.20.1')) { throw "Wrong $mod assets in combined source build for $versionId." }
            }
            if ((Test-Path (Join-Path $destination 'compatibility.txt')) -ne ($versionId -eq '1.20.1')) { throw "Wrong combined support notes for $versionId." }
            Write-Output "Passed source component builds, combined dependency resolution, mod asset filtering and support notes for $versionId."
        }
    }
    finally {
        $resolved = [IO.Path]::GetFullPath($fixture)
        if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'artemis-compatibility-test-*') { throw 'Unsafe fixture cleanup path.' }
        if (Test-Path $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
