@{
    MinVersion = '1.17'
    FileOptionsPath = 'variants/legacy-solid/manifest.json'
    FileVariants = @(


        @{
            Path = 'assets/minecraft/blockstates/infested_mossy_stone_bricks.json'
            SourcePath = 'assets/minecraft/blockstates/mossy_stone_bricks.json'
            BeforeVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/models/item/infested_mossy_stone_bricks.json'
            SourcePath = 'variants/before-pale-garden/assets/minecraft/models/item/infested_mossy_stone_bricks.json'
            BeforeVersion = '1.21.4'
        }


    )
    FileRules = @(
        @{
            Path = 'assets/minecraft/models/block/better_infested_stone/'
            MinVersion = '1.21.4'
        }








        @{
            Path = 'assets/minecraft/blockstates/pale_hanging_moss.json'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/textures/block/pale_clover.png'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/textures/block/pale_blooming_clover.png'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/textures/block/pale_moss_decoration_stem.png'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/textures/block/pale_moss_sprouts.png'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/models/block/better_pale_moss/'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/models/block/pale_moss_carpet.json'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/blockstates/pale_moss_block.json'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/blockstates/pale_moss_carpet.json'
            MinVersion = '1.21.4'
        }
        @{
            Path = 'assets/minecraft/textures/block/wildflowers.png'
            BeforeVersion = '1.21.5'
        }
        @{
            Path = 'assets/minecraft/textures/block/pink_petals.png'
            BeforeVersion = '1.20'
        }
    )
}
