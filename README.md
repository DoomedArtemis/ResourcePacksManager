# Resource Packs Manager

Resource Packs Manager is a PowerShell-based build and publishing workspace for Minecraft Java resource packs. It keeps editable pack sources in `resource_packs/`, generates version-specific resource-pack ZIPs in `build/`, and can prepare or publish those ZIPs to Modrinth.

The project is designed for maintaining multiple small resource packs against many Minecraft releases. A pack can provide canonical Minecraft asset paths directly, or it can place common asset types into typed `drop/` folders and let the builder resolve their final vanilla paths for each target version.

## Repository Layout

```text
resource_packs/   editable source packs, one folder per pack
scripts/          build, scaffold, publish, and version-matrix scripts
config/           global build configuration and Minecraft version matrix
build/            generated ZIP files, grouped by pack
archive/          uploaded or retained release ZIPs, grouped by pack and release
cache/            disposable Mojang asset catalogs and resolved route caches
.run/             shared IntelliJ run configurations
```

`cache/` and `config/modrinth.local.psd1` are ignored by git. The local Modrinth state file may contain project IDs and tokens, and the publisher refuses to use it if it is tracked.

## Pack Sources

Each direct child of `resource_packs/` is treated as one source pack. The folder name is used as the internal pack name, as the default Modrinth slug, and as part of generated ZIP filenames.

A pack may contain:

```text
resource_packs/<pack>/
  pack.png
  pack.build.psd1
  assets/
    minecraft/
      ...
  drop/
    textures/
    models/
    blockstates/
    lang/
    font/
    particles/
    atlases/
    shaders/
    sounds/
    texts/
  variants/
    ...
```

`pack.png` is copied to the root of each generated ZIP. The builder also creates `pack.mcmeta` for each selected Minecraft version, using the configured pack-format metadata for that version.

## Asset Input Modes

The builder supports two source styles.

Canonical assets are files already placed under their final resource-pack path:

```text
resource_packs/<pack>/assets/minecraft/textures/block/<file>.png
```

These files are copied directly into the generated pack. Version-specific path rewrites from the release matrix are still applied, such as older Minecraft path conventions.

Typed drop assets are files placed under `drop/<type>/...`:

```text
resource_packs/<pack>/drop/textures/block/<file>.png
resource_packs/<pack>/drop/models/item/<file>.json
resource_packs/<pack>/drop/lang/en_us.json
```

For dropped files, the builder loads or reuses the official Mojang asset catalog for the selected Minecraft version, searches within the matching asset type, and resolves the correct `assets/minecraft/...` output path. Subfolders such as `block`, `item`, or `particle` act as hints and reduce ambiguity.

If a dropped file could resolve to multiple vanilla paths, the build fails with the matching candidates. In that case, make the hint path more specific or place the file under `assets/` with the exact intended path.

Resolved routes are cached under:

```text
cache/vanilla-asset-catalogs/resolved-pack-routes/<pack>/<version>.json
```

This cache only accelerates later builds. It can be deleted and regenerated.

## Build Configuration

Global build settings live in `config/texture-pack.build.psd1`.

Important settings include:

- `PackRoot`: source-pack root, currently `resource_packs`
- `PackIconFile`: icon filename copied to ZIP root, currently `pack.png`
- `PackBuildConfigFile`: per-pack config filename, currently `pack.build.psd1`
- `CanonicalAssetsFolder`: direct asset folder, currently `assets`
- `AutoSortFolder`: typed drop folder, currently `drop`
- `VersionMatrixPath`: generated Minecraft release matrix
- `AutoSortMappings`: supported typed drop folders and their Minecraft asset prefixes
- `BaseDescription`: default generated pack description template
- `BuildRoot`: generated ZIP root, currently `build`
- `PackageNameTemplate`: generated ZIP basename template
- `Validation`: build-time validation rules

The config supports token replacement in templates. Common tokens are:

- `{PackName}`
- `{PackDisplayName}`
- `{VersionId}`
- `{MinecraftVersion}`
- `{ReleaseVersion}`

## Minecraft Version Matrix

`config/minecraft-release-version-matrix.psd1` contains the configured Minecraft release list and per-version compatibility metadata.

Each version entry can define:

- `Id`: Minecraft version identifier used by build and publish commands
- `PackFormat`: generated `pack.mcmeta` format value
- `SupportedFormats`: optional `supported_formats` metadata
- `Renames`: exact asset path renames
- `PathRewrites`: path prefix rewrites
- `Remove`: output path rules removed for that version
- `Required`: output path rules that must exist
- `PackMetadata`: extra values merged into the `pack` node
- `RootMetadata`: extra root-level metadata merged into `pack.mcmeta`
- `Enabled`: whether the version participates in builds

The current matrix is generated from Mojang metadata and loaded by the global config. `scripts/sync-minecraft-release-matrix.ps1` is the maintenance script for refreshing the matrix when new Minecraft releases need to be added.

## Per-Pack Configuration

Each pack can define `pack.build.psd1` to limit versions, customize publishing, or apply file-level rules.

Version selectors:

```powershell
@{
    Versions = @('1.20.4', '1.21.1')
    ExcludeVersions = @('1.20.5')
    MinVersion = '1.13'
    MaxVersion = '1.21.11'
    AfterVersion = '1.12.2'
    BeforeVersion = '26.1'
}
```

Selector behavior:

- `Versions` is an allow-list
- `ExcludeVersions` removes matching versions
- `MinVersion` and `MaxVersion` are inclusive
- `AfterVersion` and `BeforeVersion` are exclusive
- comparison follows the order in the configured version matrix
- command-line version selection is applied first, then pack-local filtering

File rules include or exclude source files by version:

