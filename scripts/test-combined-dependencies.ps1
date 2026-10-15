[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
. (Join-Path $PSScriptRoot 'combined-pack-dependencies.ps1')
foreach ($scriptName in @('build-texture-packs.ps1', 'build-combined-pack.ps1')) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Syntax errors in $scriptName" }
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
}
function Write-FixtureAsset {
    param([hashtable]$Component, [string]$Root, [string]$Path, [string]$Content)
    $file = Join-Path $Root $Path
    Ensure-Directory (Split-Path $file -Parent)
    Set-Content -LiteralPath $file -Value $Content -Encoding UTF8
    $Component.Files[$Path] = $file
    $Component.Included[$Path] = $true
}
function Invoke-FixtureCombine {
    param([hashtable]$Components, [hashtable]$Vanilla, [string]$Root)
    $output = Join-Path $Root ([Guid]::NewGuid().ToString('N'))
    Ensure-Directory $output
    $owners = @{}
    foreach ($pack in $Components.Keys) {
        foreach ($path in $Components[$pack].Included.Keys) {
            if (-not $owners.ContainsKey($path) -or $owners[$path].Priority -lt $Components[$pack].Entry.Priority) {
                $destination = Join-Path $output $path
                Ensure-Directory (Split-Path $destination -Parent)
                Copy-Item -LiteralPath $Components[$pack].Files[$path] -Destination $destination -Force
                $owners[$path] = @{ Pack = $pack; Priority = $Components[$pack].Entry.Priority }
            }
        }
    }
    $result = Complete-CombinedDependencies -Name 'combined' -Components $Components -Vanilla $Vanilla -Destination $output -Owners $owners
    return @{ Root = $output; Owners = $owners; Result = $result }
}
function Assert-DependencyRejected {
    param([scriptblock]$Action, [string]$Expected)
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notlike "*$Expected*") { throw }; return }
    throw "Expected rejection: $Expected"
}
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('combined-dependencies-test-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory $fixture
try {
    $dependencyCache = Join-Path $fixture 'vanilla-cache/dependency-data'
    Ensure-Directory $dependencyCache
    $cachedFixture = @{ Version = '1.17'; Paths = @{ 'assets/minecraft/blockstates/test.json' = $true }; JsonAssets = @{ 'assets/minecraft/blockstates/test.json' = '{"variants":{"":{"model":"minecraft:block/test"}}}' } }
    $cachedFixture | ConvertTo-Json -Depth 5 -Compress | Set-Content (Join-Path $dependencyCache '1.17.json') -Encoding UTF8
    $cachedDependencies = Get-CombinedVanillaDependencies -RepoRoot $fixture -Config @{ VanillaCatalogCacheRoot = 'vanilla-cache' } -VersionConfig @{ Id = '1.17' }
    if (-not $cachedDependencies.Paths.ContainsKey('assets/minecraft/blockstates/test.json') -or -not (ConvertFrom-CombinedJson $cachedDependencies.JsonAssets['assets/minecraft/blockstates/test.json']).variants.ContainsKey('')) { throw 'Native vanilla cache loading lost paths or empty variant keys.' }
    $low = @{ Entry = @{ Name = 'low'; Priority = 10 }; Files = @{}; Included = @{} }
    $high = @{ Entry = @{ Name = 'high'; Priority = 20 }; Files = @{}; Included = @{} }
    $components = @{ low = $low; high = $high }
    $statePath = 'assets/minecraft/blockstates/moss_carpet.json'
    $sharedPath = 'assets/minecraft/models/block/shared.json'
    $texturePath = 'assets/minecraft/textures/block/shared.png'
    $cubePath = 'assets/minecraft/models/block/cube.json'
    $stateJson = '{"variants":{"":{"model":"minecraft:block/shared"}}}'
    $lowJson = @'
{
  "parent": "minecraft:block/cube",
  "textures": { "all": "minecraft:block/shared" },
  "owner": "low"
}
'@
    $highJson = '{"parent":"minecraft:block/cube","textures":{"all":"minecraft:block/shared"},"owner":"high"}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') $statePath $stateJson
    Write-FixtureAsset $high (Join-Path $fixture 'high') $statePath $stateJson
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath $lowJson
    Write-FixtureAsset $high (Join-Path $fixture 'high') $sharedPath $highJson
    Write-FixtureAsset $low (Join-Path $fixture 'low') $texturePath 'low pixels'
    Write-FixtureAsset $high (Join-Path $fixture 'high') $texturePath 'high pixels'
    # Root notices survive component extraction and are packaged alongside the repo license.
    Set-Content -LiteralPath (Join-Path $fixture 'low/CREDITS.txt') -Value 'Original texture credits'
    Set-Content -LiteralPath (Join-Path $fixture 'low/pack.mcmeta') -Value '{"pack":{"author":"Fixture Artist","credits":["Original modeller","Texture contributor"]}}'
    Set-Content -LiteralPath (Join-Path $fixture 'low/LICENSE.txt') -Value 'Original texture license'
    $noticeZip = Join-Path $fixture 'notices.zip'
    New-ZipFromDirectory -SourceDirectory (Join-Path $fixture 'low') -DestinationPath $noticeZip
    $noticeComponent = Read-CombinedComponent -ZipPath $noticeZip -Entry $low.Entry -Definition @{ Exclude = @() } -Root (Join-Path $fixture 'notice-input')
    $ownDocs = Join-Path $fixture 'own-docs'
    $documentOutput = Join-Path $fixture 'document-output'
    Ensure-Directory $ownDocs
    Ensure-Directory $documentOutput
    Set-Content -LiteralPath (Join-Path $ownDocs 'credits.txt') -Value 'Combined credits'
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'LICENSE') -Destination (Join-Path $fixture 'LICENSE')
    foreach ($release in @('1.1.0', '1.2.0', '1.10.0', '9.0.0')) {
        $releaseRoot = Join-Path $fixture "archive/low/$release"
        Ensure-Directory $releaseRoot
        if ($release -ne '9.0.0') { Set-Content -LiteralPath (Join-Path $releaseRoot 'low.zip') -Value 'archived ZIP placeholder' }
    }
    $documentationVersions = Copy-CombinedPackDocumentation -RepoRoot $fixture -DefinitionDirectory $ownDocs -Destination $documentOutput -Components @{ low = $noticeComponent; no_archive = @{ Notices = @{} } } -MinecraftVersion 'fixture' -Description 'A player-friendly pack description.'
    if ($documentationVersions.low -ne '1.10.0' -or $documentationVersions.no_archive -ne 'unreleased') { throw 'Latest archived release selection failed.' }
    if ((Get-FileHash (Join-Path $fixture 'LICENSE')).Hash -ne (Get-FileHash (Join-Path $documentOutput 'license.txt')).Hash) { throw 'Repository license was not copied verbatim.' }
    $combinedCredits = Get-Content (Join-Path $documentOutput 'credits.txt') -Raw
    if ($combinedCredits -match 'Combined credits|Fixture Artist|Original modeller|Texture contributor|DoomedArtemis' -or $combinedCredits -notmatch 'low:\s+Original texture credits' -or $combinedCredits -match 'no_archive:') { throw 'Automatic credit sections were not merged correctly.' }
    if ((Get-Content (Join-Path $documentOutput 'licenses/low.txt') -Raw).Trim() -ne 'Original texture license') { throw 'Component legal notices were lost.' }
    $readme = Get-Content (Join-Path $documentOutput 'readme.txt') -Raw
    if ($readme -notmatch 'Low: 1\.10\.0' -or $readme -notmatch 'No Archive: unreleased' -or $readme -notmatch 'For Minecraft Java Edition fixture') { throw 'README is missing component versions or target Minecraft version.' }
    if ($readme -notmatch 'A player-friendly pack description\.' -or $readme -notmatch 'Options > Resource Packs > Open Pack Folder') { throw 'Player description or installation instructions are missing.' }
    if ($readme -match '\bsource packs\b|archive folders|resource-packs-manager|build report|automatically|versioned archive') { throw 'Player README contains build-system details.' }
    foreach ($release in @('1.2.0-beta.2', '1.2.0-beta.10', '1.2.0')) {
        $releaseRoot = Join-Path $fixture "archive/preview/$release"
        Ensure-Directory $releaseRoot
        Set-Content -LiteralPath (Join-Path $releaseRoot 'preview.zip') -Value 'archived ZIP placeholder'
    }
    if ((Get-LatestArchivedPackVersion $fixture 'preview') -ne '1.2.0') { throw 'Stable release did not sort above prereleases.' }
    Remove-Item -LiteralPath (Join-Path $fixture 'archive/preview/1.2.0/preview.zip')
    if ((Get-LatestArchivedPackVersion $fixture 'preview') -ne '1.2.0-beta.10') { throw 'Numeric prerelease identifiers were sorted incorrectly.' }
    $documentZip = Join-Path $fixture 'documents.zip'
    New-ZipFromDirectory -SourceDirectory $documentOutput -DestinationPath $documentZip
    $documentArchive = [IO.Compression.ZipFile]::OpenRead($documentZip)
    try {
        foreach ($path in @('credits.txt', 'readme.txt', 'license.txt', 'licenses/low.txt')) { if (-not $documentArchive.GetEntry($path)) { throw "Missing documentation ZIP entry: $path" } }
        if ($documentArchive.GetEntry('credits/low/CREDITS.txt')) { throw 'Credits were duplicated into separate component files.' }
    }
    finally { $documentArchive.Dispose() }
    # Metadata alone must never generate credits for our own work.
    $automaticDocs = Join-Path $fixture 'automatic-docs'
    Ensure-Directory $automaticDocs
    Remove-Item -LiteralPath (Join-Path $fixture 'low/CREDITS.txt')
    New-ZipFromDirectory -SourceDirectory (Join-Path $fixture 'low') -DestinationPath (Join-Path $fixture 'metadata-only.zip')
    $metadataComponent = Read-CombinedComponent -ZipPath (Join-Path $fixture 'metadata-only.zip') -Entry $low.Entry -Definition @{ Exclude = @() } -Root (Join-Path $fixture 'metadata-input')
    $null = Copy-CombinedPackDocumentation -RepoRoot $fixture -DefinitionDirectory $automaticDocs -Destination $automaticDocs -Components @{ low = $metadataComponent } -DisplayName 'Artemis Enhanced Visuals'
    $automaticCredits = Get-Content (Join-Path $automaticDocs 'credits.txt') -Raw
    if (-not [string]::IsNullOrWhiteSpace($automaticCredits)) { throw 'Metadata generated unwanted author credits.' }
    # Multiple notices from the same pack stay flat and retain their exact contents.
    Set-Content -LiteralPath (Join-Path $fixture 'low/NOTICE.txt') -Value 'Additional attribution notice'
    New-ZipFromDirectory -SourceDirectory (Join-Path $fixture 'low') -DestinationPath (Join-Path $fixture 'multiple-notices.zip')
    $multipleComponent = Read-CombinedComponent -ZipPath (Join-Path $fixture 'multiple-notices.zip') -Entry $low.Entry -Definition @{ Exclude = @() } -Root (Join-Path $fixture 'multiple-input')
    $multipleDocs = Join-Path $fixture 'multiple-docs'
    Ensure-Directory $multipleDocs
    $null = Copy-CombinedPackDocumentation -RepoRoot $fixture -DefinitionDirectory $ownDocs -Destination $multipleDocs -Components @{ low = $multipleComponent }
    foreach ($name in @('LICENSE.txt', 'NOTICE.txt')) {
        if ((Get-FileHash (Join-Path $fixture "low/$name")).Hash -ne (Get-FileHash (Join-Path $multipleDocs "licenses/low-$name")).Hash) { throw 'Flat license notices lost content.' }
    }
    if (@(Get-ChildItem (Join-Path $multipleDocs 'licenses') -Directory).Count) { throw 'License subdirectories were generated.' }
    Write-FixtureAsset $low (Join-Path $fixture 'low') "$texturePath.mcmeta" '{"animation":{}}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/blockstates/other.json' '{"multipart":[{"apply":[{"model":"demo:block/child"}]}]}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/models/block/child.json' '{"parent":"minecraft:block/shared"}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/models/item/widget.json' '{"parent":"demo:block/child","overrides":[{"predicate":{"custom_model_data":1},"model":"demo:item/alternative"}]}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/models/item/alternative.json' '{"parent":"demo:block/child"}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/items/widget.json' '{"model":{"type":"minecraft:model","model":"demo:item/widget"}}'
    $vanilla = @{ Version = 'fixture'; Paths = @{ $statePath = $true; $cubePath = $true; $sharedPath = $true }; JsonAssets = @{
        $statePath = $stateJson; $cubePath = '{"elements":[{"faces":{"north":{"texture":"#all"}}}]}'; $sharedPath = '{"parent":"minecraft:block/cube"}'
    } }
    $result = Invoke-FixtureCombine $components $vanilla $fixture
    if ($result.Owners[$statePath].Pack -ne 'high') { throw 'Blockstate priority ignored.' }
    $state = ConvertFrom-CombinedJson (Get-Content (Join-Path $result.Root $statePath) -Raw)
    $winnerModel = Convert-CombinedResourcePath $state.variants[''].model 'models'
    $winner = Get-Content (Join-Path $result.Root $winnerModel) -Raw | ConvertFrom-Json
    if ($winner.owner -ne 'high') { throw 'Winning state got the wrong model.' }
    if ($state.variants[''] -is [array]) { throw 'Variant object shape was changed.' }
    $other = Get-Content (Join-Path $result.Root 'assets/demo/blockstates/other.json') -Raw | ConvertFrom-Json
    if ($other.multipart -isnot [array] -or $other.multipart[0].apply -isnot [array]) { throw 'Singleton multipart/apply arrays were collapsed.' }
    $childPath = Convert-CombinedResourcePath $other.multipart[0].apply[0].model 'models'
    $child = Get-Content (Join-Path $result.Root $childPath) -Raw | ConvertFrom-Json
    $parentPath = Convert-CombinedResourcePath $child.parent 'models'
    $parent = Get-Content (Join-Path $result.Root $parentPath) -Raw | ConvertFrom-Json
    if ($parent.owner -ne 'high' -or $parentPath -ne $winnerModel) { throw 'Lower-priority block parent bypassed the winning model.' }
    $winningTexture = Convert-CombinedResourcePath $parent.textures.all 'textures'
    if ($winningTexture -ne $texturePath -or (Get-Content (Join-Path $result.Root $winningTexture) -Raw).Trim() -ne 'high pixels') { throw 'Winning texture was not used by the lower-priority block.' }
    if (Test-Path (Join-Path $result.Root "$texturePath.mcmeta")) { throw 'Low-priority animation metadata leaked onto the high-priority texture.' }
    if ((Get-Content (Join-Path $result.Root $parentPath) -Raw) -cne (Get-Content $high.Files[$sharedPath] -Raw)) { throw 'Winning JSON formatting was changed.' }
    if ($result.Owners.Keys | Where-Object { $_ -like '*/pack_dependencies/*' }) { throw 'Overridden assets were preserved as private dependencies.' }
    $orphanPath = 'assets/combined/models/pack_dependencies/low/minecraft/block/orphan.json'
    Ensure-Directory (Split-Path (Join-Path $result.Root $orphanPath) -Parent)
    Set-Content (Join-Path $result.Root $orphanPath) '{}'
    $result.Owners[$orphanPath] = @{ Pack = 'low'; Priority = 10 }
    Remove-UnusedCombinedDependencyCopies -Name 'combined' -Destination $result.Root -Owners $result.Owners
    if (Test-Path (Join-Path $result.Root $orphanPath)) { throw 'Unreferenced dependency copy was not pruned.' }
    if (-not (Test-Path (Join-Path $result.Root $parentPath))) { throw 'Required parent dependency was pruned.' }
    $item = Get-Content (Join-Path $result.Root 'assets/demo/items/widget.json') -Raw | ConvertFrom-Json
    $itemPath = Convert-CombinedResourcePath $item.model.model 'models'
    $itemModel = Get-Content (Join-Path $result.Root $itemPath) -Raw | ConvertFrom-Json
    $itemParentPath = Convert-CombinedResourcePath $itemModel.parent 'models'
    $itemParent = Get-Content (Join-Path $result.Root $itemParentPath) -Raw | ConvertFrom-Json
    if ((Convert-CombinedResourcePath $itemParent.parent 'models') -ne $winnerModel) { throw 'Inventory parent did not use the higher-priority model.' }
    $overridePath = Convert-CombinedResourcePath $itemModel.overrides[0].model 'models'
    if (-not (Test-Path (Join-Path $result.Root $overridePath)) -or $itemModel.overrides -isnot [array]) { throw 'Item definition/override dependencies were lost.' }
    Write-FixtureAsset $high (Join-Path $fixture 'high') $statePath '{"variants":{"": [{"model":"minecraft:block/shared","weight":1},{"model":"minecraft:block/shared","weight":2}]}}'
    $weighted = Invoke-FixtureCombine $components $vanilla $fixture
    $weightedState = ConvertFrom-CombinedJson (Get-Content (Join-Path $weighted.Root $statePath) -Raw)
    if ($weightedState.variants[''] -isnot [array] -or $weightedState.variants[''].Count -ne 2) { throw 'Weighted variant arrays were changed.' }
    Write-FixtureAsset $high (Join-Path $fixture 'high') $statePath $stateJson
    $longLocation = Get-CombinedPrivateLocation @{ Name = 'combined' } 'low' ('assets/minecraft/models/block/' + ('deep/' * 20) + 'very_long_model.json')
    if ($longLocation.Path -notlike '*/pack_dependencies/low/minecraft/block/deep/*/very_long_model.json') { throw 'Long model names were not preserved.' }
    # A model-only pack participates through the target version's vanilla blockstate.
    $high.Files.Remove($statePath); $high.Included.Remove($statePath)
    $implicit = Invoke-FixtureCombine $components $vanilla $fixture
    if (-not $implicit.Result.Blockstates[$statePath].Implicit -or $implicit.Result.Blockstates[$statePath].Pack -ne 'high') { throw 'Implicit vanilla state priority ignored.' }
    $high.Entry.Priority = 5
    $explicitWinner = Invoke-FixtureCombine $components $vanilla $fixture
    if ($explicitWinner.Result.Blockstates[$statePath].Implicit -or $explicitWinner.Result.Blockstates[$statePath].Pack -ne 'low') { throw 'Higher-priority explicit state did not win over a model-only pack.' }
    $high.Entry.Priority = 20
    # Once the winning files are absent, remaining dependencies must still be validated.
    $high.Files.Remove($sharedPath); $high.Included.Remove($sharedPath)
    $high.Files.Remove($texturePath); $high.Included.Remove($texturePath)
    # A required file filtered out by the configuration must never silently fall back.
    $low.Included.Remove($sharedPath)
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Excluded dependency'
    $low.Included[$sharedPath] = $true
    $low.Included.Remove($texturePath)
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Excluded dependency'
    $low.Included[$texturePath] = $true
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"parent":"minecraft:block/missing"}'
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Missing dependency'
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"parent":"demo:block/child"}'
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Model dependency cycle'
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"parent":"minecraft:block/cube","textures":{"all":"#missing"}}'
    $missingVariable = Invoke-FixtureCombine $components $vanilla $fixture
    if ($missingVariable.Result.Status -ne 'passed_with_warnings' -or @($missingVariable.Result.TextureWarnings | Where-Object { $_.Type -eq 'UnresolvedTextureVariable' -and $_.Reference -eq '#missing' }).Count -eq 0) { throw 'Missing texture variable did not become a report warning.' }
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"parent":"minecraft:block/cube","textures":{"all":"#second","second":"#all"}}'
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Texture variable cycle'
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"parent":"minecraft:block/cube","textures":{"all":"minecraft:block/missing"}}'
    $missingTexture = Invoke-FixtureCombine $components $vanilla $fixture
    if (@($missingTexture.Result.TextureWarnings | Where-Object { $_.Type -eq 'MissingTexture' -and $_.Reference -eq 'assets/minecraft/textures/block/missing.png' }).Count -eq 0) { throw 'Missing texture file did not become a report warning.' }
    $missingTextureModelPath = $sharedPath
    $originalModel = Get-Content (Join-Path $missingTexture.Root $missingTextureModelPath) -Raw | ConvertFrom-Json
    if ($originalModel.textures.all -ne 'minecraft:block/missing') { throw 'Missing texture reference was modified.' }
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath $lowJson
    $low.Included.Remove('assets/demo/models/item/alternative.json')
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Excluded dependency'
    $low.Included['assets/demo/models/item/alternative.json'] = $true
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/models/item/alternative.json' '{"parent":"minecraft:block/cube","textures":{"all":"#missing"}}'
    $missingItemTexture = Invoke-FixtureCombine $components $vanilla $fixture
    if (@($missingItemTexture.Result.TextureWarnings | Where-Object { $_.Type -eq 'UnresolvedTextureVariable' }).Count -eq 0) { throw 'Missing item texture was not recorded as a warning.' }
    Write-FixtureAsset $low (Join-Path $fixture 'low') 'assets/demo/models/item/alternative.json' '{"parent":"demo:block/child"}'
    # Identical shared assets need no alternate files, even with different JSON formatting/order.
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath '{"owner":"high","textures":{"all":"minecraft:block/shared"},"parent":"minecraft:block/cube"}'
    Write-FixtureAsset $low (Join-Path $fixture 'low') $texturePath 'high pixels'
    $low.Files.Remove("$texturePath.mcmeta"); $low.Included.Remove("$texturePath.mcmeta")
    $identicalAssets = Invoke-FixtureCombine $components $vanilla $fixture
    if ($identicalAssets.Owners.Keys | Where-Object { $_ -like 'assets/combined/models/pack_dependencies/*' -or $_ -like 'assets/combined/textures/block/pack_dependencies/*' }) { throw 'Identical shared assets were copied unnecessarily.' }
    Write-FixtureAsset $low (Join-Path $fixture 'low') $sharedPath $lowJson
    $vanilla.Paths.Remove($cubePath); $vanilla.JsonAssets.Remove($cubePath)
    Assert-DependencyRejected { Invoke-FixtureCombine $components $vanilla $fixture } 'Missing dependency'
    Write-Output 'Passed dependency checks, readable names, original JSON formatting, canonical reuse, identical-asset reuse, unused-copy pruning, credits, licenses, and README packaging.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'combined-dependencies-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
