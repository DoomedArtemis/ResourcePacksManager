# Artemis Texture Pack Builder

This repository now builds texture packs from folders under `resource_packs/`.

## Top-level structure

```text
resource_packs/   source packs you edit
scripts/          build, scaffold, and release-matrix maintenance scripts
config/           builder config plus generated Minecraft release matrix
build/            generated zip outputs grouped by pack
cache/            cached Mojang asset catalogs and remembered route maps
.github/          CI workflow
```

Each folder inside `resource_packs/` is one source pack. The folder name becomes the pack name for output files and the default in-game description.

## Pack layout

Example:

```text
resource_packs/
  alternative_birch_leaves/
    pack.png
    assets/
      minecraft/
        textures/
        models/
    drop/
```

For your current pack, the builder reads:

- `resource_packs/alternative_birch_leaves/pack.png`
- `resource_packs/alternative_birch_leaves/drop/**`
- `resource_packs/alternative_birch_leaves/pack.build.psd1`

and leaves those source files untouched.

## Two input modes

### 1. Canonical assets

Put files under `assets/...` when you already know the exact target path.

Example:

```text
resource_packs/alternative_birch_leaves/assets/minecraft/textures/block/birch_leaves.png
```

The builder copies that into the finished pack and then applies version-specific rewrites like `block -> blocks` for old Minecraft versions.

### 2. Typed auto-sort uploads

Put files into typed subfolders under `drop/` when you want the project to figure out the vanilla target path automatically.

Example:

```text
resource_packs/alternative_birch_leaves/drop/textures/block/birch_leaves.png
resource_packs/alternative_birch_leaves/drop/textures/item/stone_pickaxe.png
resource_packs/alternative_birch_leaves/drop/textures/particle/flame.png
resource_packs/alternative_birch_leaves/drop/models/block/birch_leaves.json
resource_packs/alternative_birch_leaves/drop/models/item/stone_pickaxe.json
resource_packs/alternative_birch_leaves/drop/blockstates/birch_leaves.json
```

Available typed drop folders:

- `drop/textures/`
- `drop/models/`
- `drop/blockstates/`
- `drop/lang/`
- `drop/font/`
- `drop/particles/`
- `drop/atlases/`
- `drop/shaders/`
- `drop/sounds/`
- `drop/texts/`

Recommended subfolders where the asset class splits by purpose:

- `drop/textures/block/`
- `drop/textures/item/`
- `drop/textures/particle/`
- `drop/models/block/`
- `drop/models/item/`

The builder downloads or reuses an official Mojang asset catalog per Minecraft version, narrows the lookup by typed folder, and places the file into the correct `assets/...` path in the generated output.

It also remembers the resolved output path of each dropped source file per pack and per Minecraft version under:

- `cache/vanilla-asset-catalogs/resolved-pack-routes/<pack>/<version>.json`

`cache/` is disposable local build acceleration data. If you delete it, the next build recreates what it needs.

Notes:

- `pack.png` is never sorted into `assets/minecraft`; it stays at the resource-pack root.
- For textures and models, prefer the `block/` or `item/` subfolders from the start.
- You can still add deeper subfolders as extra hints, such as `drop/textures/entity/` or `drop/models/gui/`, when Minecraft uses them.
- If a filename is still ambiguous inside the selected asset class, the build fails and tells you which target paths matched. In that case, either add a more specific subfolder hint or place that file under `assets/...` yourself.
- `assets/...` remains the fallback for anything custom or unclear.

## Per-pack version selection

Each pack can decide which Minecraft versions it should build by adding:

```text
resource_packs/<pack>/pack.build.psd1
```

Example:

```powershell
@{
    MinVersion = '1.13'
}
```

That means the pack will be generated for every configured release version from `1.13` upward.

You can also exclude versions instead:

```powershell
@{
    ExcludeVersions = @(
        '1.12.2'
    )
}
```

You can also select version ranges based on the order of versions in the global config.

Inclusive range:

```powershell
@{
    MinVersion = '1.16.5'
    MaxVersion = '1.20.4'
}
```

Exclusive range:

```powershell
@{
    AfterVersion = '1.12.2'
    BeforeVersion = '1.21.9'
}
```

Rules:

- `Versions` is an allow-list for that pack
- `ExcludeVersions` removes versions for that pack
- `MinVersion` and `MaxVersion` are inclusive bounds
- `AfterVersion` and `BeforeVersion` are exclusive bounds
- range comparison uses the order of `Versions` in the global [config/texture-pack.build.psd1](/C:/Users/grego/IdeaProjects/Artemis-Texture-Packs/config/texture-pack.build.psd1)
- if the file does not exist, the pack uses all globally enabled versions
- CLI selection still applies first, then the pack-local filter is applied on top

## Output

The builder generates:

- `build/<pack>/<pack>-<version>.zip`

## Full release matrix

The global version list is generated into:

- `config/minecraft-release-version-matrix.psd1`

That file currently covers every official release version after `1.12.2`, from `1.13` through `26.3`, and the main config loads it automatically.

## `pack.mcmeta` compatibility handling

The builder supports Mojang's current resource-pack metadata breakpoints:

- up to `1.20.1`: `pack_format` only
- `1.20.2` through `1.21.8`: integer `pack_format` plus optional `supported_formats`
- `1.21.9` and newer: `min_format` / `max_format` using Mojang's newer pack-format model

For `1.21.9+`, the generated metadata no longer writes `pack_format` or `supported_formats`. It emits `min_format` and `max_format` directly so packs show up as compatible in the resource-pack selection UI.

## Local build

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1
```

## IntelliJ run targets

This repo now includes shared IntelliJ run configurations under `.run/`.

In IntelliJ, use the run-config dropdown at the top right and select:

- `Build All Texture Packs`
- `Build All Texture Packs For Version Range`
- `Build Selected Texture Packs`
- `Create New Texture Pack`
- `Dry Run Modrinth Publish All`
- `Dry Run Modrinth Publish Selected`
- `Dry Run Modrinth Publish Version Range`
- `Publish All Resource Packs to Modrinth`
- `Publish Selected Resource Packs to Modrinth`

`Build All Texture Packs` runs the full builder in the IntelliJ terminal.

`Build All Texture Packs For Version Range` prompts for one version, an inclusive version range like `1.20.4..1.21.11`, or a comma-separated mix, then builds every pack for that selection.

`Build Selected Texture Packs` uses the main build script, prompts for one or more pack names, and then builds only that selection.

`Create New Texture Pack` starts the scaffold script and prompts for the pack name in the IntelliJ terminal.

The Modrinth dry-run targets use the ZIPs that already exist under `build/`, validate them, compute the Modrinth version names/numbers, and print what would be uploaded without creating anything on Modrinth. They prompt for a version selection, so you can enter `all`, one version like `1.13`, a range like `1.13.1 to 1.20.1`, or a comma-separated mix. The selected-pack Modrinth run targets also prompt for the Modrinth project, where you can paste a full project URL, slug, or project ID.

The Modrinth publish targets also use the existing ZIPs under `build/`. They prompt for the version selection, prompt for your token at runtime, and ask you to type `PUBLISH` before any upload starts.

## Create a new pack

In IntelliJ, run `Create New Texture Pack`, enter the pack name, and the repo will create the full folder scaffold under `resource_packs/`.

It creates:

- `pack.build.psd1`
- `assets/minecraft/`
- `drop/textures/block/`
- `drop/textures/item/`
- `drop/textures/particle/`
- `drop/models/block/`
- `drop/models/item/`
- the other typed `drop/` folders

You can also run it directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-texture-pack.ps1 -Name stone_tools -MinVersion 1.13
```

Use the PowerShell scripts directly or the shared IntelliJ run targets in `.run/`.

Useful commands:

```powershell
# list available packs
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListPacks

# list configured versions
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListVersions

# build one pack
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack alternative_birch_leaves

# build all packs for one version
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Version 1.21.11

# build one pack for selected versions
powershell -ExecutionPolicy Bypass -Command "& '.\scripts\build-texture-packs.ps1' -Pack alternative_birch_leaves -Version @('1.13','1.20.4','26.3')"

# build all packs for an inclusive version range
powershell -ExecutionPolicy Bypass -Command "& '.\scripts\build-texture-packs.ps1' -Version @('1.20.4','1.20.5','1.20.6')"

# clear only temporary staging data; existing build zips stay in place
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Clean
```

Build ZIP retention:

- existing `build/<pack>/<pack>-<version>.zip` files stay in place across later builds
- rebuilding the exact same pack/version replaces only that matching ZIP
- `-Clean` clears temporary staging under the system temp directory and does not delete retained ZIPs

## Modrinth publishing

The publisher uses ZIPs already present under `build/` by default. It does not rebuild packs unless you pass `-Build`.

This command does not upload anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1
```

If you explicitly want to rebuild before publishing or dry-running, add `-Build`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Build -Pack alternative_birch_leaves -Version 1.13
```

