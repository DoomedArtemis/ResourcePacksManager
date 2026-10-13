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

    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'variants/rules.json'), '{"UnexpectedOption": []}', $encoding)
    $rejected = $false
    try { Get-PackBuildOptions -PackDirectory $directory -Config $config | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unknown JSON options were accepted.' }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'pack.build.psd1'), "@{ FileOptionsPath = '../outside.json' }", $encoding)
    $rejected = $false
    try { Get-PackBuildOptions -PackDirectory $directory -Config $config | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'FileOptionsPath escaped the pack.' }
    Write-Output 'Passed JSON option merging, exact/prefix variant routing, modern preservation, and invalid option/path checks.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixture.StartsWith($temporaryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedFixture -Leaf) -notlike 'moss-file-options-*') {
        throw 'Refusing to remove a fixture outside the temporary test directory.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
