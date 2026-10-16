[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
. (Join-Path $PSScriptRoot 'combined-pack-dependencies.ps1')

foreach ($scriptName in @('build-texture-packs.ps1', 'build-combined-pack.ps1')) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Syntax errors in $scriptName" }
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Expected)
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Expected*") { throw }
        return
    }
    throw "Expected rejection: $Expected"
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $tempRoot ('combined-pack-test-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory $fixture
try {
    $definition = @{ Name = 'combined'; DisplayName = 'Combined'; Packs = @(
        @{ Name = 'carpets'; Enabled = $true; Priority = 80 }
        @{ Name = 'moss'; Enabled = $true; Priority = 100 }
        @{ Name = 'disabled'; Enabled = $false; Priority = 200 }
    ); Exclude = @('assets/minecraft/textures/block/removed.png') }
    Assert-CombinedDefinition -Definition $definition -AvailablePacks @('carpets', 'moss', 'disabled')
    $bad = @{} + $definition
    $bad.Packs = @(@{ Name = 'missing'; Enabled = $true; Priority = 1 })
    Assert-Rejected { Assert-CombinedDefinition $bad @('carpets') } 'Unknown source pack'
    $bad.Packs = @($definition.Packs[0], $definition.Packs[0])
    Assert-Rejected { Assert-CombinedDefinition $bad @('carpets') } 'Duplicate source pack'
    $bad.Packs = @(@{ Name = 'carpets'; Enabled = $false; Priority = 1 })
    Assert-Rejected { Assert-CombinedDefinition $bad @('carpets') } 'Enable at least one'

    foreach ($pack in @('carpets', 'moss')) {
        $source = Join-Path $fixture $pack
        $models = Join-Path $source 'assets/minecraft/models/block'
        Ensure-Directory $models
        Set-Content (Join-Path $models 'moss_carpet.json') ('{"owner":"' + $pack + '"}')
        Set-Content (Join-Path $models "$pack.json") '{}'
        Set-Content (Join-Path $source 'pack.mcmeta') '{}'
        Set-Content (Join-Path $source 'pack.png') 'icon'
        $textures = Join-Path $source 'assets/minecraft/textures/block'
        Ensure-Directory $textures
        Set-Content (Join-Path $textures 'removed.png') 'removed'
        New-ZipFromDirectory $source (Join-Path $fixture "$pack.zip")
    }
    # Archive selection is numeric, target-version-specific, and compatible with old names.
    foreach ($release in @('1.2.0', '1.10.0', '2.0.0')) { Ensure-Directory (Join-Path $fixture "archive/moss/$release") }
    Copy-Item (Join-Path $fixture 'moss.zip') (Join-Path $fixture 'archive/moss/1.2.0/moss-1.2.0-mc1.17.zip')
    Copy-Item (Join-Path $fixture 'moss.zip') (Join-Path $fixture 'archive/moss/1.10.0/moss-1.10.0-mc.1.17.zip')
    Copy-Item (Join-Path $fixture 'moss.zip') (Join-Path $fixture 'archive/moss/2.0.0/moss-2.0.0-mc1.17.1.zip')
    $archived = Get-CombinedArchivedComponent $fixture 'moss' '1.17'
    if ($archived.ReleaseVersion -ne '1.10.0' -or $archived.ZipPath -notlike '*mc.1.17.zip') { throw 'Wrong archived version selected.' }
    if ($null -ne (Get-CombinedArchivedComponent $fixture 'moss' '1.18')) { throw 'Missing target archive did not allow source fallback.' }
    $collision = Join-Path $fixture 'archive/moss/1.10.0/moss-1.10.0-mc1.17-uploaded-20261014000000.zip'
    Copy-Item (Join-Path $fixture 'moss.zip') $collision
    (Get-Item $collision).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(1)
    if ((Get-CombinedArchivedComponent $fixture 'moss' '1.17').ZipPath -ne $collision) { throw 'Newest archived collision copy was not selected.' }
    $validation = @{ RequireLowercasePaths = $true; ParseJsonFiles = $true; ParseMcmetaFiles = $true; RequireTextureForTextureMcmeta = $true }
    $targetVersion = @{ Id = '1.17'; Required = @('pack.mcmeta', 'assets/minecraft/models/') }
    $archivedComponent = Read-CombinedComponent -ZipPath $collision -Entry $definition.Packs[1] -Definition $definition -Root (Join-Path $fixture 'archived-input') -Validation $validation -VersionConfig $targetVersion
    $targetVersion.Required = @('assets/missing/')
    Assert-Rejected { Read-CombinedComponent -ZipPath $collision -Entry $definition.Packs[1] -Definition $definition -Root (Join-Path $fixture 'invalid-input') -Validation $validation -VersionConfig $targetVersion } 'Required output rule missing'
    $targetVersion.Required = @('pack.mcmeta')
    $badSource = Join-Path $fixture 'moss/assets/minecraft/models/block/moss_carpet.json'
    $originalModel = [IO.File]::ReadAllText($badSource)
    Set-Content $badSource '{broken'
    New-ZipFromDirectory (Join-Path $fixture 'moss') (Join-Path $fixture 'invalid.zip')
    Assert-Rejected { Read-CombinedComponent -ZipPath (Join-Path $fixture 'invalid.zip') -Entry $definition.Packs[1] -Definition $definition -Root (Join-Path $fixture 'invalid-json') -Validation $validation -VersionConfig $targetVersion } 'Invalid JSON in component'
    [IO.File]::WriteAllText($badSource, $originalModel)
    $merged = Join-Path $fixture 'merged'
    Ensure-Directory $merged
    $owners = @{}
    Merge-CombinedArchive (Join-Path $fixture 'carpets.zip') $definition.Packs[0] $definition $merged $owners
    Merge-CombinedArchive (Join-Path $fixture 'moss.zip') $definition.Packs[1] $definition $merged $owners
    $conflictPath = 'assets/minecraft/models/block/moss_carpet.json'
    if ($owners[$conflictPath].Pack -ne 'moss') { throw 'Higher priority did not win.' }
    if ((Get-Content (Join-Path $merged $conflictPath) -Raw | ConvertFrom-Json).owner -ne 'moss') { throw 'Wrong file content copied.' }
    if (-not $owners.ContainsKey('assets/minecraft/models/block/carpets.json')) { throw 'Unique lower-priority asset lost.' }
    if (Test-Path (Join-Path $merged 'pack.png')) { throw 'Component icon leaked into combined output.' }
    if ($owners.ContainsKey('assets/minecraft/textures/block/removed.png')) { throw 'Global exclusion ignored.' }
    $extractedMerge = Join-Path $fixture 'extracted-merge'
    Ensure-Directory $extractedMerge
    $extractedOwners = @{}
    Merge-CombinedArchive -Entry $definition.Packs[1] -Definition $definition -Destination $extractedMerge -Owners $extractedOwners -Component $archivedComponent
    foreach ($path in $archivedComponent.Included.Keys) {
        if ((Get-FileHash (Join-Path $merged $path)).Hash -ne (Get-FileHash (Join-Path $extractedMerge $path)).Hash) { throw 'Extract-once merge changed archive bytes.' }
    }
    # Merge order must not change priority resolution.
    $reverse = Join-Path $fixture 'reverse'
    Ensure-Directory $reverse
    $reverseOwners = @{}
    Merge-CombinedArchive (Join-Path $fixture 'moss.zip') $definition.Packs[1] $definition $reverse $reverseOwners
    Merge-CombinedArchive (Join-Path $fixture 'carpets.zip') $definition.Packs[0] $definition $reverse $reverseOwners
    if ($reverseOwners[$conflictPath].Pack -ne 'moss') { throw 'Merge order changed the winner.' }
    $equal = @{ Name = 'other'; Enabled = $true; Priority = 100 }
    Assert-Rejected { Merge-CombinedArchive (Join-Path $fixture 'moss.zip') $equal $definition $merged $owners } 'Equal priority conflict'
    $selective = @{ Include = @('assets/minecraft/models/'); Exclude = @('*moss_carpet.json') }
    if (Test-CombinedPath $conflictPath $selective $definition) { throw 'Per-pack exclusion ignored.' }
    if (-not (Test-CombinedPath 'assets/minecraft/models/block/carpets.json' $selective $definition)) { throw 'Directory inclusion ignored.' }
    if (Test-CombinedPath 'assets/minecraft/textures/block/test.png' $selective $definition) { throw 'Include allow-list ignored.' }
    if (Test-CombinedPath $conflictPath @{ Include = @() } $definition) { throw 'Empty Include was ignored.' }
    # Archived components must not hide newly synchronized compatibility assets.
    $compatRoot = Join-Path $fixture 'compatibility-source'
    Ensure-Directory (Join-Path $compatRoot 'assets/demo/models/block')
    $compatModel = Join-Path $compatRoot 'assets/demo/models/block/ore.json'
    Set-Content $compatModel '{"textures":{"all":"demo:block/ore"}}'
    Set-Content (Join-Path $compatRoot 'compatibility.txt') 'demo'
    $compatConfig = @{ CanonicalAssetsFolder = 'assets'; AutoSortFolder = 'drop'; AutoSortMappings = @(); PackBuildConfigFile = 'pack.build.psd1'; Versions = @(@{ Id = '1.17' }, @{ Id = '1.18' }) }
    $compatOptions = @{ Compatibility = @{ demo = @{ Versions = @('1.17'); Support = 'Includes demo ores.' } } }
    $compatArchive = Join-Path $fixture 'compatibility.zip'
    New-ZipFromDirectory $compatRoot $compatArchive
    $compatDirectory = Get-Item $compatRoot
    if (-not (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.17' } $compatOptions)) { throw 'Matching archived compatibility was not reused.' }
    if (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.18' } $compatOptions) { throw 'Incompatible archived mod files were accepted.' }
    Set-Content $compatModel '{"textures":{"all":"demo:block/new_ore"}}'
    if (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.17' } $compatOptions) { throw 'Stale archived mod assets were accepted.' }
    New-ZipFromDirectory $compatRoot $compatArchive
    Set-Content (Join-Path $compatRoot 'assets/demo/models/block/new_ore.json') '{}'
    if (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.17' } $compatOptions) { throw 'Archive missing newly compatible assets was accepted.' }
    Remove-Item (Join-Path $compatRoot 'assets/demo/models/block/new_ore.json')
    Set-Content (Join-Path $compatRoot 'compatibility.txt') 'Old support notes'
    New-ZipFromDirectory $compatRoot $compatArchive
    if (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.17' } $compatOptions) { throw 'Stale archived support notes were accepted.' }
    if (-not (Test-CombinedArchivedCompatibility $compatArchive $compatDirectory $compatConfig @{ Id = '1.17' } @{})) { throw 'Ordinary archive reuse changed.' }
    Write-Output 'Passed archive selection/validation, merge conflicts, exclusions, metadata isolation, and detection of stale/missing/incompatible archived mod assets and support notes.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($tempRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'combined-pack-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
