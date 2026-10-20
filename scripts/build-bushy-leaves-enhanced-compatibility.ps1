[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BasePackZip,
    [Parameter(Mandatory = $true)][string[]]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputZip
)

# Build a private, complete pack for exactly the installed mod versions. Read
# resource data only; never execute a mod JAR or change the installed mods.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Web.Extensions
$serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$serializer.MaxJsonLength = [int]::MaxValue
$serializer.RecursionLimit = 200
$encoding = New-Object System.Text.UTF8Encoding($false)
$basePath = (Resolve-Path -LiteralPath $BasePackZip).Path
$destination = [IO.Path]::GetFullPath($OutputZip)
if (Test-Path -LiteralPath $destination) { throw "Output already exists: $destination" }
$archives = New-Object 'System.Collections.Generic.List[string]'
foreach ($input in $InputPath) {
    $resolved = Get-Item -LiteralPath $input
    if ($resolved.PSIsContainer) {
        foreach ($file in @(Get-ChildItem -LiteralPath $resolved.FullName -File | Where-Object { $_.Extension -in @('.jar', '.zip') } | Sort-Object Name)) { $archives.Add($file.FullName) }
    } else { $archives.Add($resolved.FullName) }
}
if (-not $archives.Count) { throw 'No mod JARs or resource pack ZIPs found.' }
$data = @{ models = @{}; blockstates = @{}; tags = @{} }
foreach ($archivePath in $archives) {
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $assetPath = $entry.FullName
            if ($assetPath -notmatch '^(?:assets/([a-z0-9_.-]+)/(models|blockstates)/([a-z0-9_./-]+)\.json|data/([a-z0-9_.-]+)/tags/blocks?/([a-z0-9_./-]+)\.json)$') { continue }
            $namespace = $Matches[1]; $kind = $Matches[2]; $relative = $Matches[3]
            if (-not $namespace) { $namespace = $Matches[4]; $kind = 'tags'; $relative = $Matches[5] }
            if ($relative.Split('/') -contains '..') { throw "Unsafe asset path: $assetPath" }
            if ($entry.Length -gt 4MB) { throw "Oversized resource JSON: $assetPath" }
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $json = $serializer.DeserializeObject($reader.ReadToEnd()) } finally { $reader.Dispose() }
            $key = "${namespace}:$relative"
            if ($kind -eq 'tags') {
                # Block tags merge across mods unless explicitly replaced.
                if (-not $data.tags.ContainsKey($key) -or ($json.ContainsKey('replace') -and $json.replace)) { $data.tags[$key] = @{ values = @() } }
                if ($json.ContainsKey('values')) { $data.tags[$key].values = @($data.tags[$key].values) + @($json.values) }
            } else {
                # Later archives win, matching explicit resource-pack precedence.
                $data[$kind][$key] = $json
            }
        }
    } finally { $archive.Dispose() }
}
$working = Join-Path ([IO.Path]::GetTempPath()) ('bushy-leaves-enhanced-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $working
try {
    $inputJson = Join-Path $working 'input.json'
    $overlay = Join-Path $working 'overlay'
    [IO.File]::WriteAllText($inputJson, $serializer.Serialize($data), $encoding)
    & node (Join-Path $PSScriptRoot 'bushy-leaves-enhanced-compatibility.cjs') $inputJson $overlay
    if ($LASTEXITCODE -ne 0) { throw 'Leaf compatibility scan failed.' }
    # Copy into a new ZIP; preserve base metadata, licenses and original assets.
    $base = [IO.Compression.ZipFile]::OpenRead($basePath)
    try {
        if (-not $base.GetEntry('assets/bushy_leaves_enhanced/models/block/broad_0.json') -or -not $base.GetEntry('pack.mcmeta')) { throw 'BasePackZip must be a built Bushy Leaves Enhanced pack.' }
    } finally { $base.Dispose() }
    $null = New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force
    [IO.File]::Copy($basePath, $destination, $false)
    $output = [IO.Compression.ZipFile]::Open($destination, [IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $overlay -Recurse -File) {
            $relative = $file.FullName.Substring($overlay.Length + 1).Replace('\', '/')
            $existing = $output.GetEntry($relative)
            if ($existing) { $existing.Delete() }
            $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($output, $file.FullName, $relative)
        }
    } finally { $output.Dispose() }
    Write-Host "Created $destination"
    Write-Host 'Use this ZIP instead of the base ZIP. Inspect scan-report.json for exceptions. Regenerate after changing mod versions.'
} finally {
    # Only this invocation's GUID-named temporary directory can be removed.
    $resolvedWorking = [IO.Path]::GetFullPath($working)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedWorking.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedWorking -Leaf) -match '^bushy-leaves-enhanced-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolvedWorking -Recurse -Force
    }
}
