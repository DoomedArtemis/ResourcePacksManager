@{
    MinVersion = '1.17'
    Modrinth = @{
        Dependencies = @(
            @{
                ProjectId = 'dl88rsIq' # Dye Depot
                Type = 'optional'
                Versions = @('1.20.1', '1.21.1')
            }
        )
    }
    CurseForge = @{
        Dependencies = @(
            @{
                ProjectId = '988504' # Dye Depot
                Slug = 'dye-depot'
                Type = 'optionalDependency'
                Versions = @('1.20.1', '1.21.1')
            }
        )
    }
    PackMetadata = @{
        name = 'Better Candles'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Melted candle wax'; color = 'yellow' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    Compatibility = @{
        dye_depot = @{
            Versions = @('1.20.1', '1.21.1')
            Support = 'Includes candle models and wax puddles for Dye Depot.'
        }
    }
}
