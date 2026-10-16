[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
foreach ($scriptName in @('publish-modrinth.ps1', 'publish-curseforge.ps1')) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Publisher syntax errors: $errors" }
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
}
$DefaultReleaseVersion = '1.0.0'; $DefaultStatus = 'listed'; $DefaultVersionType = 'release'
$DefaultEnvironment = 'client_only'; $DefaultReleaseType = 'release'; $DefaultChangelogType = 'text'
$matrix = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../config/minecraft-release-version-matrix.psd1')
$order = Get-VersionOrderLookup $matrix
function Resolve-Dependencies {
    param([object[]]$Entries, [string]$Version = '1.15.2')
    Get-ModrinthDependencies -Dependencies $Entries -PackName 'fixture' -VersionConfig @{ Id = $Version } -VersionOrder $order
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -like "*$Message*") { return }
        throw
    }
    throw "Expected rejection containing '$Message'."
}
$empty = ConvertTo-Hashtable (ConvertTo-Hashtable @{ Versions = @(); ExcludeVersions = @() })
if ($empty.Versions -isnot [array] -or $empty.Versions.Count -ne 0) { throw 'Empty arrays changed type during repeated conversion.' }
if (@(Resolve-Dependencies @(@{ ProjectId = 'TKB6INcv'; Versions = @() }) '1.20.1').Count) { throw 'Empty Versions must match no releases.' }
if (@(Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Versions = @('1.20.1') }) '1.20.1').Count -ne 1) { throw 'Single-element Versions failed.' }
$configs = @{}
foreach ($pack in @('alternative_ores', 'better_candles')) {
    $options = Import-PowerShellDataFile (Join-Path $PSScriptRoot "../resource_packs/$pack/pack.build.psd1")
    $modrinth = Get-PackModrinthConfig $pack $options
    $curseforge = Get-PackCurseForgeConfig $pack $options
    $configs[$pack] = $modrinth
    $expectedId = if ($pack -eq 'alternative_ores') { 'Ce6I4WUE' } else { 'dl88rsIq' }
    $expectedCurseForgeId = if ($pack -eq 'alternative_ores') { '268560' } else { '988504' }
    $compatibility = if ($pack -eq 'alternative_ores') { $options.Compatibility.mekanism } else { $options.Compatibility.dye_depot }
    foreach ($version in $matrix.Versions) {
        $expected = [int]($version.Id -in $compatibility.Versions)
        $mr = @(Resolve-Dependencies $modrinth.Dependencies $version.Id | Where-Object { $_.project_id -ceq $expectedId })
        $cf = @(Get-CurseForgeDependencies $curseforge.Dependencies $pack $version $order | Where-Object { $_.projectID -eq $expectedCurseForgeId })
        if ($mr.Count -ne $expected -or $cf.Count -ne $expected) { throw "Platform version filters differ for $pack $($version.Id)" }
        if ($expected -and ($mr[0].project_id -cne $expectedId -or $mr[0].dependency_type -ne 'optional' -or $cf[0].type -ne 'optionalDependency')) {
            throw "Wrong project/type for $pack $($version.Id)"
        }
    }
}
$bounded = @{ ProjectId = 'Ce6I4WUE'; Versions = @('1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5'); MinVersion = '1.15.1'; MaxVersion = '1.16.5'; AfterVersion = '1.15.1'; BeforeVersion = '1.16.5'; ExcludeVersions = @('1.16.1', '1.16.3', '1.16.4') }
foreach ($version in $matrix.Versions) {
    if (@(Resolve-Dependencies @($bounded) $version.Id).Count -ne [int]($version.Id -eq '1.15.2')) { throw "Bounds failed for $($version.Id)" }
}
foreach ($type in @('required', 'optional', 'incompatible', 'embedded')) {
    $result = @(Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Type = $type }))
    if ($result[0].dependency_type -ne $type) { throw "Dependency type failed: $type" }
}
$pinned = @(Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; VersionId = 'Ab12Cd34'; FileName = 'mekanism.jar'; Type = 'required' }))
if ($pinned[0].version_id -cne 'Ab12Cd34' -or $pinned[0].file_name -ne 'mekanism.jar') { throw 'Version pin or filename lost.' }
if (@(Resolve-Dependencies @(@{ VersionId = 'Ab12Cd34' })).Count -ne 1) { throw 'Version-only dependency lost.' }
if (@(Resolve-Dependencies @(@{ FileName = 'external.jar'; Type = 'embedded' })).Count -ne 1) { throw 'External dependency lost.' }
if (@(Resolve-Dependencies @(@{ Enabled = $false })).Count) { throw 'Disabled dependency included.' }
if (@(Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE' }, @{ ProjectId = 'Ce6I4WUE'; Type = 'optional' })).Count -ne 1) { throw 'Duplicate dependency included.' }
if (@(Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE' }, @{ ProjectId = 'ce6I4WUE' })).Count -ne 2) { throw 'Case-sensitive project IDs collapsed.' }
Assert-Rejected { Resolve-Dependencies @(@{}) } 'requires ProjectId, VersionId, or FileName'
Assert-Rejected { Resolve-Dependencies @('Ce6I4WUE') } 'dependency tables'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = '268560' }) } 'invalid ProjectId'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'dye-depot' }) } 'invalid ProjectId'
Assert-Rejected { Resolve-Dependencies @(@{ VersionId = 'invalid!' }) } 'invalid VersionId'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Type = 'tool' }) } 'invalid Type'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Version = '1.15.2' }) } 'unknown option'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Versions = @('1.21.1'); BeforeVersion = 'typo' }) } 'unknown version id'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; Type = 'required' }, @{ ProjectId = 'Ce6I4WUE' }) } 'conflicting dependency settings'
Assert-Rejected { Resolve-Dependencies @(@{ ProjectId = 'Ce6I4WUE'; VersionId = 'Ab12Cd34' }, @{ ProjectId = 'Ce6I4WUE'; VersionId = 'Ab12Cd35' }) } 'conflicting dependency settings'

