@{
    MinVersion = '1.13'
    PackMetadata = @{
        name = 'Flowering Lily Pads'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Blooming lily pads'; color = 'light_purple' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
        FileRules = @(
            @{
                Path = 'textures/block/spore_blossom.png'
                BeforeVersion = '1.17'
            }
            @{
                Path = 'textures/block/spore_blossom_base.png'
                BeforeVersion = '1.17'
            }
        )
}
