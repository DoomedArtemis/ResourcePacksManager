[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'combined-pack-support.ps1')
foreach ($scriptName in @('publish-modrinth.ps1', 'publish-curseforge.ps1')) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $scriptName), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Publisher syntax errors.' }
    foreach ($node in $ast.EndBlock.Statements) {
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) { Invoke-Expression $node.Extent.Text }
    }
}
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('publish-state-test-' + [Guid]::NewGuid().ToString('N'))
Ensure-Directory $fixture
try {
    $statePath = Join-Path $fixture 'large.psd1'
    $state = @{ Projects = @{} }
    for ($pack = 0; $pack -lt 8; $pack++) {
        $records = @()
        for ($index = 0; $index -lt 100; $index++) {
            $records += @{ ProjectId = '123'; VersionNumber = "1.0.$index-mc1.15.2"; MinecraftVersion = '1.15.2'; FileId = "$index"; PublishedAt = 'fixture' }
        }
        $state.Projects["pack$pack"] = @{ ProjectId = '123'; Token = "fixture-token-$pack"; UpdatedAt = 'fixture'; PublishedFiles = $records }
    }
    Write-LocalCurseForgeState $state $statePath
    $repoRoot = Split-Path $PSScriptRoot -Parent
    foreach ($reader in @('Read-LocalCurseForgeState', 'Read-LocalModrinthState')) {
        $loaded = & $reader -RepoRoot $repoRoot -StatePath $statePath
        if ($loaded.Projects.Count -ne 8) { throw 'Large project table truncated.' }
        foreach ($pack in $state.Projects.Keys) {
            if ($loaded.Projects[$pack].PublishedFiles.Count -ne 100 -or $loaded.Projects[$pack].Token -ne $state.Projects[$pack].Token) { throw 'History or token changed.' }
            foreach ($record in $state.Projects[$pack].PublishedFiles) {
                $actual = @($loaded.Projects[$pack].PublishedFiles | Where-Object { $_.FileId -eq $record.FileId })
                if ($actual.Count -ne 1) { throw 'Published record lost.' }
                foreach ($key in $record.Keys) { if ($actual[0][$key] -cne $record[$key]) { throw 'Published record changed.' } }
            }
        }
    }
    $modrinthPath = Join-Path $fixture 'modrinth.psd1'
    Write-LocalModrinthState $state $modrinthPath
    $loaded = Read-LocalModrinthState $repoRoot $modrinthPath
    if ($loaded.Projects.Count -ne 8 -or $loaded.Projects.pack0.Token -ne 'fixture-token-0') { throw 'Modrinth state roundtrip failed.' }
    $literalPath = Join-Path $fixture 'literals.psd1'
    Set-Content $literalPath '@{ Projects = @{}; Empty = @(); One = @(@{ Value = 1 }); Many = 1,2; Flag = $false; Nothing = $null; Text = ''it''''s literal'' }'
    $loaded = Read-PublishStateDataFile $literalPath
    if ($loaded.Empty.Count -ne 0 -or $loaded.One.Count -ne 1 -or $loaded.One[0].Value -ne 1 -or $loaded.Many.Count -ne 2 -or $loaded.Flag -ne $false -or $null -ne $loaded.Nothing -or $loaded.Text -ne "it's literal") { throw 'PSD1 literal semantics changed.' }
    $marker = Join-Path $fixture 'must-not-exist'
    $malicious = "@{ Projects = @{}; Token = 'fixture-secret'; Dynamic = (Set-Content -LiteralPath '$marker' -Value 'executed') }"
    foreach ($raw in @($malicious, "@{ Token = 'fixture-secret'; Broken = ", "@{ Token = 'fixture-secret' }; Get-Date")) {
        Set-Content $literalPath $raw
        $rejected = $false
        try { Read-PublishStateDataFile $literalPath | Out-Null }
        catch {
            if ($_ | Out-String | Select-String -SimpleMatch 'fixture-secret') { throw 'State contents leaked through error output.' }
            $rejected = $true
        }
        if (-not $rejected -or (Test-Path -LiteralPath $marker)) { throw 'Dynamic/invalid data must be rejected without execution.' }
    }
    Write-Output 'Passed large publishing histories (800 records), both state formats, literal arrays/booleans/nulls, preserved tokens, and rejection of dynamic or malformed data without disclosing contents.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($temporaryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'publish-state-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