# Capture the actual multipart data field without sending anything to a server.
Add-Type -AssemblyName System.Net.Http
Add-Type -ReferencedAssemblies System.Net.Http -TypeDefinition @'
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public class ModrinthDependencyCapture : HttpMessageHandler {
    public string Data;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        foreach (HttpContent part in (MultipartFormDataContent) request.Content) {
            if (part.Headers.ContentDisposition.Name.Trim('"') == "data") Data = await part.ReadAsStringAsync();
        }
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"id\":\"Ab12Cd34\"}") };
    }
}
'@
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('modrinth-dependencies-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$zipPath = Join-Path $fixture 'fixture.zip'
$handler = New-Object ModrinthDependencyCapture
$client = [System.Net.Http.HttpClient]::new($handler)
$ApiBaseUrl = 'https://example.invalid'
try {
    Set-Content -LiteralPath $zipPath -Value 'fixture'
    $item = [pscustomobject]@{
        PackName = 'alternative_ores'; PackDisplayName = 'Alternative Ores'; ProjectId = 'Ab12Cd34'; MinecraftVersion = '1.15.2'
        ReleaseVersion = '1.0.0'; VersionNumber = '1.0.0-mc1.15.2'; VersionName = 'Alternative Ores'
        Changelog = ''; VersionType = 'release'; Status = 'listed'; Environment = 'client_only'; Featured = $false
        Loaders = @('minecraft'); ZipPath = $zipPath
        Dependencies = @(Resolve-Dependencies $configs.alternative_ores.Dependencies)
    }
    $uploaded = Publish-ModrinthVersion $client $item
    $payload = $handler.Data | ConvertFrom-Json
    if ($uploaded.id -cne 'Ab12Cd34' -or (ConvertTo-Json -InputObject @($payload.dependencies) -Depth 10 -Compress) -cne (ConvertTo-Json -InputObject @($item.Dependencies) -Depth 10 -Compress)) { throw 'Multipart dependency metadata changed.' }
    foreach ($expectedId in @('Ce6I4WUE', 'XxWD5pD3')) {
        if (@($payload.dependencies | Where-Object { $_.project_id -ceq $expectedId -and $_.dependency_type -eq 'optional' }).Count -ne 1) { throw 'Expected optional dependency missing.' }
    }
    if ($payload.game_versions[0] -ne '1.15.2') { throw 'Game version changed.' }
    $item.Dependencies = @(Resolve-Dependencies $configs.alternative_ores.Dependencies '1.21.2')
    Publish-ModrinthVersion $client $item | Out-Null
    if ($handler.Data -notmatch '"dependencies":\[\]') { throw 'Unsupported Minecraft version gained a dependency.' }
    $item.Dependencies = $pinned
    Publish-ModrinthVersion $client $item | Out-Null
    $payload = $handler.Data | ConvertFrom-Json
    if ($payload.dependencies[0].version_id -cne 'Ab12Cd34' -or $payload.dependencies[0].file_name -ne 'mekanism.jar') { throw 'Multipart version pin or filename lost.' }
    $item.PSObject.Properties.Remove('Dependencies')
    if ((Get-ModrinthUploadMetadata $item).dependencies.Count) { throw 'Legacy upload behavior changed.' }
    $legacy = Get-PackModrinthConfig 'legacy' @{}
    if ($legacy.DependenciesConfigured -or $legacy.Dependencies.Count) { throw 'Legacy configuration defaults changed.' }
    Write-Output 'Passed both platforms across all 51 releases, optional Mekanism/Dye Depot and AE2 multipart metadata, bounds, types, pins, external files, case-sensitive IDs, validation, duplicates, and legacy defaults.'
}
finally {
    $client.Dispose()
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Force
}
