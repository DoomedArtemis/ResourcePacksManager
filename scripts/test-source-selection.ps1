[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Builder syntax errors.' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $statement.Extent.Text }
}

# Compare indexed lookup to the original path predicate, including overlapping
# prefixes, exact rules, repeated declarations, casing, aliases and Unicode.
$rules = New-Object System.Collections.Generic.List[object]
$paths = @('assets/', 'assets/demo/', 'assets/demo/models/', 'assets/demo/models/a.json',
    'ASSETS/DEMO/MODELS/A.JSON', 'models/a.json', 'assets/demo2/a.json', 'assets/demo//a.json',
    'assets/demo/a.json.extra', 'a.json', ('assets/demo/' + [char]0x0131 + '.json'))
foreach ($rulePath in $paths) {
    $rules.Add(@{ Path = $rulePath })
    $rules.Add($null)
    $rules.Add(@{ Path = $rulePath })
}
for ($index = 0; $index -lt 80; $index++) { $rules.Add(@{ Path = "assets/mod$index/models/" }); $paths += "assets/mod$index/models/a.json" }
$index = New-PackPathRuleIndex -Rules $rules.ToArray() -ContextDescription 'Fixture'
foreach ($candidate in $paths) {
    $aliases = @($candidate, $candidate.ToUpperInvariant(), 'models/a.json')
    $expected = @(); $ordinal = 0
    foreach ($rule in $rules) {
        if ($null -eq $rule) { continue }
        foreach ($alias in $aliases) {
            if (Test-RuleMatch -Path $alias -Rule $rule.Path) { $expected += $ordinal; break }
        }
        $ordinal++
    }
    $actual = @(Get-PackPathRuleMatches -Index $index -Paths $aliases | ForEach-Object { $_.Ordinal })
    if (($actual -join ',') -ne ($expected -join ',')) { throw "Indexed path semantics changed for $candidate" }
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('source-selection-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'assets/demo/models/block'), (Join-Path $fixture 'drop/models/block'), (Join-Path $fixture 'variants') -Force | Out-Null
try {
    foreach ($file in @('assets/demo/models/block/a.json', 'assets/demo/models/block/b.json', 'drop/models/block/c.json', 'variants/replacement.json')) {
        Set-Content -LiteralPath (Join-Path $fixture $file) -Value '{}'
    }
    $config = @{ PackBuildConfigFile = 'pack.build.psd1'; CanonicalAssetsFolder = 'assets'; AutoSortFolder = 'drop'; AutoSortMappings = @(@{ Folder = 'models'; AssetPrefix = 'assets/minecraft/models/' }); Versions = @(@{ Id = '1.17' }, @{ Id = '26.1' }) }
    $directory = Get-Item $fixture
    $fixtureOptions = @{
        FileRules = @(
            @{ Path = 'assets/demo/'; MaxVersion = '1.17' }
            @{ Path = 'ASSETS/DEMO/MODELS/BLOCK/A.JSON'; MinVersion = '26.1' }
            @{ Path = 'models/block/'; MinVersion = '26.1' }
        )
        FileVariants = @(@{ Path = 'assets/demo/models/block/'; SourcePath = 'variants/replacement.json'; BeforeVersion = '26.1' })
    }
    # Supply the fixture as JSON so each call must reread changed options.
    Set-Content (Join-Path $fixture 'pack.build.psd1') "@{ FileOptionsPath = 'variants/rules.json' }"
    $rulesPath = Join-Path $fixture 'variants/rules.json'
    $fixtureOptions | ConvertTo-Json -Depth 10 | Set-Content $rulesPath
    $legacy = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0])
    $modern = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[1])
    if ($legacy.Count -ne 2 -or @($legacy | Where-Object { $_.SourcePath -ne (Join-Path $fixture 'variants/replacement.json') }).Count) { throw 'Prefix variants or OR inclusion rules changed.' }
    if ($modern.Count -ne 2 -or $modern[0].Kind -ne 'auto' -or $modern[0].VirtualPath -ne 'c.json' -or $modern[1].VirtualPath -ne 'assets/demo/models/block/a.json') { throw 'Typed drop paths, priorities or version isolation changed.' }

    $fixtureOptions.FileVariants = @(
        @{ Path = 'assets/demo/models/block/a.json'; SourcePath = 'variants/replacement.json' }
        @{ Path = 'demo/models/block/'; SourcePath = 'variants/replacement.json' }
    )
    $fixtureOptions | ConvertTo-Json -Depth 10 | Set-Content $rulesPath
    $rejected = $false
    try { Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0] | Out-Null }
    catch { $rejected = $_.Exception.Message -like '*matches multiple FileVariants*' }
    if (-not $rejected) { throw 'Overlapping exact/typed prefix variants must remain an error.' }

    # The same declaration matching both canonical and relative RulePaths is one
    # match; two separate declarations must still count as two conflicts.
    $fixtureOptions.FileVariants = @(@{ Path = 'assets/demo/'; SourcePath = 'variants/missing.json' })
    $fixtureOptions | ConvertTo-Json -Depth 10 | Set-Content $rulesPath
    $rejected = $false
    try { Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0] | Out-Null }
    catch { $rejected = $_.Exception.Message -like '*missing SourcePath*' }
    if (-not $rejected) { throw 'Missing selected variant files must remain an error.' }
    $fixtureOptions.FileVariants = @()
    $fixtureOptions.FileRules = @(@{ Path = 'assets/demo/'; Versions = @('unknown') })
    $fixtureOptions | ConvertTo-Json -Depth 10 | Set-Content $rulesPath
    $rejected = $false
    try { Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0] | Out-Null }
    catch { $rejected = $_.Exception.Message -like '*unknown version id*' }
    if (-not $rejected) { throw 'Unknown matching selector versions must remain an error.' }
    Write-Output 'Passed indexed/reference path equivalence, rule order, case sensitivity, aliases, duplicates, prefixes, OR rules, variant conflicts, live configuration edits, priorities and validation failures.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'source-selection-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
