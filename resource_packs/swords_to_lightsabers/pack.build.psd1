@{
    MinVersion = '1.13'
    PackMetadata = @{
        name = 'Swords to Lightsabers'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Glowing lightsabers'; color = 'aqua' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    FileRules = @(
        @{
            Path = 'textures/item/netherite_sword.png'
            MinVersion = '1.16'
        }
        @{
            Path = 'textures/item/copper_sword.png'
            MinVersion = '1.21.9'
        }
    )
}
