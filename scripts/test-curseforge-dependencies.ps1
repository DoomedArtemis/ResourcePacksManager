[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')

$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'publish-curseforge.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Publisher syntax errors: $errors" }
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
}
$DefaultReleaseVersion = '1.0.0'
$DefaultReleaseType = 'release'
$DefaultChangelogType = 'text'
$matrix = @('1.19.4', '1.20.1', '1.20.2', '1.21', '1.21.1', '1.21.2')
$order = Get-VersionOrderLookup -Config @{ Versions = @($matrix | ForEach-Object { @{ Id = $_ } }) }
function Resolve-Dependencies {
    param([object[]]$Entries, [string]$Version = '1.20.1')
    Get-CurseForgeDependencies -Dependencies $Entries -PackName 'fixture' -VersionConfig @{ Id = $Version } -VersionOrder $order
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -like "*$Message*") { return }
        throw
    }
    throw "Expected rejection containing '$Message'."
}

$packOptions = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../resource_packs/better_candles/pack.build.psd1')
$settings = Get-PackCurseForgeConfig -PackName 'better_candles' -PackOptions $packOptions
foreach ($version in $matrix) {
    $relations = @(Resolve-Dependencies $settings.Dependencies $version)
    $expected = if ($version -in @('1.20.1', '1.21.1')) { 1 } else { 0 }
    if ($relations.Count -ne $expected) { throw "Dye Depot filtering failed for $version" }
    if ($expected -and ($relations[0].projectID -ne '988504' -or $relations[0].type -ne 'optionalDependency' -or $relations[0].slug -ne 'dye-depot' -or $relations[0].projectID -isnot [int])) {
        throw 'Dye Depot must be an optional relation with numeric ID and slug.'
    }
}
$bounded = @{ Slug = 'example-project'; ProjectId = 123; MinVersion = '1.20.1'; MaxVersion = '1.21.1'; AfterVersion = '1.20.1'; BeforeVersion = '1.21.1'; ExcludeVersions = @('1.21') }
foreach ($version in $matrix) {
    if (@(Resolve-Dependencies @($bounded) $version).Count -ne [int]($version -eq '1.20.2')) { throw "Bounds failed for $version" }
}
foreach ($type in @('embeddedLibrary', 'incompatible', 'optionalDependency', 'requiredDependency', 'tool')) {
    $result = @(Resolve-Dependencies @(@{ Slug = 'example-project'; Type = $type }))
    if ($result[0].type -ne $type -or $result[0].slug -ne 'example-project') { throw "Relation type failed: $type" }
}
if (@(Resolve-Dependencies @(@{ Enabled = $false })).Count) { throw 'Disabled dependency included.' }
if (@(Resolve-Dependencies @(@{ Slug = 'example-project'; ProjectId = 123 }, @{ Slug = 'example-project'; ProjectId = '123'; Type = 'optionalDependency' })).Count -ne 1) { throw 'Duplicate relation included.' }
Assert-Rejected { Resolve-Dependencies @(@{ Slug = 'example-project'; ProjectId = 123; Type = 'requiredDependency' }, @{ Slug = 'example-project'; ProjectId = 123 }) } 'conflicting relation types'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'abc' }) } 'invalid ProjectId'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 0 }) } 'invalid ProjectId'
Assert-Rejected { Resolve-Dependencies @(@{}) } 'requires ProjectId or Slug'
Assert-Rejected { Resolve-Dependencies @(@{ Slug = 'example-project'; ProjectId = 123; Type = 'required' }) } 'invalid Type'
Assert-Rejected { Resolve-Dependencies @(@{ Slug = 'example-project'; ProjectId = 123; Version = '1.20.1' }) } 'unknown option'
Assert-Rejected { Resolve-Dependencies @(@{ Slug = 'example-project'; ProjectId = 123; Versions = @('1.21.1'); BeforeVersion = 'typo' }) } 'unknown version id'
Assert-Rejected { Resolve-Dependencies @('123') } 'dependency tables'

Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 123 }) } 'requires Slug'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = '999999999999'; Slug = 'example-project' }) } 'invalid ProjectId'

