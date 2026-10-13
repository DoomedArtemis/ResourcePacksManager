@{
    MinVersion = '1.17'
    PackMetadata = @{
        name = 'Better Candles'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'A warm touch of '; color = 'gray' }
            @{ text = 'melted candle wax'; color = 'yellow' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    Compatibility = @{
        dye_depot = @{
            # Published Minecraft versions checked on Modrinth and CurseForge.
            # https://modrinth.com/mod/dye-depot/versions
            # https://www.curseforge.com/minecraft/mc-mods/dye-depot/files/all
            Versions = @('1.20.1', '1.21.1')
            Support = @'
Better Candles includes support for Dye Depot's 16 additional candle colors.
Matching candle models and wax puddles, with no separate compatibility pack needed.

Modrinth: https://modrinth.com/mod/dye-depot
CurseForge: https://www.curseforge.com/minecraft/mc-mods/dye-depot
GitHub: https://github.com/PssbleTrngle/dye_depot
'@
        }
    }
}
