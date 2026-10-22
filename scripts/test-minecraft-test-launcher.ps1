[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('minecraft-test-launcher-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture/scripts", "$fixture/resource_packs/example/assets/minecraft/textures/block", "$fixture/app/profiles/Legacy Profile", "$fixture/app/profiles/Other Profile" -Force | Out-Null
try {
    foreach ($name in @('test-resource-pack-in-minecraft.ps1', 'modrinth-test-profiles.cjs', 'minecraft-test-loaders.ps1', 'minecraft-test-shaders.ps1', 'minecraft-test-pack-dependencies.ps1', 'build-texture-packs.ps1', 'combined-pack-support.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination "$fixture/scripts/$name"
    }
    # Fixture profiles never run Minecraft. Keep transport and process checks local.
    $launcherPath = "$fixture/scripts/test-resource-pack-in-minecraft.ps1"
    $source = [IO.File]::ReadAllText($launcherPath)
    $marker = '$repoRoot = Split-Path $PSScriptRoot -Parent'
    $stubs = 'function Assert-MinecraftTestProfileStopped { param($Directory) }' + "`r`n" + 'function Start-Process { param($FilePath) [IO.File]::WriteAllText((Join-Path $PSScriptRoot ../launch.txt), $FilePath) }'
    $stubs += @'

function Initialize-MinecraftTestEnvironment {
    param($ProfileDirectory, $PackOptions, $Config, $PackName, $MinecraftVersion, $LoaderId, [switch]$SkipShaders, [switch]$DryRun)
    if (-not $DryRun -and $ProfileDirectory) { [IO.File]::WriteAllText((Join-Path $ProfileDirectory 'shader-setup-fixture.txt'), $LoaderId) }
}

function Start-MinecraftTestProfileImport {
    param($ImportPath)
    $archive = [IO.Compression.ZipFile]::OpenRead($ImportPath)
    try {
        if ($archive.Entries.Count -ne 1) { throw 'Profile import must contain only the index.' }
        $reader = [IO.StreamReader]::new($archive.GetEntry('modrinth.index.json').Open())
        try { $index = ConvertFrom-Json -InputObject $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($index.formatVersion -ne 1 -or $index.files.Count -ne 0 -or $index.game -ne 'minecraft') { throw 'Invalid profile import.' }
    } finally { $archive.Dispose() }
    $importLoader = 'vanilla'
    foreach ($pair in @(@('fabric-loader','fabric'), @('neoforge','neoforge'), @('forge','forge'))) {
        if ($index.dependencies.PSObject.Properties[$pair[0]]) { $importLoader = $pair[1] }
    }
    & node --no-warnings (Join-Path $PSScriptRoot 'simulate-profile-import.cjs') (Join-Path $PSScriptRoot '../app') $index.name $index.dependencies.minecraft $importLoader
    if ($LASTEXITCODE) { throw 'Fixture profile import failed.' }
}
'@
    $metadataStub = @'

function Get-MinecraftLoaderMetadata {
    param($Kind)
    if ($Kind -eq 'fabric-games') { return [pscustomobject]@{ version = '1.21.1' } }
    $gameId = if ($Kind -eq 'fabric') { '${modrinth.gameVersion}' } else { '1.21.1' }
    $version = switch ($Kind) { fabric { '0.16.0' }; neoforge { '21.1.42' }; forge { '52.0.0' } }
    return [pscustomobject]@{ gameVersions = @([pscustomobject]@{ id = $gameId; stable = $true; loaders = @([pscustomobject]@{ id = $version; stable = $true }) }) }
}
'@
    $stubs += $metadataStub
    [IO.File]::WriteAllText($launcherPath, $source.Replace($marker, $stubs + "`r`n" + $marker))
    @'
const {DatabaseSync}=require('node:sqlite'); const fs=require('node:fs'); const path=require('node:path');
const [root,name,version,loader]=process.argv.slice(2); const db=new DatabaseSync(path.join(root,'app.db'));
const id=loader==='vanilla'?'local:created-'+version:'local:created-'+loader+'-'+version; const content='content-'+loader+'-'+version;
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run(id,name,name,content,'installed');
db.prepare('INSERT INTO instance_content_sets VALUES (?, ?, ?)').run(content,version,loader);
fs.mkdirSync(path.join(root,'profiles',name),{recursive:true}); db.close();
'@ | Set-Content -LiteralPath "$fixture/scripts/simulate-profile-import.cjs"
    @'
const {DatabaseSync}=require('node:sqlite');
const path=require('node:path');
const root=process.argv[2];
const db=new DatabaseSync(path.join(root,'app.db'));
db.exec(`CREATE TABLE settings(custom_dir TEXT);
CREATE TABLE instances(id TEXT, name TEXT, path TEXT, applied_content_set_id TEXT, install_stage TEXT);
CREATE TABLE instance_content_sets(id TEXT, game_version TEXT, loader TEXT);
CREATE TABLE instance_groups(id TEXT PRIMARY KEY, name TEXT, display_order INTEGER);
CREATE TABLE instance_group_memberships(instance_id TEXT, group_id TEXT, PRIMARY KEY(instance_id, group_id));
INSERT INTO instance_groups VALUES ('personal', 'Personal', 0), ('vanilla-group', 'Vanilla', 1);
INSERT INTO instance_group_memberships VALUES ('local:legacy id', 'personal'), ('local:legacy id', 'vanilla-group'), ('local:other', 'vanilla-group'), ('local:personal', 'personal');`);
db.prepare('INSERT INTO settings VALUES (?)').run(root);
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:legacy id', 'Legacy', 'Legacy Profile', 'a', 'installed');
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:other', 'Other', 'Other Profile', 'b', 'installed');
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:personal', 'Personal', 'Personal Profile', 'a', 'installed');
require('node:fs').mkdirSync(path.join(root,'profiles','Personal Profile'),{recursive:true});
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:personal14', 'Personal14', 'Personal14', 'c', 'installed');
require('node:fs').mkdirSync(path.join(root,'profiles','Personal14'),{recursive:true});
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:personal-fabric', 'Personal Fabric', 'Personal Fabric', 'd', 'installed');
require('node:fs').mkdirSync(path.join(root,'profiles','Personal Fabric'),{recursive:true});
db.exec("INSERT INTO instance_content_sets VALUES ('a','1.13','vanilla'), ('b','1.13','fabric'), ('c','1.14','vanilla'), ('d','1.21.1','fabric'); INSERT INTO instance_group_memberships VALUES ('local:personal14','personal'), ('local:personal-fabric','personal')");
db.close();
'@ | & node --disable-warning=ExperimentalWarning - "$fixture/app"
    if ($LASTEXITCODE) { throw 'Unable to create profile database fixture.' }
    @'
@{
 PackRoot = 'resource_packs'; PackIconFile = 'pack.png'; PackBuildConfigFile = 'pack.build.psd1'
 CanonicalAssetsFolder = 'assets'; AutoSortFolder = 'drop'; AutoSortMappings = @()
 BuildRoot = 'build'; BaseDescription = 'Example'; PackageNameTemplate = '{PackName}-{VersionId}'
 VanillaCatalogCacheRoot = 'cache'
 Validation = @{ RequireLowercasePaths = $true; ParseJsonFiles = $true; ParseMcmetaFiles = $true; RequireTextureForTextureMcmeta = $false }
 Versions = @(
  @{ Id = '1.13'; Enabled = $true; PackFormat = 4 }
  @{ Id = '1.13.1'; Enabled = $true; PackFormat = 4 }
  @{ Id = '1.14'; Enabled = $true; PackFormat = 5 }
  @{ Id = '1.21.1'; Enabled = $true; PackFormat = 34 }
 )
}
'@ | Set-Content -LiteralPath "$fixture/config.psd1"
    Set-Content -LiteralPath "$fixture/resource_packs/example/assets/minecraft/textures/block/example.png" -Value 'fixture'
    $profilePath = "$fixture/app/profiles/Legacy Profile"
    $optionsPath = "$profilePath/options.txt"
    $originalOptions = 'soundCategory_music:0.5', 'fov:0.0', 'guiScale:2', 'narrator:1', 'onboardAccessibility:true', 'resourcePacks:["vanilla","file/existing.zip"]', 'lang:de_de'
    [IO.File]::WriteAllLines($optionsPath, $originalOptions)
    $arguments = @{ ConfigPath = 'config.psd1'; Pack = 'example'; Version = '1.13'; Loader = 'vanilla'; Profile = 'Legacy'; ModrinthAppData = "$fixture/app" }
    & $launcherPath @arguments -DryRun | Out-Null
    if ((Test-Path "$fixture/build") -or (Test-Path "$profilePath/resourcepacks") -or (Test-Path "$fixture/launch.txt")) { throw 'Dry run changed files or launched.' }
    $failed = $false
    try { & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.13 -Profile Personal -ModrinthAppData "$fixture/app" -NoLaunch | Out-Null } catch { $failed = $_.Exception.Message -match 'outside the Vanilla group' }
    if (-not $failed -or (Test-Path "$fixture/app/profiles/Personal Profile/resourcepacks")) { throw 'An explicitly requested personal profile was not excluded.' }
    # IDE terminals may lack the agent's Node directory on PATH.
    $nodeExecutable = (Get-Command node -CommandType Application).Source
    $savedPath = $env:PATH
    try {
        $env:PATH = "$env:SystemRoot/System32;$env:SystemRoot/System32/WindowsPowerShell/v1.0"
        & $launcherPath @arguments -NodePath $nodeExecutable -DryRun | Out-Null
    }
    finally { $env:PATH = $savedPath }
    $failed = $false
    try { & $launcherPath @arguments -NodePath "$fixture/missing-node.exe" -DryRun | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'An invalid explicit Node runtime was accepted.' }
    # Missing build is generated, copied and selected; URI uses the stable encoded ID.
    & $launcherPath @arguments | Out-Null
    $installed = "$profilePath/resourcepacks/rpm-test-example.zip"
    if (-not (Test-Path $installed)) { throw 'Test pack was not installed.' }
    if ((Get-Content "$fixture/launch.txt" -Raw) -cne 'modrinth://launch/instance/local%3Alegacy%20id') { throw 'Wrong launch URI.' }
    $lines = [IO.File]::ReadAllLines($optionsPath)
    $resourceLine = @($lines | Where-Object { $_.StartsWith('resourcePacks:') })
    if ($resourceLine.Count -ne 1) { throw 'Resource pack selection was duplicated.' }
    $enabled = ConvertFrom-Json -InputObject $resourceLine[0].Substring(14)
    if (($enabled -join ',') -cne 'vanilla,file/existing.zip,file/rpm-test-example.zip' -or 'lang:de_de' -notin $lines) { throw 'Existing options or selected packs were lost.' }
    if ('soundCategory_music:0.0' -notin $lines -or 'fov:0.625' -notin $lines -or 'guiScale:4' -notin $lines) { throw 'Test-profile music, FOV, or GUI scale was not applied.' }
    if ('narrator:0' -notin $lines -or 'onboardAccessibility:false' -notin $lines) { throw 'Narrator or first-launch accessibility prompt was not disabled.' }
    if (([IO.File]::ReadAllLines("$optionsPath.rpm-test.bak") -join "`n") -cne ($originalOptions -join "`n")) { throw 'Options backup was not preserved.' }
    # Existing ZIP is reused. Repeated runs replace one stable file, with no duplicate selection.
    $built = "$fixture/build/example/example-1.13.zip"
    $buildTime = (Get-Item $built).LastWriteTimeUtc
    Remove-Item -LiteralPath "$fixture/launch.txt"
    & $launcherPath @arguments -NoLaunch | Out-Null
    if ((Get-Item $built).LastWriteTimeUtc -ne $buildTime -or (Test-Path "$fixture/launch.txt")) { throw 'Existing build was rebuilt or NoLaunch launched.' }
    if (@([IO.File]::ReadAllLines($optionsPath) | Where-Object { $_ -match '^(soundCategory_music|fov|guiScale|narrator|onboardAccessibility):' }).Count -ne 5) { throw 'Repeated runs duplicated the test-profile settings.' }
    & "$fixture/scripts/build-texture-packs.ps1" -ConfigPath config.psd1 -Pack example -Version 1.13.1 | Out-Null
    $grouped = "$fixture/build/example/example-1.13.x.zip"
    if (-not (Test-Path $grouped)) { throw 'Grouped test fixture failed.' }
    & $launcherPath @arguments -NoLaunch | Out-Null
    if ((Get-FileHash $installed).Hash -ne (Get-FileHash $grouped).Hash) { throw 'Grouped build was not installed.' }
    # Prefer the newest applicable artifact even if an older individual ZIP exists.
    Copy-Item -LiteralPath $grouped -Destination $built
    (Get-Item $built).LastWriteTimeUtc = [DateTime]::new(2000, 1, 1)
    $dryOutput = & $launcherPath @arguments -DryRun | Out-String
    if ($dryOutput -notmatch 'Would use build:.*1\.13\.x\.zip') { throw 'Grouped build was not reused.' }
    Remove-Item -LiteralPath $built
    # Invalid options must fail before replacing the previously installed pack.
    $installedHash = (Get-FileHash $installed).Hash
    $goodOptions = [IO.File]::ReadAllText($optionsPath)
    [IO.File]::WriteAllText($optionsPath, 'resourcePacks:not-json')
    $failed = $false
    try { & $launcherPath @arguments -NoLaunch | Out-Null } catch { $failed = $true }
    if (-not $failed -or (Get-FileHash $installed).Hash -ne $installedHash) { throw 'Invalid options were not rejected before copying.' }
    [IO.File]::WriteAllText($optionsPath, $goodOptions)
    # Reject a profile with a different Minecraft version before touching it.
    $failed = $false
    try { & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.14 -Profile Legacy -ModrinthAppData "$fixture/app" -NoLaunch | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Mismatched Minecraft/profile version was accepted.' }
    # Missing versions are created through a minimal mrpack, then reused.
    $dryOutput = & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.14 -ModrinthAppData "$fixture/app" -DryRun | Out-String
    if ($dryOutput -notmatch 'Would create vanilla Modrinth profile' -or (Test-Path "$fixture/build/test-profiles")) { throw 'Missing-profile preview failed or created files.' }
    & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.14 -ModrinthAppData "$fixture/app" -NoLaunch | Out-Null
    $newProfile = "$fixture/app/profiles/Resource Pack Test 1.14"
    if (-not (Test-Path "$newProfile/resourcepacks/rpm-test-example.zip")) { throw 'New profile did not receive the test pack.' }
    $newOptions = [IO.File]::ReadAllLines("$newProfile/options.txt")
    if ('soundCategory_music:0.0' -notin $newOptions -or 'fov:0.625' -notin $newOptions -or 'guiScale:4' -notin $newOptions) { throw 'New profiles did not receive the requested test settings.' }
    if ('narrator:0' -notin $newOptions -or 'onboardAccessibility:false' -notin $newOptions) { throw 'New profiles did not skip narrator onboarding.' }
    if (Test-Path "$fixture/app/profiles/Personal14/resourcepacks") { throw 'A matching personal profile was modified instead of creating a Vanilla profile.' }
    $importPath = "$fixture/build/test-profiles/minecraft-1.14.mrpack"
    $importTime = (Get-Item $importPath).LastWriteTimeUtc
    & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.14 -ModrinthAppData "$fixture/app" | Out-Null
    if ((Get-Item $importPath).LastWriteTimeUtc -ne $importTime -or (Get-Content "$fixture/launch.txt" -Raw) -ne 'modrinth://launch/instance/local%3Acreated-1.14') { throw 'New profile was recreated instead of reused and launched.' }
    @'
const assert=require('node:assert/strict'); const path=require('node:path'); const {DatabaseSync}=require('node:sqlite');
const root=process.argv[2]; const {addToVanillaGroup,ensureLoaderGroups}=require(path.resolve(process.argv[3]));
const db=new DatabaseSync(path.join(root,'app.db'));
assert.deepEqual(db.prepare('SELECT group_id FROM instance_group_memberships WHERE instance_id=?').all('local:created-1.14').map(r=>r.group_id),['vanilla-group']);
assert.deepEqual(db.prepare('SELECT group_id FROM instance_group_memberships WHERE instance_id=? ORDER BY group_id').all('local:legacy id').map(r=>r.group_id),['personal','vanilla-group']);
db.prepare('INSERT INTO instance_group_memberships VALUES (?,?)').run('local:created-1.14','personal');
addToVanillaGroup(root,'local:created-1.14');
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM instance_group_memberships WHERE instance_id=?').get('local:created-1.14').n,2);
assert.throws(()=>addToVanillaGroup(root,'local:other'),/vanilla test profile/);
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM instance_group_memberships WHERE instance_id=?').get('local:other').n,1);
db.prepare('DELETE FROM instance_group_memberships WHERE group_id=?').run('vanilla-group');
db.prepare('DELETE FROM instance_groups WHERE id=?').run('vanilla-group');
addToVanillaGroup(root,'local:created-1.14'); addToVanillaGroup(root,'local:created-1.14');
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM instance_groups WHERE name='Vanilla'").get().n,1);
const group=db.prepare("SELECT id FROM instance_groups WHERE name='Vanilla'").get().id;
db.prepare('INSERT INTO instance_group_memberships VALUES (?,?)').run('local:legacy id',group);
db.prepare('INSERT INTO instance_group_memberships VALUES (?,?)').run('local:other',group);
const originalGroups=ensureLoaderGroups(root);
db.exec("INSERT INTO instance_groups VALUES ('fabric-copy',' fabric ',90),('fabric-upper','FABRIC',91),('neo-copy','neoforge',92)");
db.exec("INSERT INTO instance_group_memberships VALUES ('local:other','fabric-copy'),('local:other','fabric-upper')");
ensureLoaderGroups(root); ensureLoaderGroups(root);
assert.deepEqual(db.prepare("SELECT name FROM instance_groups WHERE name <> 'Personal' ORDER BY name").all().map(r=>r.name),['Fabric','Forge','NeoForge','Vanilla']);
assert.equal(db.prepare('SELECT COUNT(*) AS n FROM instance_group_memberships WHERE instance_id=? AND group_id=?').get('local:other',originalGroups.fabric.groupId).n,1);
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM instance_groups WHERE id='personal' AND name='Personal'").get().n,1);
assert.equal(ensureLoaderGroups(root).fabric.groupId,originalGroups.fabric.groupId);
db.close();
'@ | & node --no-warnings - "$fixture/app" "$fixture/scripts/modrinth-test-profiles.cjs"
    if ($LASTEXITCODE) { throw 'Vanilla grouping, preservation, or idempotency failed.' }
    # Available loaders come from metadata and creation installs the exact loader.
    . (Join-Path $PSScriptRoot 'minecraft-test-loaders.ps1')
    Invoke-Expression $metadataStub
    $oldLoaders = @(Get-MinecraftTestLoaders -VersionId 1.13)
    if (($oldLoaders.Id -join ',') -ne 'vanilla') { throw 'Unsupported loaders were offered for 1.13.' }
    $modernLoaders = @(Get-MinecraftTestLoaders -VersionId 1.21.1)
    if (($modernLoaders.Id -join ',') -ne 'vanilla,fabric,neoforge,forge') { throw 'Supported loader choices were lost.' }
    $failed = $false
    try { & $launcherPath -ConfigPath config.psd1 -Pack example -Version 1.13 -Loader fabric -ModrinthAppData "$fixture/app" -DryRun | Out-Null } catch { $failed = $_.Exception.Message -match 'not available' }
    if (-not $failed) { throw 'Explicitly requested unsupported Fabric was accepted.' }
    $failed = $false
    try { & $launcherPath -ConfigPath config.psd1 -Pack example -Version 1.21.1 -Loader fabric -Profile 'Personal Fabric' -ModrinthAppData "$fixture/app" -NoLaunch | Out-Null } catch { $failed = $_.Exception.Message -match 'outside the Fabric group' }
    if (-not $failed) { throw 'A personal Fabric profile outside the Fabric group was accepted.' }
    foreach ($testLoader in @('fabric','neoforge','forge')) {
        & $launcherPath -ConfigPath config.psd1 -Pack example -Version 1.21.1 -Loader $testLoader -ModrinthAppData "$fixture/app" -NoLaunch | Out-Null
        $loaderImport = "$fixture/build/test-profiles/minecraft-1.21.1-$testLoader.mrpack"
        $createdTime = (Get-Item $loaderImport).LastWriteTimeUtc
        & $launcherPath -ConfigPath config.psd1 -Pack example -Version 1.21.1 -Loader $testLoader -ModrinthAppData "$fixture/app" | Out-Null
        if ((Get-Item $loaderImport).LastWriteTimeUtc -ne $createdTime -or (Get-Content "$fixture/launch.txt" -Raw) -ne "modrinth://launch/instance/local%3Acreated-$testLoader-1.21.1") { throw "Wrong profile reused for $testLoader." }
        $groupName = switch ($testLoader) { fabric { 'Fabric' }; neoforge { 'NeoForge' }; forge { 'Forge' } }
        if ((Get-Content "$fixture/app/profiles/Resource Pack Test $groupName 1.21.1/shader-setup-fixture.txt" -Raw) -ne $testLoader) { throw 'Shader setup did not run in the selected profile.' }
    }
    @'
const assert=require('node:assert/strict'); const path=require('node:path'); const {readProfiles}=require(path.resolve(process.argv[3]));
const profiles=readProfiles(process.argv[2]);
for(const [loader,group] of [['fabric','Fabric'],['neoforge','NeoForge'],['forge','Forge']]) {
 const profile=profiles.find(p=>p.id===`local:created-${loader}-1.21.1`);
 assert.equal(profile.loader,loader); assert.deepEqual(profile.groups,[group]);
}
'@ | & node --no-warnings - "$fixture/app" "$fixture/scripts/modrinth-test-profiles.cjs"
    if ($LASTEXITCODE) { throw 'Loader groups were mixed.' }
    if (Test-Path "$fixture/app/profiles/Personal Fabric/resourcepacks") { throw 'Personal Fabric profile was modified.' }
    # Full interactive selection includes profile selection when versions are ambiguous.
    $script:answers = New-Object 'Collections.Generic.Queue[string]'
    foreach ($answer in @('1', '1')) { $script:answers.Enqueue($answer) }
    function Read-Host { param($Prompt) return $answers.Dequeue() }
    & $launcherPath -Loader vanilla -ConfigPath config.psd1 -ModrinthAppData "$fixture/app" -DryRun | Out-Null
    if ($script:answers.Count) { throw 'Interactive pack/version/profile selection was skipped.' }
    # A pending profile is discoverable even before its folder exists.
    @'
const {DatabaseSync}=require('node:sqlite'); const path=require('node:path');
const db=new DatabaseSync(path.join(process.argv[2],'app.db'));
db.prepare('INSERT INTO instances VALUES (?, ?, ?, ?, ?)').run('local:pending','Pending','Pending','p','installing');
db.prepare('INSERT INTO instance_content_sets VALUES (?, ?, ?)').run('p','1.13.1','vanilla');
db.prepare("INSERT INTO instance_group_memberships SELECT 'local:pending', id FROM instance_groups WHERE name='Vanilla'").run(); db.close();
'@ | & node --no-warnings - "$fixture/app"
    $pendingOutput = & $launcherPath -Loader vanilla -ConfigPath config.psd1 -Pack example -Version 1.13.1 -Profile Pending -ModrinthAppData "$fixture/app" -DryRun | Out-String
    if ($pendingOutput -match 'Would create vanilla') { throw 'An installing profile would be imported a second time.' }
    # Polling must wait for the installed stage, not just the initial database row.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$tokens, [ref]$errors)
    $waitDefinition = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Wait-MinecraftTestProfile' }
    Invoke-Expression $waitDefinition.Extent.Text
    $script:profilePolls = 0
    function Get-ModrinthTestProfiles {
        param($AppDataRoot)
        $script:profilePolls++
        [pscustomobject]@{ id = 'local:pending'; name = 'Pending'; loader = 'vanilla'; minecraftVersion = '1.13.1'; installStage = $(if ($script:profilePolls -gt 1) { 'installed' } else { 'installing' }) }
    }
    $ready = Wait-MinecraftTestProfile -AppDataRoot "$fixture/app" -Name Pending -VersionId 1.13.1 -TimeoutSeconds 10
    if ($ready.installStage -ne 'installed' -or $script:profilePolls -ne 2) { throw 'Profile installation readiness was not checked.' }
    # Unsafe profile paths in the database are rejected by the read-only helper.
    @'
const {DatabaseSync}=require('node:sqlite'); const path=require('node:path');
const db=new DatabaseSync(path.join(process.argv[2],'app.db'));
db.prepare('UPDATE instances SET path = ? WHERE id = ?').run('../outside', 'local:legacy id'); db.close();
'@ | & node --disable-warning=ExperimentalWarning - "$fixture/app"
    $failed = $false
    try { & $launcherPath @arguments -DryRun | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Profile path outside the profile root was accepted.' }
    Write-Output 'Minecraft test launcher tests passed.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
