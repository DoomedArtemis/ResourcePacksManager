[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('combined-discovery-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'resource_packs/normal'), (Join-Path $fixture 'artemis_enhanced_visuals') -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $fixture 'artemis_enhanced_visuals/combined.psd1') -Value "@{ Name = 'combined'; DisplayName = 'Combined'; MinVersion = '1.17'; Modrinth = @{ ProjectId = 'example-slug' }; CurseForge = @{ ProjectId = '12345' } }"
    Set-Content -LiteralPath (Join-Path $fixture 'resource_packs/normal/pack.build.psd1') -Value "@{ MinVersion = '1.13' }"
    $config = @{ PackRoot = 'resource_packs'; PackBuildConfigFile = 'pack.build.psd1'; Versions = @(@{ Id = '1.13'; Enabled = $true }, @{ Id = '1.17'; Enabled = $true }) }
    foreach ($scriptName in @('build-texture-packs.ps1', 'publish-modrinth.ps1', 'publish-curseforge.ps1')) {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "Syntax errors in $scriptName" }
        foreach ($node in $ast.EndBlock.Statements) {
            if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
        }
        $all = @(Get-PackDirectories -RepoRoot $fixture -Config $config)
        if ($all.Count -ne 2 -or 'normal' -notin $all.Name -or 'combined' -notin $all.Name) { throw "Discovery failed in $scriptName" }
        $selected = @(Get-PackDirectories -RepoRoot $fixture -Config $config -RequestedPackNames @('combined'))
        if ($selected.Count -ne 1 -or -not (Get-CombinedDefinitionPath $selected[0])) { throw "Combined selection failed in $scriptName" }
        $options = Get-PackBuildOptions -PackDirectory $selected[0] -Config $config
        if ($options.Modrinth.ProjectId -ne 'example-slug' -or $options.CurseForge.ProjectId -ne '12345') { throw "Publishing options were lost in $scriptName" }
        $versions = @(Get-PackSelectedVersions -PackDirectory $selected[0] -Config $config -GloballySelectedVersions $config.Versions)
        if ($versions.Count -ne 1 -or $versions[0].Id -ne '1.17') { throw "Combined version filtering failed in $scriptName" }
        $normal = $all | Where-Object { $_.Name -eq 'normal' }
        if ((Get-PackBuildOptions -PackDirectory $normal -Config $config).MinVersion -ne '1.13') { throw "Normal options changed in $scriptName" }
        if (@(Get-PackSelectedVersions -PackDirectory $normal -Config $config -GloballySelectedVersions $config.Versions).Count -ne 2) { throw "Normal version filtering changed in $scriptName" }
        if ($scriptName -ne 'build-texture-packs.ps1') {
            $buildRoot = Join-Path $fixture "$scriptName/build/combined"
            $archiveRoot = Join-Path $fixture "$scriptName/archive"
            Ensure-Directory -Path (Join-Path $buildRoot 'reports')
            $item = [pscustomobject]@{ PackName = 'combined'; ReleaseVersion = '1.0.0'; VersionNumber = '1.0.0-mc.1.17'; ZipPath = Join-Path $buildRoot 'combined-1.17.zip' }
            $reportPath = Get-CombinedBuildReportPath -ZipPath $item.ZipPath
            $unrelatedReport = Join-Path $buildRoot 'reports/combined-1.18.report.json'
            Set-Content -LiteralPath $unrelatedReport -Value '{}'
            Set-Content -LiteralPath $item.ZipPath -Value 'test zip content'
            Set-Content -LiteralPath $reportPath -Value '{}'
            $archivePath = Move-UploadedZipToArchive -Item $item -ArchiveRootPath $archiveRoot
            if ((Split-Path $archivePath -Leaf) -ne 'combined-1.0.0-mc1.17.zip') { throw "Wrong archive filename in $scriptName" }
            $item | Add-Member -NotePropertyName MinecraftVersion -NotePropertyValue '1.17'
            $resolvedZip = Resolve-PublishZipPath -Item $item -BuildZipPath $item.ZipPath -ArchiveRootPath $archiveRoot -ConfigPath 'fixture-config.psd1' -ShouldBuildIfMissing $false
            if ($resolvedZip.Source -ne 'archive' -or $resolvedZip.Path -ne $archivePath) { throw "Renamed archive lookup failed in $scriptName" }
            $oldArchivePath = Join-Path (Split-Path $archivePath -Parent) 'combined-1.0.0-mc.1.17.zip'
            Move-Item -LiteralPath $archivePath -Destination $oldArchivePath
            $resolvedZip = Resolve-PublishZipPath -Item $item -BuildZipPath $item.ZipPath -ArchiveRootPath $archiveRoot -ConfigPath 'fixture-config.psd1' -ShouldBuildIfMissing $false
            if ($resolvedZip.Source -ne 'archive' -or $resolvedZip.Path -ne $oldArchivePath) { throw "Legacy archive lookup failed in $scriptName" }
            Move-Item -LiteralPath $oldArchivePath -Destination $archivePath
            if ($scriptName -eq 'publish-curseforge.ps1') {
                $item | Add-Member -NotePropertyName ProjectId -NotePropertyValue '12345'
                $item.VersionNumber = '1.0.0-mc1.17'
                $oldState = @{ Projects = @{ combined = @{ PublishedFiles = @(@{ ProjectId = '12345'; VersionNumber = '1.0.0-mc.1.17' }) } } }
                if (-not (Test-LocalCurseForgeVersionPublished -State $oldState -Item $item)) { throw 'Legacy CurseForge release was not recognized.' }
            }
            if (-not (Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $reportPath)) { throw "Move/report cleanup failed in $scriptName" }
            if (-not (Test-Path -LiteralPath $unrelatedReport)) { throw "Unrelated report removed in $scriptName" }
            # Existing identical archive: remove only the source ZIP and its report.
            Set-Content -LiteralPath $item.ZipPath -Value 'test zip content'
            Set-Content -LiteralPath $reportPath -Value '{}'
            $legacyReport = [IO.Path]::ChangeExtension($item.ZipPath, 'report.json')
            Set-Content -LiteralPath $legacyReport -Value '{}'
            $duplicatePath = Move-UploadedZipToArchive -Item $item -ArchiveRootPath $archiveRoot
            if ($duplicatePath -ne $archivePath -or (Test-Path $item.ZipPath) -or (Test-Path $reportPath) -or (Test-Path $legacyReport)) { throw "Duplicate archive cleanup failed in $scriptName" }
            # Different archived content uses the timestamp fallback and still removes its report.
            Set-Content -LiteralPath $item.ZipPath -Value 'different test zip content'
            Set-Content -LiteralPath $reportPath -Value '{}'
            $changedPath = Move-UploadedZipToArchive -Item $item -ArchiveRootPath $archiveRoot
            if ($changedPath -eq $archivePath -or -not (Test-Path $changedPath) -or (Test-Path $reportPath)) { throw "Archive collision cleanup failed in $scriptName" }
            # A failed archive operation must preserve the report.
            Set-Content -LiteralPath $reportPath -Value '{}'
            $failed = $false
            try { Move-UploadedZipToArchive -Item $item -ArchiveRootPath $archiveRoot | Out-Null } catch { $failed = $true }
            if (-not $failed -or -not (Test-Path $reportPath)) { throw "Failed archive operation removed report in $scriptName" }
        }
    }
    New-Item -ItemType Directory -Path (Join-Path $fixture 'resource_packs/combined') | Out-Null
    $rejected = $false
    try { Get-CombinedPackDirectories -RepoRoot $fixture -Config $config | Out-Null } catch { $rejected = $_.Exception.Message -like '*conflicts with a normal pack*' }
    if (-not $rejected) { throw 'Duplicate combined/normal names were accepted.' }
    Write-Output 'Passed discovery, publish options, version filters, duplicate names, archive report cleanup, identical/different archives, unrelated report preservation, and failed-move report retention for both publishers.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'combined-discovery-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
