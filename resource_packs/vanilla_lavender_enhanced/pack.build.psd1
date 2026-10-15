@{
    MinVersion = '1.13'
    PackMetadata = @{
        name = 'Vanilla Lavender Enhanced'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Lavender in full bloom'; color = 'light_purple' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    FileVariants = @(
        @{
            Path = 'assets/minecraft/textures/block/lavender_tall.png'
            SourcePath = 'variants/1.13/assets/minecraft/textures/block/lavender_tall.png'
            MinVersion = '1.13'
            MaxVersion = '1.13.2'
        }
        @{
            Path = 'assets/minecraft/models/block/lilac_bottom.json'
            SourcePath = 'variants/1.13/assets/minecraft/models/block/lilac_bottom.json'
            MinVersion = '1.13'
            MaxVersion = '1.13.2'
        }
    )
}
