[CmdletBinding()]
param(
    [string[]]$Pack,
    [switch]$Check,
    [switch]$CachedMetadata,
    [string]$SyncConfigPath = 'config/compatibility-sync.json',
    [string]$ReportPath = 'build/compatibility-sync.report.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

function Get-SyncTableValueAst {
    param($Table, [string]$Key)
    foreach ($pair in $Table.KeyValuePairs) {
        if ($pair.Item1.SafeGetValue() -ceq $Key) {
            $nodes = @($pair.Item2.FindAll({ param($node)
                $node -is [Management.Automation.Language.ExpressionAst]
            }, $false))
            return $nodes[0]
        }
    }
    return $null
}

function Get-SyncVersionLocation {
    param($Table, [string]$Kind, [string]$Key)
    $node = Get-SyncTableValueAst $Table 'Versions'
    if ($null -eq $node) { throw "Managed $Kind '$Key' needs an explicit Versions array." }
    foreach ($bound in @('ExcludeVersions', 'MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion')) {
        if ($null -ne (Get-SyncTableValueAst $Table $bound)) { throw "Managed $Kind '$Key' has '$bound'. Use explicit Versions for automatic synchronization." }
    }
    return @{ kind = $Kind; key = $Key; start = $node.Extent.StartOffset; end = $node.Extent.EndOffset }
}

$syncConfig = Get-Content (Join-Path $repoRoot $SyncConfigPath) -Raw | ConvertFrom-Json
$matrix = Import-PowerShellDataFile (Join-Path $repoRoot 'config/minecraft-release-version-matrix.psd1')
$packs = @()
foreach ($profile in $syncConfig.packs) {
    if ($Pack -and $profile.name -notin $Pack) { continue }
    $packRoot = Join-Path $repoRoot "resource_packs/$($profile.name)"
    $file = Join-Path $packRoot 'pack.build.psd1'
    $options = Import-PowerShellDataFile $file
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Syntax errors in '$file'." }
    $tables = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.HashtableAst] }, $true))
    $rootTable = $tables[0]
    $compatibilityTable = Get-SyncTableValueAst $rootTable 'Compatibility'
    $locations = @()
    foreach ($group in $profile.groups) {
        foreach ($namespace in $group.namespaces) {
            $entry = Get-SyncTableValueAst $compatibilityTable $namespace
            if ($null -eq $entry) { throw "No Compatibility.$namespace in '$file'." }
            $locations += Get-SyncVersionLocation $entry 'compatibility' $namespace
        }
    }
    foreach ($platform in @('Modrinth', 'CurseForge')) {
        $platformTable = Get-SyncTableValueAst $rootTable $platform
        $dependencies = Get-SyncTableValueAst $platformTable 'Dependencies'
        $entries = @($dependencies.FindAll({ param($node) $node -is [Management.Automation.Language.HashtableAst] }, $true))
        foreach ($entry in $entries) {
            $id = Get-SyncTableValueAst $entry 'ProjectId'
            if ($null -eq $id) { continue }
            $projectId = [string]$id.SafeGetValue()
            $known = @($profile.groups | ForEach-Object { $_.projects } | Where-Object {
                $property = $_.PSObject.Properties[$platform.ToLowerInvariant()]
                $null -ne $property -and [string]$property.Value -ceq $projectId
            })
            if ($known.Count) { $locations += Get-SyncVersionLocation $entry $platform.ToLowerInvariant() $projectId }
        }
    }
    $packs += @{ name = $profile.name; root = $packRoot; file = $file; options = $options; groups = @($profile.groups); locations = $locations }
}
if (-not $packs.Count) { throw 'No configured packs selected.' }
foreach ($name in @($Pack)) {
    if ($name -and $name -notin @($packs | ForEach-Object { $_.name })) { throw "No synchronization profile for '$name'." }
}
$request = @{ root = $repoRoot; versions = @($matrix.Versions | ForEach-Object { $_.Id }); packs = $packs; cachedMetadata = [bool]$CachedMetadata }
$tempRequest = Join-Path ([IO.Path]::GetTempPath()) ('compatibility-sync-' + [Guid]::NewGuid().ToString('N') + '.json')
$tempPlan = "$tempRequest.plan.json"
try {
    $request | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tempRequest -Encoding UTF8
    & node (Join-Path $PSScriptRoot 'sync-mod-compatibility.cjs') $tempRequest $tempPlan
    if ($LASTEXITCODE -ne 0) { throw 'Compatibility synchronization failed; pack configuration was not changed.' }
    $plan = Get-Content -LiteralPath $tempPlan -Raw | ConvertFrom-Json
    # Validate every proposed PSD1 before writing any pack configuration.
    foreach ($change in $plan.changes) {
        if ([IO.File]::ReadAllText($change.path) -cne $change.original) { throw "File changed during synchronization: $($change.path)" }
        if ($change.path.EndsWith('.psd1')) {
            $tokens = $null; $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseInput($change.content, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count) { throw "Invalid generated PSD1: $($change.path)" }
        } else { $null = $change.content | ConvertFrom-Json }
    }
    if (-not $Check) {
        foreach ($change in $plan.changes) {
            $bytes = [IO.File]::ReadAllBytes($change.path)
            $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
            [IO.File]::WriteAllText($change.path, $change.content, [Text.UTF8Encoding]::new($bom))
        }
    }
    $reportFile = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot $ReportPath }
    $null = New-Item -ItemType Directory -Path (Split-Path $reportFile -Parent) -Force
    $plan.report | Add-Member -NotePropertyName checkOnly -NotePropertyValue ([bool]$Check)
    $plan.report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $reportFile -Encoding UTF8
    foreach ($message in $plan.report.messages) { Write-Host $message }
    $action = if ($Check) { 'Would update' } else { 'Updated' }
    Write-Host "$action $(@($plan.changes).Count) files. Report: $reportFile"
}
finally {
    foreach ($file in @($tempRequest, $tempPlan)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
}