# Exercise the actual multipart upload with an in-memory HTTP handler; no network or token.
$fullMatrix = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../config/minecraft-release-version-matrix.psd1')
$fullOrder = Get-VersionOrderLookup -Config $fullMatrix
$oreOptions = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../resource_packs/alternative_ores/pack.build.psd1')
$oreRelations = @(Get-CurseForgeDependencies -Dependencies $oreOptions.CurseForge.Dependencies -PackName 'alternative_ores' -VersionConfig @{ Id = '1.20.1' } -VersionOrder $fullOrder)
if ($oreRelations.Count -ne 26) { throw 'Expected twenty-six Alternative Ores relations for 1.20.1, including Ad Astra.' }
foreach ($relation in $oreRelations) {
    if ($relation.projectID -isnot [int] -or [string]::IsNullOrWhiteSpace($relation.slug)) { throw 'Alternative Ores relation lacks integer projectID or required slug.' }
}
Add-Type -AssemblyName System.Net.Http
Add-Type -ReferencedAssemblies System.Net.Http -TypeDefinition @'
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public class CurseForgeDependencyCapture : HttpMessageHandler {
    public string Body;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        Body = await request.Content.ReadAsStringAsync();
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"id\":42}") };
    }
}
'@
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('curseforge-dependencies-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$zipPath = Join-Path $fixture 'fixture.zip'
$handler = New-Object CurseForgeDependencyCapture
$client = [System.Net.Http.HttpClient]::new($handler)
$ApiBaseUrl = 'https://example.invalid'
try {
    Set-Content -LiteralPath $zipPath -Value 'fixture'
    $item = [pscustomobject]@{
        PackName = 'fixture'; PackDisplayName = 'Fixture'; ProjectId = '123'; MinecraftVersion = '1.20.1'
        ReleaseVersion = '1.0.0'; VersionNumber = '1.0.0-mc1.20.1'; VersionName = 'Fixture'
        Changelog = ''; ChangelogType = 'text'; ReleaseType = 'release'; ManualRelease = $false
        GameVersionNames = @('1.20.1'); ZipPath = $zipPath; DependenciesConfigured = $true
        Dependencies = @(Resolve-Dependencies $settings.Dependencies)
    }
    $uploaded = Publish-CurseForgeVersion -Client $client -Item $item
    if ($uploaded.id -ne 42 -or $handler.Body -notmatch '"projectID":988504' -or $handler.Body -notmatch '"type":"optionalDependency"' -or $handler.Body -notmatch '"slug":"dye-depot"') {
        throw 'Multipart upload lost dependency metadata.'
    }
    $item.Dependencies = @(Resolve-Dependencies $settings.Dependencies '1.21.2')
    Publish-CurseForgeVersion -Client $client -Item $item | Out-Null
    if ($handler.Body -match '"relations"') { throw 'Nonmatching upload sent an invalid empty relation list.' }
    $item.Dependencies = @(Get-CurseForgeDependencies -Dependencies $oreOptions.CurseForge.Dependencies -PackName 'alternative_ores' -VersionConfig @{ Id = '1.13' } -VersionOrder $fullOrder)
    if ($item.Dependencies.Count) { throw 'Alternative Ores 1.13 unexpectedly has dependencies.' }
    Publish-CurseForgeVersion -Client $client -Item $item | Out-Null
    if ($handler.Body -match '"relations"') { throw 'Alternative Ores 1.13 sent an invalid empty relation list.' }
    $item.DependenciesConfigured = $false
    if ((Get-CurseForgeUploadMetadata $item).Contains('relations')) { throw 'Unconfigured packs changed behavior.' }
    $legacy = Get-PackCurseForgeConfig -PackName 'legacy' -PackOptions @{}
    if ($legacy.DependenciesConfigured -or $legacy.Dependencies.Count) { throw 'Legacy dependency defaults changed.' }
    Write-Output 'Passed Dye Depot version selection, bounds, relation types, validation, duplicates, legacy defaults, and multipart upload metadata.'
}
finally {
    $client.Dispose()
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Force
}
