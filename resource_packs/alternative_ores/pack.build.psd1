@{
    MinVersion = '1.13'
    PackMetadata = @{
        name = 'Alternative Ores'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Crystalline ores'; color = 'aqua' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }
    FileOptionsPath = 'variants/ore-versions.json'
    Compatibility = @{
        eternal_starlight = @{
            Versions = @('1.21', '1.21.1')
            Name = 'Eternal Starlight'
        }
        ad_astra = @{
            Versions = @('1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.21.1')
            Name = 'Ad Astra'
        }
        astralsorcery = @{
            Versions = @('1.15.2', '1.16.4', '1.16.5', '1.21.1')
            Name = 'Astral Sorcery'
        }
        neovitae = @{
            Versions = @('1.21.1', '26.1.2')
            Name = 'Neo Vitae'
        }
        aether = @{
            Versions = @('1.19.2', '1.19.4', '1.20.1', '1.20.2', '1.20.4', '1.21.1')
            Name = 'The Aether'
        }
        bigreactors = @{
            Versions = @('1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.20', '1.20.1', '1.20.6', '1.21', '1.21.1', '1.21.4')
            Name = 'Extreme Reactors'
        }
        powah = @{
            Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.2', '1.19.1', '1.19.2', '1.20.1', '1.20.2', '1.20.4', '1.21', '1.21.1', '26.1.2')
            Name = 'Powah!'
        }
        silentgems = @{
            Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.2')
            Name = 'Silent''s Gems'
        }
        oritech = @{
            Versions = @('1.20.4', '1.21', '1.21.1', '26.1', '26.1.2')
            Name = 'Oritech'
        }
        undergarden = @{
            Versions = @('1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18.1', '1.18.2', '1.19.2', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1.2')
            Name = 'The Undergarden'
        }
        deeperdarker = @{
            Versions = @('1.19', '1.19.1', '1.19.2', '1.20', '1.20.1', '1.20.2', '1.20.3', '1.20.4', '1.21', '1.21.1')
            Name = 'Deeper and Darker'
        }
        rftoolsbase = @{
            Versions = @('1.14.3', '1.14.4', '1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21.1')
            Name = 'RFTools Base'
        }
        silentgear = @{
            Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.1', '26.1.2')
            Name = 'Silent Gear'
        }
        occultism = @{
            Versions = @('1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1', '26.1.2', '26.2', '26.3')
            Name = 'Occultism'
        }
        theurgy = @{
            Versions = @('1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '1.21.3', '26.1', '26.1.1', '26.1.2', '26.2', '26.3')
            Name = 'Theurgy'
        }
        xycraft_world = @{
            Versions = @('1.19.2', '1.20.1', '1.21', '1.21.1', '26.1', '26.1.1', '26.1.2')
            Name = 'XyCraft World'
        }
        evilcraft = @{
            Versions = @('1.15.2', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.4', '1.21.8', '1.21.10', '1.21.11', '26.1.1', '26.1.2', '26.2', '26.3')
            Name = 'EvilCraft'
        }
        forbidden_arcanus = @{
            Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18.1', '1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21', '1.21.1', '26.1.2')
            Name = 'Forbidden and Arcanus'
        }
        mysticalagradditions = @{
            Versions = @('1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            Name = 'Mystical Agradditions'
        }
        irons_spellbooks = @{
            Versions = @('1.20.1', '1.21', '1.21.1')
            Name = 'Iron''s Spells ''n Spellbooks'
        }
        actuallyadditions = @{
            Versions = @('1.20.4', '1.21.1')
            Name = 'Actually Additions'
        }
        modern_industrialization = @{
            Versions = @('1.18.2', '1.19', '1.19.1', '1.19.2', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1')
            Name = 'Modern Industrialization'
        }
        tconstruct = @{
            Versions = @('1.16.5', '1.18.1', '1.18.2', '1.19.2', '1.20.1')
            Name = 'Tinkers'' Construct'
        }
        mysticalagriculture = @{
            Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            Name = 'Mystical Agriculture'
        }
        ars_nouveau = @{
            Versions = @('1.15', '1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1')
            Name = 'Ars Nouveau'
        }
        draconicevolution = @{
            Versions = @('1.16.5', '1.18.2', '1.20.1', '1.20.4', '1.21.1')
            Name = 'Draconic Evolution'
        }
        allthemodium = @{
            Versions = @('1.15.2', '1.16.1', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20.1', '1.21', '1.21.1', '26.1.2')
            Name = 'Allthemodium'
        }
        immersiveengineering = @{
            Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21.1')
            Name = 'Immersive Engineering'
        }
        alltheores = @{
            Versions = @('1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            Name = 'ATO - All the Ores'
        }
        create = @{
            Versions = @('1.14.4', '1.15.2', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20.1', '1.21.1')
            Name = 'Create'
        }
        appliedenergistics2 = @{
            Versions = @('1.15.2', '1.16.1', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1')
            Name = 'Applied Energistics 2'
        }
        ae2 = @{
            Versions = @('1.18', '1.18.1', '1.18.2')
            Name = 'Applied Energistics 2'
        }
        mekanism = @{
            Versions = @('1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.20.1', '1.20.4', '1.21', '1.21.1')
            Name = 'Mekanism'
        }
    }
    CurseForge = @{
        Dependencies = @(
            @{
                ProjectId = '1080592' # Eternal Starlight
                Slug = 'eternal-starlight'
                Type = 'optionalDependency'
                Versions = @('1.21', '1.21.1')
            }
            @{
                ProjectId = '635042' # Ad Astra
                Slug = 'ad-astra'
                Type = 'optionalDependency'
                Versions = @('1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = '241721' # Astral Sorcery
                Slug = 'astral-sorcery'
                Type = 'optionalDependency'
                Versions = @('1.15.2', '1.16.4', '1.16.5', '1.21.1')
            }
            @{
                ProjectId = '1404763' # Neo Vitae
                Slug = 'neovitae'
                Type = 'optionalDependency'
                Versions = @('1.21.1', '26.1.2')
            }
            @{
                ProjectId = '255308' # The Aether
                Slug = 'aether'
                Type = 'optionalDependency'
                Versions = @('1.19.2', '1.19.4', '1.20.1', '1.20.2', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = '250277' # Extreme Reactors
                Slug = 'extreme-reactors'
                Type = 'optionalDependency'
                Versions = @('1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.20', '1.20.1', '1.20.6', '1.21', '1.21.1', '1.21.4')
            }
            @{
                ProjectId = '633483' # Powah! Rearchitected
                Slug = 'powah-rearchitected'
                Type = 'optionalDependency'
                Versions = @('1.18.2', '1.19.1', '1.19.2', '1.20.1', '1.20.2', '1.20.4', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '352656' # Powah
                Slug = 'powah'
                Type = 'optionalDependency'
                Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5')
            }
            @{
                ProjectId = '220311' # Silent Gems
                Slug = 'silents-gems'
                Type = 'optionalDependency'
                Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.2')
            }
            @{
                ProjectId = '1030830' # Oritech
                Slug = 'oritech'
                Type = 'optionalDependency'
                Versions = @('1.20.4', '1.21', '1.21.1', '26.1', '26.1.2')
            }
            @{
                ProjectId = '379849' # The Undergarden
                Slug = 'the-undergarden'
                Type = 'optionalDependency'
                Versions = @('1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18.1', '1.18.2', '1.19.2', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '659011' # Deeper and Darker
                Slug = 'deeperdarker'
                Type = 'optionalDependency'
                Versions = @('1.19', '1.19.1', '1.19.2', '1.20', '1.20.1', '1.20.2', '1.20.3', '1.20.4', '1.21', '1.21.1')
            }
            @{
                ProjectId = '326041' # RFTools Base
                Slug = 'rftools-base'
                Type = 'optionalDependency'
                Versions = @('1.14.3', '1.14.4', '1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21.1')
            }
            @{
                ProjectId = '297039' # Silent Gear
                Slug = 'silent-gear'
                Type = 'optionalDependency'
                Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.1', '26.1.2')
            }
            @{
                ProjectId = '361026' # Occultism
                Slug = 'occultism'
                Type = 'optionalDependency'
                Versions = @('1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = '430636' # Theurgy
                Slug = 'theurgy'
                Type = 'optionalDependency'
                Versions = @('1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '1.21.3', '26.1', '26.1.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = '653789' # XyCraft World
                Slug = 'xycraft-world'
                Type = 'optionalDependency'
                Versions = @('1.19.2', '1.20.1', '1.21', '1.21.1', '26.1', '26.1.1', '26.1.2')
            }
            @{
                ProjectId = '74610' # EvilCraft
                Slug = 'evilcraft'
                Type = 'optionalDependency'
                Versions = @('1.15.2', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.4', '1.21.8', '1.21.10', '1.21.11', '26.1.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = '309858' # Forbidden and Arcanus
                Slug = 'forbidden-arcanus'
                Type = 'optionalDependency'
                Versions = @('1.13.2', '1.14.2', '1.14.3', '1.14.4', '1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18.1', '1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '256247' # Mystical Agradditions
                Slug = 'mystical-agradditions'
                Type = 'optionalDependency'
                Versions = @('1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '855414' # Irons Spells and Spellbooks
                Slug = 'irons-spells-n-spellbooks'
                Type = 'optionalDependency'
                Versions = @('1.20.1', '1.21', '1.21.1')
            }
            @{
                ProjectId = '228404' # Actually Additions
                Slug = 'actually-additions'
                Type = 'optionalDependency'
                Versions = @('1.20.4', '1.21.1')
            }
            @{
                ProjectId = '405388' # Modern Industrialization
                Slug = 'modern-industrialization'
                Type = 'optionalDependency'
                Versions = @('1.18.2', '1.19', '1.19.1', '1.19.2', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1')
            }
            @{
                ProjectId = '74072' # Tinkers Construct
                Slug = 'tinkers-construct'
                Type = 'optionalDependency'
                Versions = @('1.16.5', '1.18.1', '1.18.2', '1.19.2', '1.20.1')
            }
            @{
                ProjectId = '246640' # Mystical Agriculture
                Slug = 'mystical-agriculture'
                Type = 'optionalDependency'
                Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '401955' # Ars Nouveau
                Slug = 'ars-nouveau'
                Type = 'optionalDependency'
                Versions = @('1.15', '1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1')
            }
            @{
                ProjectId = '405593' # ATO - All the Ores (official CurseForge project only)
                Slug = 'ato'
                Type = 'optionalDependency'
                Versions = @('1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '268560' # Mekanism
                Slug = 'mekanism'
                Type = 'optionalDependency'
                Versions = @('1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.20.1', '1.20.4', '1.21', '1.21.1')
            }
            @{
                ProjectId = '223794' # Applied Energistics 2
                Slug = 'applied-energistics-2'
                Type = 'optionalDependency'
                Versions = @('1.15.2', '1.16.1', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2')
            }
            @{
                ProjectId = '328085' # Create
                Slug = 'create'
                Type = 'optionalDependency'
                Versions = @('1.14.4', '1.15.2', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20.1', '1.21.1')
            }
            @{
                ProjectId = '624165' # Create Fabric
                Slug = 'create-fabric'
                Type = 'optionalDependency'
                Versions = @('1.18.2', '1.19.2', '1.20.1')
            }
            @{
                ProjectId = '231951' # Immersive Engineering
                Slug = 'immersive-engineering'
                Type = 'optionalDependency'
                Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = '364466' # Allthemodium (official CurseForge project)
                Slug = 'allthemodium'
                Type = 'optionalDependency'
                Versions = @('1.15.2', '1.16.1', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = '223565' # Draconic Evolution
                Slug = 'draconic-evolution'
                Type = 'optionalDependency'
                Versions = @('1.16.5', '1.18.2', '1.20.1', '1.20.4', '1.21.1')
            }
        )
    }
    Modrinth = @{
        Dependencies = @(
            @{
                ProjectId = 'XvcfUGfB' # Eternal Starlight
                Type = 'optional'
                Versions = @('1.21', '1.21.1')
            }
            @{
                ProjectId = '3ufwT9JF' # Ad Astra
                Type = 'optional'
                Versions = @('1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = 'rvaW4C93' # Neo Vitae
                Type = 'optional'
                Versions = @('1.21.1', '26.1.2')
            }
            @{
                ProjectId = 'YhmgMVyu' # The Aether
                Type = 'optional'
                Versions = @('1.19.2', '1.19.4', '1.20.1', '1.20.2', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = 'idkvShUy' # Extreme Reactors
                Type = 'optional'
                Versions = @('1.16.5', '1.17.1', '1.18.2', '1.19.2', '1.20', '1.20.1', '1.21', '1.21.1')
            }
            @{
                ProjectId = 'KZO4S4DO' # Powah
                Type = 'optional'
                Versions = @('1.18.2', '1.19.1', '1.19.2', '1.20.1', '1.20.2', '1.20.4', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = 'Y036wakZ' # Silent Gems
                Type = 'optional'
                Versions = @('1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.2')
            }
            @{
                ProjectId = '4sYI62kA' # Oritech
                Type = 'optional'
                Versions = @('1.20.4', '1.21', '1.21.1', '26.1', '26.1.2')
            }
            @{
                ProjectId = 'Ejfl5qDL' # The Undergarden
                Type = 'optional'
                Versions = @('1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = 'fnAffV0n' # Deeper and Darker
                Type = 'optional'
                Versions = @('1.19.1', '1.19.2', '1.20', '1.20.1', '1.20.2', '1.20.3', '1.20.4', '1.21', '1.21.1')
            }
            @{
                ProjectId = 'hIO8IsD8' # RFTools Base
                Type = 'optional'
                Versions = @('1.14.3', '1.14.4', '1.15.2', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21.1')
            }
            @{
                ProjectId = '73mSSnCf' # Silent Gear
                Type = 'optional'
                Versions = @('1.13.2', '1.14.4', '1.15.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.11', '26.1', '26.1.1', '26.1.2')
            }
            @{
                ProjectId = 'sbJh4AZw' # Occultism
                Type = 'optional'
                Versions = @('1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '26.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = 'uOVMgoil' # Theurgy
                Type = 'optional'
                Versions = @('1.20', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1', '1.21.3', '26.1', '26.1.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = '3ANq2btA' # EvilCraft
                Type = 'optional'
                Versions = @('1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21', '1.21.1', '1.21.4', '1.21.8', '1.21.10', '1.21.11', '26.1.1', '26.1.2', '26.2', '26.3')
            }
            @{
                ProjectId = 'MdlnLS7Q' # Forbidden and Arcanus
                Type = 'optional'
                Versions = @('1.18.2', '1.19', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = 'pl0jGXIx' # Mystical Agradditions
                Type = 'optional'
                Versions = @('1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = 's4OWxYQQ' # Irons Spells and Spellbooks
                Type = 'optional'
                Versions = @('1.20.1', '1.21', '1.21.1')
            }
            @{
                ProjectId = '4K7Q3nqd' # Actually Additions
                Type = 'optional'
                Versions = @('1.20.4', '1.21.1')
            }
            @{
                ProjectId = 'Gov5Dboq' # Modern Industrialization
                Type = 'optional'
                Versions = @('1.18.2', '1.19', '1.19.2', '1.20.1', '1.20.4', '1.20.6', '1.21', '1.21.1')
            }
            @{
                ProjectId = 'rxIIYO6c' # Tinkers Construct
                Type = 'optional'
                Versions = @('1.16.5', '1.18.2', '1.19.2', '1.20.1')
            }
            @{
                ProjectId = 'C95ReXie' # Mystical Agriculture
                Type = 'optional'
                Versions = @('1.14.4', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.1', '1.18.2', '1.19.1', '1.19.2', '1.19.3', '1.19.4', '1.20', '1.20.1', '1.21', '1.21.1', '26.1.2')
            }
            @{
                ProjectId = 'TKB6INcv' # Ars Nouveau
                Type = 'optional'
                Versions = @()
            }
            @{
                ProjectId = 'Ce6I4WUE' # Mekanism
                Type = 'optional'
                Versions = @('1.15.1', '1.15.2', '1.16.1', '1.16.3', '1.16.4', '1.16.5', '1.18.2', '1.19', '1.19.1', '1.19.2', '1.20.1', '1.20.4', '1.21', '1.21.1')
            }
            @{
                ProjectId = 'XxWD5pD3' # Applied Energistics 2
                Type = 'optional'
                Versions = @('1.15.2', '1.16.1', '1.16.2', '1.16.3', '1.16.4', '1.16.5', '1.17.1', '1.18', '1.18.1', '1.18.2')
            }
            @{
                ProjectId = 'LNytGWDc' # Create
                Type = 'optional'
                Versions = @('1.14.4', '1.15.2', '1.16.3', '1.16.4', '1.16.5', '1.18', '1.18.1', '1.18.2', '1.19.2', '1.20.1', '1.21.1')
            }
            @{
                ProjectId = 'Xbc0uyRg' # Create Fabric
                Type = 'optional'
                Versions = @('1.18.2', '1.19.2', '1.20.1')
            }
            @{
                ProjectId = 'tIm2nV03' # Immersive Engineering
                Type = 'optional'
                Versions = @('1.16.5', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20.1', '1.20.4', '1.21.1')
            }
            @{
                ProjectId = 'nBqivi8H' # Draconic Evolution
                Type = 'optional'
                Versions = @('1.16.5', '1.18.2', '1.20.1', '1.20.4', '1.21.1')
            }
        )
    }
}
