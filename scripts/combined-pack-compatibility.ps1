function Merge-CombinedCompatibilityAssets {
    param([hashtable]$Components, [string]$Destination, [hashtable]$Owners, [string]$DefinitionDirectory, [hashtable]$Definition)
    $root = Join-Path $DefinitionDirectory 'compatibility'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($folder in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
        $required = @($folder.Name.Split('+'))
        if (@($required | Where-Object { -not $Components.ContainsKey($_) }).Count) { continue }
        $pack = $required | Sort-Object { $Components[$_].Entry.Priority } -Descending | Select-Object -First 1
        $component = $Components[$pack]
        foreach ($file in Get-ChildItem -LiteralPath $folder.FullName -File -Recurse) {
            $asset = $file.FullName.Substring($folder.FullName.Length + 1).Replace('\', '/')
            if (-not $asset.StartsWith('assets/')) { continue }
            if (-not (Test-CombinedPath -Path $asset -Entry $component.Entry -Definition $Definition)) { continue }
            if ($Owners.ContainsKey($asset) -and $Owners[$asset].Priority -gt $component.Entry.Priority) { continue }
            if ($asset.EndsWith('.json')) { $null = ConvertFrom-CombinedJson ([IO.File]::ReadAllText($file.FullName)) }
            $component.Files[$asset] = $file.FullName
            $component.Included[$asset] = $true
            $target = Join-Path $Destination $asset
            Ensure-Directory (Split-Path $target -Parent)
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $Owners[$asset] = @{ Pack = $pack; Priority = $component.Entry.Priority; Compatibility = $folder.Name }
        }
    }
}
