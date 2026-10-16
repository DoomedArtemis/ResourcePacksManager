[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')

# Load only function definitions, without starting the build script.
$parseTokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'build-texture-packs.ps1'), [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Build script has syntax errors.' }
foreach ($function in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    Invoke-Expression $function.Extent.Text
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $temporaryRoot ('moss-file-options-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
    $config = @{
        PackBuildConfigFile = 'pack.build.psd1'
        CanonicalAssetsFolder = 'assets'
        AutoSortFolder = 'drop'
        AutoSortMappings = @()
        Versions = @(@{ Id = '1.17' }, @{ Id = '26.1' })
    }
    $directory = Get-Item -LiteralPath $fixtureRoot
    $encoding = New-Object System.Text.UTF8Encoding($false)
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'assets/minecraft/models/block') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'variants') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'pack.build.psd1'), "@{ FileOptionsPath = 'variants/rules.json'; FileRules = @(@{ Path = 'assets/unused.json'; MinVersion = '1.17' }) }", $encoding)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'assets/minecraft/models/block/test.json'), '{}', $encoding)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'variants/test.json'), '{}', $encoding)
    $manifest = @{
        FileRules = @(@{ Path = 'assets/unused2.json'; BeforeVersion = '26.1' })
        FileVariants = @(@{ Path = 'assets/minecraft/models/block/test.json'; SourcePath = 'variants/test.json'; BeforeVersion = '26.1' })
    }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'variants/rules.json'), ($manifest | ConvertTo-Json -Depth 10), $encoding)
    $options = Get-PackBuildOptions -PackDirectory $directory -Config $config
    if ($options.FileRules.Count -ne 2 -or $options.FileVariants.Count -ne 1) { throw 'JSON options were not appended.' }
    $legacy = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0])
    $modern = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[1])
    if ($legacy.Count -ne 1 -or [IO.Path]::GetFullPath($legacy[0].SourcePath) -ne [IO.Path]::GetFullPath((Join-Path $fixtureRoot 'variants/test.json'))) { throw ('Legacy exact variant was not selected: ' + ($legacy | ConvertTo-Json -Depth 10)) }
    if ($modern.Count -ne 1 -or [IO.Path]::GetFullPath($modern[0].SourcePath) -ne [IO.Path]::GetFullPath((Join-Path $fixtureRoot 'assets/minecraft/models/block/test.json'))) { throw 'Modern source was not preserved.' }

    # Prefix rules must still work after indexing exact file paths.
    $manifest.FileVariants[0].Path = 'assets/minecraft/models/'
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'variants/rules.json'), ($manifest | ConvertTo-Json -Depth 10), $encoding)
    $legacy = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0])
    if ([IO.Path]::GetFullPath($legacy[0].SourcePath) -ne [IO.Path]::GetFullPath((Join-Path $fixtureRoot 'variants/test.json'))) { throw 'Prefix variant was not selected.' }

    # Mod compatibility filters assets independently of ordinary FileRules.
    $config.Versions = @('1.20.1', '1.20.2', '1.21', '1.21.1', '1.21.2') | ForEach-Object { @{ Id = $_; Enabled = $true } }
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'assets/demo/models/block') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'assets/demo/models/block/test.json'), '{}', $encoding)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'assets/minecraft/models/block/custom_floor.json'), '{}', $encoding)
    function Set-CompatibilityFixture([string]$optionsText) {
        [IO.File]::WriteAllText((Join-Path $fixtureRoot 'pack.build.psd1'), $optionsText, $encoding)
    }
    function Assert-CompatibilityFiles([string]$version, [int]$expected) {
        $versionConfig = $config.Versions | Where-Object { $_.Id -eq $version }
        $files = @(Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $versionConfig)
        if ($files.Count -ne $expected) { throw "Compatibility fixture for ${version}: expected $expected files, found $($files.Count)." }
    }
    Set-CompatibilityFixture "@{ Compatibility = @{ demo = @{ Versions = @('1.20.1', '1.21.1') } }; FileRules = @(@{ Path = 'assets/demo/' }) }"
    Assert-CompatibilityFiles '1.20.1' 3
    Assert-CompatibilityFiles '1.20.2' 2
    Assert-CompatibilityFiles '1.21.1' 3
    Set-CompatibilityFixture "@{ Compatibility = @{ demo = @{ Versions = @('1.20.1..1.21.1'); ExcludeVersions = @('1.20.2 to 1.21') } } }"
    Assert-CompatibilityFiles '1.20.1' 3
    Assert-CompatibilityFiles '1.20.2' 2
    Assert-CompatibilityFiles '1.21' 2
    Assert-CompatibilityFiles '1.21.1' 3
    Assert-CompatibilityFiles '1.21.2' 2
    Set-CompatibilityFixture "@{ Compatibility = @{ demo = @{ AfterVersion = '1.20.1'; BeforeVersion = '1.21.2'; MinVersion = '1.20.2'; MaxVersion = '1.21.1'; Paths = @('assets/demo/', 'assets/minecraft/models/block/custom_floor.json') } } }"
    Assert-CompatibilityFiles '1.20.1' 1
    Assert-CompatibilityFiles '1.20.2' 3
    Assert-CompatibilityFiles '1.21.1' 3
    Assert-CompatibilityFiles '1.21.2' 1
    Set-CompatibilityFixture "@{ Compatibility = @{ demo = @{ Enabled = `$false } } }"
    Assert-CompatibilityFiles '1.20.1' 2
    Set-CompatibilityFixture "@{ Compatibility = @{ demo = @{ Versions = @() } } }"
    Assert-CompatibilityFiles '1.20.1' 2
    $supportOptions = @{ Compatibility = @{
        second = @{ Name = 'Second Mod'; Versions = @('1.20.1..1.21.1'); Support = 'Second mod support.' }
        first = @{ Name = 'First Mod'; Versions = @('1.20.1'); Support = 'First mod support.' }
        disabled = @{ Enabled = $false; Support = 'Must not appear.' }
        no_note = @{ Name = 'First Mod'; Versions = @('1.20.1') }
    } }
    $supportRules = @(Get-PackCompatibilityRules -Options $supportOptions -Config $config -VersionConfig $config.Versions[0] -PackName 'fixture')
    $supportText = Get-PackCompatibilityText -Rules $supportRules
    $expectedSupport = 'First Mod' + [Environment]::NewLine + 'Second Mod' + [Environment]::NewLine
    if ($supportText -cne $expectedSupport) { throw 'Active support notes were not combined in stable mod-ID order.' }
    $supportRules = @(Get-PackCompatibilityRules -Options $supportOptions -Config $config -VersionConfig $config.Versions[3] -PackName 'fixture')
    if ((Get-PackCompatibilityText -Rules $supportRules) -cne ('Second Mod' + [Environment]::NewLine)) { throw 'Unsupported mod note leaked into support text.' }
    $supportRules = @(Get-PackCompatibilityRules -Options $supportOptions -Config $config -VersionConfig $config.Versions[4] -PackName 'fixture')
    if (Get-PackCompatibilityText -Rules $supportRules) { throw 'Support text generated without an active mod note.' }
    foreach ($invalidOptions in @(
        "@{ Compatibility = @{ demo = @{ Versions = @('unknown') } } }",
        "@{ Compatibility = @{ demo = @{ Versions = @('1.21.1..1.20.1') } } }",
        "@{ Compatibility = @{ demo = @{ MinVersion = '1.21.1'; MaxVersion = '1.20.1' } } }",
        "@{ Compatibility = @{ demo = @{ Paths = @('assets/demo/*') } } }",
        "@{ Compatibility = @{ demo = @{ Support = @('invalid') } } }",
        "@{ Compatibility = @{ demo = @{ Unexpected = `$true } } }"
    )) {
        Set-CompatibilityFixture $invalidOptions
        $rejected = $false
        try { Get-PackInputFiles -PackDirectory $directory -Config $config -VersionConfig $config.Versions[0] | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw "Invalid compatibility options accepted: $invalidOptions" }
    }
    Set-CompatibilityFixture "@{ FileOptionsPath = 'variants/rules.json' }"
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'variants/rules.json'), '{"UnexpectedOption": []}', $encoding)
    $rejected = $false
    try { Get-PackBuildOptions -PackDirectory $directory -Config $config | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unknown JSON options were accepted.' }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'pack.build.psd1'), "@{ FileOptionsPath = '../outside.json' }", $encoding)
    $rejected = $false
    try { Get-PackBuildOptions -PackDirectory $directory -Config $config | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'FileOptionsPath escaped the pack.' }
    Write-Output 'Passed JSON options, variants, compatibility selectors, exclusions, custom paths, disabled entries, compatibility names and deduplication, and invalid option checks.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedFixture -Leaf) -notlike 'moss-file-options-*') {
        throw 'Refusing to remove a fixture outside the temporary test directory.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