```powershell
@{
    FileRules = @(
        @{
            Path = 'textures/item/<file>.png'
            MinVersion = '1.20'
        }
    )
}
```

`Path` can match either the source-relative path or the typed drop path. A rule ending in `/` matches everything below that path.

File variants replace one source file with another for selected versions:

```powershell
@{
    FileVariants = @(
        @{
            Path = 'lang/en_us.json'
            SourcePath = 'variants/<version>/drop/lang/en_us.json'
            MinVersion = '1.21.9'
        }
    )
}
```

Variants are useful when a version needs different JSON, textures, or models while preserving the same output path.

## Build Output

The build script generates:

```text
build/<pack>/<pack>-<version>.zip
```

Builds use a temporary staging directory under the system temp folder, then write the final ZIP into `build/`. Existing ZIPs for other versions remain in place. Rebuilding the same pack/version replaces only that matching ZIP.

The generated ZIP contains:

- root `pack.mcmeta`
- root `pack.png`, when present in the source pack
- resolved `assets/minecraft/...` files from `assets/` and `drop/`

Build validation can enforce lowercase output paths, parse generated JSON and `.mcmeta` files, and check texture metadata pairs depending on the global validation settings.

## Pack Metadata

The builder generates `pack.mcmeta` differently depending on the target Minecraft version metadata:

- older versions receive integer `pack_format`
- versions that support it may receive `supported_formats`
- versions using Mojang's newer format model receive `min_format` and `max_format`

The default pack description comes from `BaseDescription` in the global config. Per-version matrix entries can override or extend generated metadata with `Description`, `PackMetadata`, and `RootMetadata`.

## Commands

The scripts can be run directly with PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListPacks
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListVersions
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack <pack>
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Version <version>
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack <pack> -Version <version>
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForPack
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForVersion
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Clean
```

Interactive version selection accepts `all`, a single version, an inclusive range such as `<start>..<end>` or `<start> to <end>`, and comma-separated mixes.

The scaffold script creates a new pack folder using the configured source layout:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-texture-pack.ps1 -Name <pack> -MinVersion <version>
```

The sync script refreshes the generated Minecraft release matrix:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-minecraft-release-matrix.ps1
```

## IntelliJ Run Configurations

Shared IntelliJ run configurations are stored in `.run/`:

- `Build All Texture Packs`
- `Build All Texture Packs For Version Range`
- `Build Selected Texture Packs`
- `Create New Texture Pack`
- `Dry Run Modrinth Publish All`
- `Dry Run Modrinth Publish Selected`
- `Dry Run Modrinth Publish Version Range`
- `Publish All Resource Packs to Modrinth`
- `Publish Selected Resource Packs to Modrinth`

These run the same PowerShell scripts with prompt-based flags for pack, version, project, changelog, release version, and token input.

## Modrinth Publishing

`scripts/publish-modrinth.ps1` prepares Modrinth upload items from ZIPs already present under `build/`. It performs a dry run unless `-Publish` is provided.

Useful publishing parameters:

- `-Pack`: select one or more source packs
- `-Version`: select one or more Minecraft versions or ranges
- `-PromptForPack`: prompt for pack selection
- `-PromptForVersion`: prompt for version selection
- `-PromptForProject`: prompt for Modrinth project references
- `-Build`: build selected ZIPs before publishing
- `-SkipBuild`: use existing ZIPs only
- `-Publish`: create Modrinth versions
- `-CheckRemote`: check existing remote Modrinth versions during dry runs
- `-PromptForToken`: prompt for a token
- `-PromptForChangelog`: prompt for a changelog
- `-ReleaseVersion`: override the release version used in Modrinth version numbers
- `-PromptForReleaseVersion`: prompt for that release version

Project references can be Modrinth resource-pack URLs, project IDs, or slugs. By default, the pack folder name is used as the Modrinth slug unless a project is configured or saved locally.

Per-pack Modrinth settings live in the pack's `pack.build.psd1`:

```powershell
@{
    Modrinth = @{
        ProjectUrl = 'https://modrinth.com/resourcepack/<slug>'
        ReleaseVersion = '1.0.0'
        VersionNumberTemplate = '{ReleaseVersion}-mc.{MinecraftVersion}'
        NameTemplate = '{PackDisplayName} {ReleaseVersion} for Minecraft {MinecraftVersion}'
        Changelog = ''
        VersionType = 'release'
        Status = 'listed'
        Featured = $false
        Environment = 'client_only'
    }
}
```

`ProjectId`, `Project`, or `Slug` can be used instead of `ProjectUrl`. Set `Enabled = $false` inside the `Modrinth` block to exclude a pack from publishing.

The publisher validates every selected upload item before upload:

- the ZIP must exist under `build/<pack>/`
- the ZIP must contain root `pack.mcmeta`
- the generated Modrinth version number must use supported characters
- `VersionType` and `Status` must be valid Modrinth values

Publishing requires a Modrinth personal access token with the `VERSION_CREATE` scope. The token can come from `-PromptForToken`, the `MODRINTH_TOKEN` environment variable, or the ignored local state file at `config/modrinth.local.psd1`.

When publishing, the script reads existing Modrinth versions and skips version numbers that already exist. Uploaded ZIPs are copied with their Modrinth upload filename, then moved from `build/<pack>/` into:

```text
archive/<pack>/<releaseVersion>/<pack>-<releaseVersion>-mc.<minecraftVersion>.zip
```

If the archive path already contains identical contents, the duplicate build copy is removed. If the path exists with different contents, the uploaded copy is kept with a timestamp suffix.

## Licensing

The repository is licensed under the MIT License. See `LICENSE` for the full text.
