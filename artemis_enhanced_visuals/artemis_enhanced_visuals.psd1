@{
    Name = 'artemis_enhanced_visuals'
    DisplayName = 'Artemis Enhanced Visuals'

    PackMetadata = @{
        name = 'Artemis Enhanced Visuals'
        author = 'DoomedArtemis'
        description = @(
            @{ text = 'Enhanced Vanilla visuals'; color = 'aqua' }
            @{ text = ' by '; color = 'gray' }
            @{ text = 'Artemis'; color = 'gold' }
        )
    }

    IconPath = 'artemis_enhanced_visuals/pack.png'

    Packs = @(
        @{ Name = 'bushy_leaves_enhanced'; Enabled = $true; Priority = 5 }
        @{ Name = 'alternative_birch_leaves'; Enabled = $true; Priority = 10 }
        @{ Name = 'alternative_end_rod'; Enabled = $true; Priority = 20 }
        @{ Name = 'alternative_mud_color'; Enabled = $true; Priority = 30 }
        @{ Name = 'alternative_nether_portal_color'; Enabled = $true; Priority = 40 }
        @{ Name = 'alternative_ores'; Enabled = $true; Priority = 45 }
        @{ Name = 'amethyst_to_jade'; Enabled = $false; Priority = 50 }
        @{ Name = 'better_cake_slices'; Enabled = $true; Priority = 60 }
        @{ Name = 'better_candles'; Enabled = $true; Priority = 70 }
        @{ Name = 'better_carpets'; Enabled = $true; Priority = 80 }
        @{ Name = 'better_grass'; Enabled = $true; Priority = 90 }
        @{ Name = 'better_moss'; Enabled = $true; Priority = 100 }
        @{ Name = 'flowering_lily_pads'; Enabled = $true; Priority = 110 }
        @{ Name = 'flowering_oak_leaves'; Enabled = $true; Priority = 120 }
        @{ Name = 'nuggets_to_coins'; Enabled = $false; Priority = 130 }
        @{ Name = 'swords_to_lightsabers'; Enabled = $false; Priority = 140 }
        @{ Name = 'vanilla_lavender'; Enabled = $true; Priority = 150 }
        @{ Name = 'vanilla_lavender_enhanced'; Enabled = $false; Priority = 160 }
    )

    Exclude = @()
}
