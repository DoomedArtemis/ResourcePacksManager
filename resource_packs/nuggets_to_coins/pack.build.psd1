@{
    MinVersion = '1.13'
    PackMetadata = @{
        name = 'Nuggets to Coins'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'A little shine for '; color = 'gray' }
            @{ text = 'nugget coins'; color = 'gold' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    FileRules = @(
        @{
            Path = 'textures/item/copper_nugget.png'
            MinVersion = '1.21.9'
        }
    )
    FileVariants = @(
        @{
            Path = 'lang/en_us.json'
            SourcePath = 'variants/1.21.9/drop/lang/en_us.json'
            MinVersion = '1.21.9'
        }
    )
}