Real publishing requires `-Publish`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Publish -PromptForToken
```

Use a Modrinth personal access token with the `VERSION_CREATE` scope. After a successful upload, the publisher saves the resolved Modrinth project ID and token for that pack in `config/modrinth.local.psd1`. That file is ignored by git and the script refuses to use it if it is ever tracked, because it can contain real tokens.

The shared IntelliJ publish run configurations already use `-PromptForToken`. The first successful upload stores the token locally; later runs reuse the saved token for that pack and only prompt when a selected pack does not have one yet.

The publish run configurations also use `-PromptForChangelog`. Type a changelog for that upload run, or press Enter to send an empty changelog. This value is temporary and is not saved to `config/modrinth.local.psd1`.

They also use `-PromptForReleaseVersion`. Enter a release version like `1.0.0`; the publisher combines it with each Minecraft version, so Minecraft `26.3` uploads with the version number and ZIP filename `1.0.0-mc.26.3`. Press Enter to use the configured default.

For local-only automation, the script also supports reading `MODRINTH_TOKEN` from your environment when `-PromptForToken` is omitted:

```powershell
[Environment]::SetEnvironmentVariable('MODRINTH_TOKEN', '<your-token>', 'User')
```

If you use that environment variable, open a new terminal or restart IntelliJ after setting it.

By default, each pack is published to the Modrinth project with the same slug as the source folder name. If the Modrinth slug differs, set `ProjectUrl` so the publisher uses the exact project page.

Add a `Modrinth` block to that pack's `pack.build.psd1`:

```powershell
@{
    MinVersion = '1.13'
    Modrinth = @{
        ProjectUrl = 'https://modrinth.com/resourcepack/alternative-birch-leaves'
        ReleaseVersion = '1.0.0'
    }
}
```

You can also use `ProjectId`, `Project`, or `Slug` instead of `ProjectUrl` if you prefer Modrinth's project ID or slug.

When using `Publish Selected Resource Packs to Modrinth`, the script asks for the project interactively. Press Enter to use the configured value, or paste one of these:

```text
https://modrinth.com/resourcepack/alternative-birch-leaves
alternative-birch-leaves
AABBCCDD
```

Useful optional fields:

```powershell
Modrinth = @{
    ProjectUrl = 'https://modrinth.com/resourcepack/alternative-birch-leaves'
    ReleaseVersion = '1.0.0'
    VersionNumberTemplate = '{ReleaseVersion}-mc.{MinecraftVersion}'
    NameTemplate = '{PackDisplayName} {ReleaseVersion} for Minecraft {MinecraftVersion}'
    Changelog = ''
    VersionType = 'release'
    Status = 'listed'
    Featured = $false
    Environment = 'client_only'
}
```

The generated Modrinth version number includes the Minecraft version, such as `1.0.0-mc.1.21.11`, because Modrinth requires version numbers to be unique within a project.

The publisher validates every selected ZIP before upload:

- the ZIP must exist under `build/<pack>/`
- the ZIP must contain root `pack.mcmeta`
- the generated Modrinth version number must be valid
- `VersionType` and `Status` must be supported Modrinth values

When `-Publish` is used, the script reads existing Modrinth versions first and skips version numbers that already exist.

Before each upload, the publisher creates a temporary copy of the build ZIP using the uploaded filename, such as `<pack>-1.0.0-mc.26.3.zip`, so the remote file uses that name instead of the build filename `<pack>-26.3.zip`.

After each successful upload, the exact ZIP contents that were uploaded are moved from `build/<pack>/` to `archive/<pack>/<releaseVersion>/` and renamed with the same uploaded version filename, such as `archive/<pack>/1.0.0/<pack>-1.0.0-mc.26.3.zip`. If the same archive file already exists with the same SHA-256 hash, the duplicate build copy is removed. If the archive path already exists with different contents, the new upload copy is kept with an `-uploaded-<timestamp>` suffix.

Examples:

```powershell
# dry run one pack for one version
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Pack alternative_birch_leaves -Version 1.21.11

# dry run one pack for a version range
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Pack alternative_birch_leaves -Version @('1.13.1','1.14','1.14.1')

# publish one pack for one version
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Publish -PromptForToken -Pack alternative_birch_leaves -Version 1.21.11

# publish with a changelog for this run only
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Publish -PromptForToken -Changelog "Updated pack metadata." -Pack alternative_birch_leaves -Version 1.21.11

# publish with a release version for this run only; uploads as alternative_birch_leaves-1.0.0-mc.26.3.zip
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Publish -PromptForToken -ReleaseVersion 1.0.0 -Pack alternative_birch_leaves -Version 26.3

# publish everything
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Publish -PromptForToken
```

## GitHub Actions

The workflow at [.github/workflows/build-packs.yml](/C:/Users/grego/IdeaProjects/Artemis-Texture-Packs/.github/workflows/build-packs.yml) builds packs automatically when pack sources, config, or scripts change.

## Release matrix maintenance

`scripts/sync-minecraft-release-matrix.ps1` is not part of normal local builds. Keep it for the rare case where Mojang adds new release versions and you want to regenerate [config/minecraft-release-version-matrix.psd1](/C:/Users/grego/IdeaProjects/Artemis-Texture-Packs/config/minecraft-release-version-matrix.psd1) from official metadata.

## Current source pack

Your first pack is here:

- [resource_packs/alternative_birch_leaves](/C:/Users/grego/IdeaProjects/Artemis-Texture-Packs/resource_packs/alternative_birch_leaves)

Its current asset files are in typed `drop/...` folders, and the builder now resolves them automatically for every release version from `1.13` through `26.3`.
