[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modelRoot = Join-Path $PSScriptRoot '../resource_packs/better_moss/assets/minecraft/models/block/better_moss_details'
$models = @(Get-ChildItem -LiteralPath $modelRoot -Filter 'seams*.json')
if ($models.Count -eq 0) {
    throw 'No mossy stone seam models found.'
}

foreach ($file in $models) {
    $model = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    # Explicit elements replace inherited geometry, so every seam variant must
    # include the stone itself, not just its decoration (or an empty list).
    $stone = @($model.elements | Where-Object {
        $_.to[0] -gt $_.from[0] -and
        $_.to[1] -gt $_.from[1] -and
        $_.to[2] -gt $_.from[2] -and
        @($_.faces.PSObject.Properties.Value.texture | Where-Object {
            $_ -eq '#seam_growth' -or $_ -like '#detail_*'
        }).Count -eq 0
    })
    if ($stone.Count -eq 0) {
        throw "Seam variant has no solid stone geometry: $($file.Name)"
    }
}

Write-Output "Validated solid stone geometry in all $($models.Count) seam variants."
