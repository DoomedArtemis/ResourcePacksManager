@{
    Name = 'artemis_enhanced_visuals'
    DisplayName = 'Artemis Enhanced Visuals'
    # In-game pack description. Use a multiline @' ... '@ string like the other packs.
    # {PackDisplayName} and {VersionId} are replaced during the build.
    Description = 'A collection of Artemis resource packs that enhances Minecraft''s vanilla visuals while preserving its familiar style.'
    # Optional icon path relative to the repository root.
    IconPath = 'artemis_enhanced_visuals/pack.png'
    # Modrinth/CurseForge publishing options and version selectors can be added here,
    # using the same format as a normal pack.build.psd1.

    # Higher numbers choose the blockstate (explicit, or vanilla for model-only packs).
    # Winning blocks retain their model/parent/texture dependencies in private paths.
    # Other files still use normal file priority. Missing textures are report warnings;
    # missing models and deliberately excluded dependencies still fail.
    # Disabled and unlisted packs are excluded. New packs are never added automatically.
    Packs = @(
        @{ Name = 'alternative_birch_leaves'; Enabled = $true; Priority = 10 }
        @{ Name = 'alternative_end_rod'; Enabled = $true; Priority = 20 }
        @{ Name = 'alternative_mud_color'; Enabled = $true; Priority = 30 }
        @{ Name = 'alternative_nether_portal_color'; Enabled = $true; Priority = 40 }
        @{ Name = 'amethyst_to_jade'; Enabled = $false; Priority = 50 }
        @{ Name = 'better_cake_slices'; Enabled = $true; Priority = 60 }
        @{ Name = 'better_candles'; Enabled = $true; Priority = 70 }
        @{ Name = 'better_carpets'; Enabled = $true; Priority = 80 }
        @{ Name = 'better_moss'; Enabled = $true; Priority = 100 }
        @{ Name = 'flowering_lily_pads'; Enabled = $true; Priority = 110 }
        @{ Name = 'flowering_oak_leaves'; Enabled = $true; Priority = 120 }
        @{ Name = 'nuggets_to_coins'; Enabled = $false; Priority = 130 }
        @{ Name = 'swords_to_lightsabers'; Enabled = $false; Priority = 140 }
        @{ Name = 'vanilla_lavender'; Enabled = $false; Priority = 150 }
        @{ Name = 'vanilla_lavender_enhanced'; Enabled = $true; Priority = 160 }
    )

    # Include/Exclude can also be placed on each pack entry. Rules use final ZIP paths.
    # Include = @('assets/minecraft/textures/*') limits a pack to textures.
    # Exclude = @('assets/minecraft/models/block/moss_carpet.json') excludes one file.
    # A trailing slash matches a directory prefix; wildcards are supported.
    Exclude = @()
}
