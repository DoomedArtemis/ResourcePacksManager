# Resource Packs Manager

Resource Packs Manager is a PowerShell-based build and publishing workspace for Minecraft Java resource packs. It keeps editable individual pack sources in `resource_packs/`, combines selected packs into Artemis Enhanced Visuals, generates version-specific ZIPs in `build/`, and can prepare or publish those ZIPs to Modrinth or CurseForge.

The project is designed for maintaining multiple small resource packs against many Minecraft releases. A pack can provide canonical Minecraft asset paths directly, or it can place common asset types into typed `drop/` folders and let the builder resolve their final vanilla paths for each target version.

## Getting Started

Use Windows PowerShell 5.1 (`powershell.exe`) and run commands from the repository root. The builders use .NET Framework's `System.Web.Extensions`, so PowerShell 7 (`pwsh`) is not a drop-in replacement. IntelliJ is optional; the shared run configurations invoke the same scripts shown below.

Asset routing and combined dependency checks may need internet access to fetch official Mojang metadata and client assets when they are not cached locally. Refreshing the release matrix also downloads official client JARs and may invoke `javap`; put a JDK capable of reading the target releases' class files on `PATH` before running the sync script.

Use a lowercase folder name for each pack; `example_pack` below is a placeholder for your own pack name. List the available packs and configured versions before building:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListPacks
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListVersions
```

1. Create a source pack with `powershell -ExecutionPolicy Bypass -File scripts/new-texture-pack.ps1 -Name example_pack -MinVersion 1.13`, or add an existing pack under `resource_packs/`.
2. Add its assets under `assets/<namespace>/...` or the supported typed `drop/` folders. Configure supported versions, file variants, mod compatibility, and publishing settings in its `pack.build.psd1`.
3. Build it with `powershell -ExecutionPolicy Bypass -File scripts/build-texture-packs.ps1 -Pack example_pack -Version '1.21.4..26.3'`, or use the IntelliJ build configurations. Test the matching ZIP from `build/example_pack/` in Minecraft.
4. Preview an upload with the Modrinth or CurseForge dry-run configuration, then publish using the matching publish configuration. Successful uploads move build ZIPs into `archive/<pack>/<release>/`.
5. To include the pack in Artemis Enhanced Visuals, add it to the combined definition's `Packs` list and choose its priority. Rebuild the combined pack after updating its component releases.

See the sections below for asset routing, version selection, build output, and publishing configuration.

## Repository Layout

```text
resource_packs/            editable source packs, one folder per pack
artemis_enhanced_visuals/  combined-pack definition and icon
scripts/                   build, scaffold, publish, and version-matrix scripts
config/                    global build configuration and Minecraft version matrix
build/                     generated ZIP files, grouped by pack
archive/                   uploaded or retained release ZIPs, grouped by pack and release
cache/                     disposable Mojang asset catalogs and resolved route caches
.run/                      shared IntelliJ run configurations
```

`cache/`, `config/modrinth.local.psd1`, and `config/curseforge.local.psd1` are ignored by git. The local publishing state files may contain project IDs and tokens, and the publishers refuse to use them if they are tracked.

## Artemis Enhanced Visuals

The combined pack is configured separately in `artemis_enhanced_visuals/artemis_enhanced_visuals.psd1`.
Its sources stay outside `resource_packs/`, but it appears alongside normal packs in
build and publish selections. Only its build process differs; normal source packs
and their individual ZIPs keep their existing behavior.

The source folder contains:

```text
artemis_enhanced_visuals/
  artemis_enhanced_visuals.psd1   inclusion, priorities, description, and publishing options
  pack.png                      combined pack icon
```

### Description, icon, and publishing settings

Set the plain-text description using `Description` in the combined definition. It
appears in the generated player README and supplies the in-game description unless
`PackMetadata.description` overrides it. It supports multiline here-string syntax:

```powershell
Description = @'
A collection of Artemis resource packs that enhances Minecraft's vanilla visuals while preserving its familiar style.
For Minecraft {VersionId}.
'@
```

Credits are collected automatically from each included component's credit files
into one ZIP-root `credits.txt`, with headings such as `example_pack:`.
No manual combined credit file or component attribution list is needed.
Each build uses the current repository
`LICENSE` as the ZIP's `license.txt`. Included components' original
license notices are preserved under `licenses/<pack>.txt`, so
third-party attribution and original copyright/license notices remain included.
Use `PackMetadata.description` for colored Minecraft text components in the
resource-pack menu while retaining plain `Description` text for the player README.
Neither setting changes the project page description on Modrinth or CurseForge.

`IconPath = 'artemis_enhanced_visuals/pack.png'` selects the combined icon. Paths are
relative to the repository root; setting `IconPath = ''` omits the icon. Component
pack icons and descriptions are not merged into the combined pack.

`Modrinth`, `CurseForge`, and version selectors such as `MinVersion`, `MaxVersion`,
and `ExcludeVersions` can be placed in this definition using the same settings as
an individual pack's `pack.build.psd1`.

### Automatic credits and component versions

The generated ZIP-root `readme.txt` is written for players: it contains the in-game
description, target Minecraft version, installation instructions, readable pack
names and versions, and pointers to credits and licenses. It does not explain this
manager's archives, source files, reports, or build process. Credit sections keep
the requested identifiers such as `example_pack:` and the original
attribution text; their introduction is also written for players.

The combined builder first looks in `archive/<pack>/<release>/` for each component
and target Minecraft version. It uses the newest release containing a matching ZIP,
comparing numeric versions (so `1.10.0` comes after `1.2.0`). Prerelease ordering is
also supported. Both `mc1.21.11` and legacy `mc.1.21.11` filenames are accepted;
within a release, the most recently modified matching ZIP is used, including
timestamped `-uploaded-` collision copies. ZIPs for other Minecraft versions and
empty release folders do not affect selection. If no matching archive exists,
the component is built from source and listed as `unreleased`.
The player README records the release actually used, rather than the newest
release available for a different Minecraft version.
The same version list is stored as `ComponentVersions` in the build report.

For example, ZIPs in both `archive/example_pack/1.1.0/` and
`archive/example_pack/1.2.0/` produce `Example Pack: 1.2.0` in `readme.txt`.
An empty `1.3.0/` folder does not change that selection. Versions are compared by
their numbers, not folder modification time. Stable releases sort after prereleases
with the same version number, and numeric prerelease identifiers are compared
numerically. Only recognized version folders with ZIP files directly inside count.

Credits are collected from component ZIP-root credit notices such as `credits.txt`
and `CREDITS.txt`, regardless of filename capitalization. Only packs included for
the selected Minecraft version contribute credits and README entries. A pack with
no credits file appears only in the README. Author and credits metadata do not generate attribution. Credit contents are preserved beneath
the pack-name heading; they are not duplicated into separate `credits/<pack>/` files. Component licenses are stored directly in `licenses/`, named after the pack (for example, `vanilla_lavender_enhanced.txt`). If a pack has multiple notices, each filename includes the pack name and original notice filename to preserve them all.

### Inclusion, priority, and dependency handling

Edit its `Packs` list to choose what goes into **Artemis Enhanced Visuals**:

```powershell
@{ Name = 'component_a'; Enabled = $true; Priority = 80 }
@{ Name = 'component_b'; Enabled = $true; Priority = 100 }
@{ Name = 'optional_component'; Enabled = $false; Priority = 140 }
```

Block appearance is selected by **blockstate priority**. Higher priorities win for
the same blockstate; a model-only pack participates using that Minecraft version's
vanilla blockstate when it changes a model used by the block. If two components
change the same block, the higher-priority component supplies that block's appearance
while unrelated blocks keep their other component's changes.
Other assets still use file priority. Equal priorities on a shared path fail with
a conflict message instead of choosing an arbitrary winner.
Disabled packs and packs absent from the list are excluded; new source packs are
never silently included. The definition's `Packs` list is the source of truth for
which components are enabled.

For finer control, add `Include` and/or `Exclude` to a pack entry:

```powershell
@{
    Name = 'component_a'
    Enabled = $true
    Priority = 80
    Include = @('assets/*')
    Exclude = @('assets/minecraft/models/block/<block>.json')
}
```

Rules match final ZIP paths after version routing and rewrites. Wildcards are supported;
a trailing slash matches a directory prefix. Missing `Include` means all assets,
while `Include = @()` includes none. The top-level `Exclude` list removes matching
files from every component. References first use the highest-priority included
file at the required path. If no included file supplies it, a dependency deliberately
excluded from the referencing pack fails the build, even when vanilla has that path.
Missing models and parents also fail with a dependency chain. JSON contents are
not merged by key.

The combined builder walks each winning blockstate's variants and multipart models,
their parents, model overrides, textures, and animation metadata. It also checks
item models and modern item definitions. Every model and texture reference uses
whichever included component has the highest priority at that path, including
parents referenced by lower-priority inventory models. Overridden component assets
are not preserved as private alternatives. For example, Better Moss's moss carpet
models and textures also replace those referenced by Better Carpets' inventory models.
Unchanged vanilla models are supplied by Minecraft itself. Unreferenced generated
dependency copies are removed before packaging.
Reference edits preserve original JSON indentation, property order, inline faces,
number formatting, and line endings. Unchanged component JSON is copied verbatim.
Shorter temporary staging paths accommodate readable model names on Windows.
The report records the original paths and why alternate dependencies were needed;
source packs remain untouched.

Validation checks missing/filtered models and deliberately excluded textures,
parent/reference cycles, and circular texture variables using the effective
child/parent context. Missing texture files and unresolved texture variables such
as `#missing` are allowed: their original references are retained, and they appear
in the report under `Dependencies.TextureWarnings`. Such builds have dependency
status `passed_with_warnings`; they still produce a ZIP normally.
Vanilla models and textures are checked against the **selected Minecraft version**,
including its default blockstates. Vanilla definitions are cached under
`cache/vanilla-asset-catalogs/dependency-data/`; the first check for a version uses
an installed official client JAR or downloads the official JAR and verifies its hash.
It cannot substitute a different version's vanilla assets. An invalid graph stops
the build before replacing an existing ZIP. These checks cover vanilla JSON block
and item model dependencies; custom mod model loaders are outside their scope.

| Dependency issue | Build behavior |
| --- | --- |
| Missing texture file or undefined texture variable such as `#missing` | Keep the reference, record a texture warning, and build the ZIP |
| Missing model or parent model | Fail with the dependency chain |
| Required file deliberately excluded, with no included provider at that path | Fail with the dependency chain |
| Circular model references or texture variables | Fail |
| Component unsupported for the selected Minecraft version | Skip that component and record it in the report |

### Building and generated files

All build commands and IntelliJ build configurations show live PowerShell progress, plus periodic text status updates for output panes that cannot display the progress bar. The overall counter tracks processed pack/version jobs (or completed versions for a direct combined build). Separate counters show the current component, asset routing/copying, dependency checks, and ZIP compression. Stage percentages restart when a new stage begins; they measure completed work items, not elapsed time or an estimated time remaining. Failed jobs remain reported as failures even though they count as processed jobs.

Build using the IntelliJ **Build Artemis Enhanced Visuals** run configuration, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-combined-pack.ps1 -Version 26.2
powershell -ExecutionPolicy Bypass -File .\scripts\build-combined-pack.ps1 -Version '1.17..26.2'
powershell -ExecutionPolicy Bypass -File .\scripts\build-combined-pack.ps1 -PromptForVersion
powershell -ExecutionPolicy Bypass -File .\scripts\build-combined-pack.ps1 -ListPacks
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack artemis_enhanced_visuals -Version 26.2
```

Omitting `-Version` builds every enabled version. Each component uses its existing
version filters; matching archived ZIPs already contain the release's variants
and routed assets. Source fallback uses the normal variants and routing. Unsupported components are
skipped for that Minecraft version and recorded in the report. A version with no
included assets fails. Component icons and descriptions are replaced by the combined
pack's own metadata. Its icon is `artemis_enhanced_visuals/pack.png`, configured by
the repository-relative `IconPath` in the definition.

Outputs are `build/artemis_enhanced_visuals/artemis_enhanced_visuals-<version>.zip`
and a matching `.report.json` under `build/artemis_enhanced_visuals/reports/`:

```text
build/artemis_enhanced_visuals/
  artemis_enhanced_visuals-26.2.zip
  reports/
    artemis_enhanced_visuals-26.2.report.json
```

The ZIP contains `pack.mcmeta`, the configured `pack.png`, assets, a single generated
`credits.txt`, a generated `readme.txt`, the current repository license as
`license.txt`, and applicable component notices under `licenses/<pack>.txt`.

The report describes the same build:

| Field | Contents |
| --- | --- |
| `IncludedPacks` | Enabled components supported by this Minecraft version |
| `UnsupportedPacks` | Enabled components skipped by their version filters |
| `ComponentVersions` | Archived release actually used for each component, or `unreleased` for source fallback |
| `ComponentSources` | Whether each component came from an archive or source, with archived release and ZIP path |
| `Files` | Asset owners, priorities, and original paths for private dependency copies |
| `Dependencies.Blockstates` | Selected blockstate providers, including implicit vanilla blockstates |
| `Dependencies.ResolvedModelCount` | Number of resolved model contexts |
| `Dependencies.Status` | `passed` or `passed_with_warnings` |
| `Dependencies.TextureWarnings` | Nonfatal missing-texture references and their contexts |

Older reports without `Dependencies` were generated before dependency validation
was added and do not establish that those checks passed.

Both publishers delete the matching build report after successfully moving its ZIP
to the archive, including when an identical ZIP is already archived. Dry runs and failed archive moves retain
the report. Archived components are read without modifying their ZIPs. Only missing
components are built in temporary storage, leaving normal build ZIPs untouched.
Archived components still undergo JSON/metadata, lowercase-path, duplicate-path,
required-output, texture-animation pairing, and path safety checks. All merged
model, texture, parent, override, item, and blockstate dependency checks still run.
Each component is extracted once and then merged from that extracted input.
The normal build commands include the combined pack and dispatch it
to the combined builder. Modrinth and CurseForge publishing use their usual ZIP lookup,
project prompts, release versions, duplicate handling, and archive behavior, including
building missing combined ZIPs when requested. Add `Modrinth` and `CurseForge` blocks
to this definition using the same options as normal `pack.build.psd1` files, or use
the usual project prompts and local publishing state. Version selectors such as
`MinVersion` and `ExcludeVersions` are supported at the definition's top level too.

Publish updated component releases to the archive before rebuilding to include
their changed assets and credits. Rebuild to apply changed priorities, descriptions, icons, or
archive version labels. The generated credits, README, and report are snapshots from
that build. Publishing reuses existing archive/build ZIPs; `-Build` builds only a
missing ZIP and does not refresh an existing one.

### Publishing

For example, preview publishing without uploading:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\publish-modrinth.ps1 -Pack artemis_enhanced_visuals -Version 26.2 -SkipBuild
powershell -ExecutionPolicy Bypass -File .\scripts\publish-curseforge.ps1 -Pack artemis_enhanced_visuals -Version 26.2 -PromptForProject -SkipBuild
```

Use the normal publishing run configurations or add `-Publish` to upload. Modrinth
uses the configured/saved project reference or defaults to `artemis_enhanced_visuals`;
CurseForge needs its numeric project ID. Successful uploads use the same
`archive/artemis_enhanced_visuals/<release>/` layout and duplicate handling as the
individual packs.

### Verification commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-combined-pack.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-combined-dependencies.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-combined-publishing.ps1
```

These check inclusion and priority, model and texture references and warnings,
automatic credits and README version selection, publisher discovery, and report
cleanup after successful archive moves.

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

Build descriptions and package-name templates support these tokens:

- `{PackName}`
- `{PackDisplayName}`
- `{VersionId}`

Publishing templates additionally support `{MinecraftVersion}` and `{ReleaseVersion}`.

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

### Mod compatibility versions

Use `Compatibility` to control which Minecraft versions include each mod's assets without restricting the pack's vanilla support:

```powershell
@{
    MinVersion = '1.17'
    Compatibility = @{
        another_mod = @{
            Versions = @('1.20.1', '1.21.1')
        }
        example_mod = @{
            Versions = @('1.20.1..1.21.1', '26.1 to 26.3')
            ExcludeVersions = @('1.20.2', '1.21.5..1.21.8')
            MinVersion = '1.20.1'
            MaxVersion = '26.3'
            # Optional: include files outside assets/example_mod/ too.
            Paths = @('assets/example_mod/', 'assets/minecraft/textures/block/example.png')
            Support = 'Includes support for Example Mod. No separate compatibility pack needed.'
        }
    }
}
```

Each mod ID defaults to filtering `assets/<mod-id>/`. Override `Paths` with exact source-relative or typed drop paths, or directory prefixes ending in `/`. Compatibility paths do not support wildcards. Matching files are included only when their mod's selectors match the selected Minecraft version; ordinary `FileRules` cannot reintroduce incompatible assets. Files outside these paths keep their normal behavior.

Supported selectors are `Versions`, `ExcludeVersions`, `MinVersion`, `MaxVersion`, `AfterVersion`, and `BeforeVersion`. `Versions` and `ExcludeVersions` accept exact versions, inclusive `start..end` or `start to end` ranges, and comma-separated mixes. Ranges follow the configured Minecraft release matrix; multiple selectors apply together. Omit `Versions` to allow all versions within the other bounds, use `Versions = @()` to include none, or set `Enabled = $false` to disable that mod's assets entirely. Unknown versions, reversed bounds, invalid paths, and unknown compatibility options fail the build.

Set `Support` inside each mod entry to a short player-facing note, including any links. It accepts a plain string or a multiline PowerShell here-string. The builder combines notes for enabled compatibilities matching the target version into one ZIP-root `support.txt`, separated by blank lines and ordered by mod ID. Unsupported and disabled mod notes are omitted. No file is generated when no active entry has a nonempty note. Keep the text in `pack.build.psd1`; do not also supply a source `support.txt`, which would conflict with the generated file.

Check a mod's published Minecraft versions before setting its compatibility selectors, and update them when new releases become available. Compatibility configuration filters bundled assets; it does not install or detect mods in a player's game. Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-file-options.ps1` to check compatibility selectors and file routing.

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

`Path` can match either the source-relative path or the typed drop path. For canonical assets, include the full source-relative prefix, such as `assets/minecraft/models/block/<block>.json`; `models/block/<block>.json` is a typed drop path. A rule ending in `/` matches everything below that path. File rules and variants use exact paths or directory prefixes, not wildcards; the combined pack's `Include` and `Exclude` rules separately support wildcards.

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

Large generated rule sets can be stored in a JSON file inside the pack. Set `FileOptionsPath` in `pack.build.psd1` to that file's relative path; its `FileRules` and `FileVariants` arrays are appended to the inline rules. Other option names are rejected.

## Build Output

The build script generates:

```text
build/<pack>/<pack>-<version>.zip
```

Builds use a temporary staging directory under the system temp folder, then write the final ZIP into `build/`. Existing ZIPs for other versions remain in place. Rebuilding the same pack/version replaces only that matching ZIP.

An individual source pack's generated ZIP contains:

- root `pack.mcmeta`
- root `pack.png`, when present in the source pack
- extra files placed directly in the source pack root (such as `LICENSE.txt`)
- generated root `support.txt`, when active `Compatibility` entries define support notes
- files from `extras/`, copied to the ZIP root with their subfolders preserved
- resolved `assets/<namespace>/...` files from `assets/` and `drop/`, including mod namespaces when their compatibility rules allow them

Build validation can enforce lowercase output paths, parse generated JSON and `.mcmeta` files, and check texture metadata pairs depending on the global validation settings.

## Pack Metadata

The builder generates `pack.mcmeta` differently depending on the target Minecraft version metadata:

- older versions receive integer `pack_format`
- versions that support it may receive `supported_formats`
- versions using Mojang's newer format model receive `min_format` and `max_format`

The default pack description comes from `BaseDescription` in the global config. Per-version matrix entries can override or extend generated metadata with `Description`, `PackMetadata`, and `RootMetadata`.

To customize one pack, put a JSON `pack.mcmeta` in its source root. Its fields are merged into generated metadata. You can also set these options in `pack.build.psd1`:

```powershell
@{
    Description = 'My pack for Minecraft {VersionId}'
    PackMetadata = @{
        credits = 'Textures by the original creators'
    }
    RootMetadata = @{
        license = 'See LICENSE.txt'
    }
}
```

For a colored in-game description, omit the top-level `Description` override and define Minecraft text components in `PackMetadata.description`:

```powershell
PackMetadata = @{
    name = 'Example Pack'
    author = 'Your Name'
    description = @(
        @{ text = 'A fresh look for '; color = 'gray' }
        @{ text = 'Minecraft'; color = 'green' }
        @{ text = ' by '; color = 'gray' }
        @{ text = 'Your Name'; color = 'gold' }
    )
}
```

Named Minecraft colors work across older supported versions. The combined definition also accepts `PackMetadata`; its formatted menu description overrides the plain `Description`, while generated documentation keeps the plain text. `PackMetadata.name` also supplies the display name for new upload and archive ZIPs, such as `Example Pack 1.0.0 MC26.2.zip`. The Minecraft menu's pack title comes from the ZIP or folder name; author remains extra metadata. Build filenames stay unchanged. Existing archived ZIPs keep their exact filenames when uploaded to either platform. Archive lookup and the combined builder accept both readable filenames and the older `pack-release-mcversion.zip` / `pack-release-mc.version.zip` formats, including timestamp collision copies.

Metadata precedence is generated version metadata, source `pack.mcmeta`, `RootMetadata`, `PackMetadata`, then `Description`. The builder always retains the target version's generated compatibility fields (`pack_format`, `supported_formats`, `min_format`, `max_format`), even if custom metadata supplies them.

Put documentation such as `license.txt` directly in the source pack root. Use `extras/` for nested extra files; for example, `extras/docs/CREDITS.txt` becomes `docs/CREDITS.txt` in the ZIP. The build config and source `pack.mcmeta` are handled separately. Lowercase path validation applies to `assets/`; documentation filenames may contain capitals. JSON and `.mcmeta` files still need valid JSON. Place custom `pack.mcmeta` at the source root, rather than in `extras/`.

## Commands

The scripts can be run directly with PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListPacks
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -ListVersions
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack example_pack
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Version 26.2
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack example_pack -Version 26.2
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForPack
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForPack -Version all
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForPack -PromptForVersion
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack example_pack -Version '1.21.4..26.3'
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -PromptForVersion
powershell -ExecutionPolicy Bypass -File .\scripts\build-texture-packs.ps1 -Pack example_pack -Version 26.2 -Clean
```

Without pack or version arguments, the builder selects all packs (including Artemis Enhanced Visuals) and all enabled versions allowed by each pack. `-Clean` removes the shared temporary staging directory before continuing with the requested build; existing ZIPs in `build/` and `archive/` are retained until a matching build ZIP is replaced normally.

Both `-Version` and interactive version selection accept `all`, a single version, an inclusive range such as `<start>..<end>` or `<start> to <end>`, and comma-separated mixes. Ranges follow the configured version matrix order; each pack's version filters still apply. Quote command-line ranges and mixes containing spaces.

`Build Selected Texture Packs` uses this same version selection after you enter the pack names. For example, select `example_pack`, then enter `1.21.4..26.3` to build every configured version in that inclusive range, or `1.21.4, 1.21.11 to 26.3` to mix individual versions and ranges.
The builder also prompts for versions when run with just `-PromptForPack`, unless `-Version` is supplied or you are only listing packs with `-ListPacks`.

All build and publishing run configurations prompt for versions. Enter `all` for every enabled supported version, or choose individual versions and ranges. Selected-pack configurations also ask for pack names.

The scaffold script creates a new pack folder using the configured source layout:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-texture-pack.ps1 -Name example_pack -MinVersion 1.13
```

The sync script refreshes the generated Minecraft release matrix:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\sync-minecraft-release-matrix.ps1
```

## IntelliJ Run Configurations

Shared IntelliJ run configurations are stored in `.run/`:

| Build configuration | Pack selection | Version selection |
| --- | --- | --- |
| `Build All Texture Packs` | All packs | Prompts for versions, ranges, or `all` |
| `Build Selected Texture Packs` | Prompts for pack names | Prompts for versions, ranges, or `all` |

Other shared configurations:

- `Build Artemis Enhanced Visuals`
- `Create New Texture Pack`
- `Dry Run Modrinth Publish All`
- `Dry Run Modrinth Publish Selected`
- `Publish All Resource Packs to Modrinth`
- `Publish Selected Resource Packs to Modrinth`
- `Dry Run CurseForge Publish All`
- `Dry Run CurseForge Publish Selected`
- `Publish All Resource Packs to CurseForge`
- `Publish Selected Resource Packs to CurseForge`

These configurations run the repository's PowerShell scripts. Build prompts follow the table above; publishing configurations prompt for their configured pack, version, project, changelog, release version, and token inputs.

The all-pack and selected-pack build/publish configurations also include Artemis
Enhanced Visuals. Its dedicated build configuration prompts for Minecraft versions
and uses the combined builder directly.

## Modrinth Publishing

`scripts/publish-modrinth.ps1` prepares Modrinth upload items from release ZIPs. It looks first in `archive/<pack>/<releaseVersion>/`, then falls back to `build/<pack>/`. If `-Build` is provided and neither location has the ZIP, it builds that pack/version before publishing. It performs a dry run unless `-Publish` is provided.

Useful publishing parameters:

- `-Pack`: select one or more individual or combined packs
- `-Version`: select one or more Minecraft versions or ranges
- `-PromptForPack`: prompt for pack selection
- `-PromptForVersion`: prompt for version selection
- `-PromptForProject`: prompt for Modrinth project references
- `-Build`: build a pack/version only when no matching archive or build ZIP exists
- `-SkipBuild`: use existing archive/build ZIPs only
- `-Publish`: create Modrinth versions
- `-CheckRemote`: check existing remote Modrinth versions during dry runs
- `-PromptForToken`: prompt for a token
- `-PromptForChangelog`: prompt for a changelog
- `-Changelog`: provide the changelog directly, including an empty string to clear it
- `-ReleaseVersion`: override the release version used in Modrinth version numbers
- `-PromptForReleaseVersion`: prompt for that release version

Project references can be Modrinth resource-pack URLs, project IDs, or slugs. By default, the pack folder name is used as the Modrinth slug unless a project is configured or saved locally.

Per-pack Modrinth settings live in the pack's `pack.build.psd1`:

```powershell
@{
    Modrinth = @{
        ProjectUrl = 'https://modrinth.com/resourcepack/<slug>'
        ReleaseVersion = '1.0.0'
        VersionNumberTemplate = '{ReleaseVersion}-mc{MinecraftVersion}'
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

- a matching archive or build ZIP must exist, or be built when `-Build` is enabled
- the ZIP must contain root `pack.mcmeta`
- the generated Modrinth version number must use supported characters
- `VersionType` and `Status` must be valid Modrinth values

Publishing requires a Modrinth personal access token with the `VERSION_CREATE` scope. The token can come from `-PromptForToken`, the `MODRINTH_TOKEN` environment variable, or the ignored local state file at `config/modrinth.local.psd1`.

When publishing, the script reads existing Modrinth versions and skips version numbers that already exist. Uploaded ZIPs are copied with their Modrinth upload filename. ZIPs from `build/<pack>/` are moved into the archive after upload; ZIPs already found in `archive/` are reused in place:

```text
archive/<pack>/<releaseVersion>/<display name> <releaseVersion> MC<minecraftVersion>.zip
```

If the archive path already contains identical contents, the duplicate build copy is removed. If the path exists with different contents, the uploaded copy is kept with a timestamp suffix.

New upload filenames use the pack's display name, release version, and uppercase `MC`, for example `Example Pack 1.0.0 MC26.2.zip`. Existing archive filenames are preserved when reused on either platform. Default version numbers still use `mc1.21.11`, with no dot after `mc`. Both publishers recognize older archive naming styles; duplicate detection treats `mc1.21.11` and `mc.1.21.11` as the same release, preserving existing Modrinth releases and saved CurseForge publish records.

## CurseForge Publishing

`scripts/publish-curseforge.ps1` prepares CurseForge upload items from release ZIPs. It looks first in `archive/<pack>/<releaseVersion>/`, then falls back to `build/<pack>/`. If `-Build` is provided and neither location has the ZIP, it builds that pack/version before publishing. It performs a dry run unless `-Publish` is provided.

Useful publishing parameters match the Modrinth publisher where CurseForge supports the same workflow:

- `-Pack`: select one or more individual or combined packs
- `-Version`: select one or more Minecraft versions or ranges
- `-PromptForPack`: prompt for pack selection
- `-PromptForVersion`: prompt for version selection
- `-PromptForProject`: prompt for CurseForge project IDs
- `-Build`: build a pack/version only when no matching archive or build ZIP exists
- `-SkipBuild`: use existing archive/build ZIPs only
- `-Publish`: upload CurseForge files
- `-CheckRemote`: check local publish state for duplicates; CurseForge does not document a remote file-listing endpoint for this upload API
- `-PromptForToken`: prompt for a token
- `-PromptForChangelog`: prompt for a changelog
- `-Changelog`: provide the changelog directly, including an empty string to clear it
- `-ReleaseVersion`: override the release version used in file names
- `-PromptForReleaseVersion`: prompt for that release version

Project references must be numeric CurseForge project IDs, or author dashboard URLs containing that ID, such as `https://authors.curseforge.com/dashboard/projects/123456`. Public project slugs are not enough for upload API calls.

Per-pack CurseForge settings live in the pack's `pack.build.psd1`:

```powershell
@{
    CurseForge = @{
        ProjectId = '123456'
        ReleaseVersion = '1.0.0'
        VersionNumberTemplate = '{ReleaseVersion}-mc{MinecraftVersion}'
        NameTemplate = '{PackDisplayName} {ReleaseVersion} for Minecraft {MinecraftVersion}'
        Changelog = ''
        ChangelogType = 'text'
        ReleaseType = 'release'
        ManualRelease = $false
        GameVersionNames = @('{MinecraftVersion}')
    }
}
```

`ProjectUrl`, `Url`, or `Project` can be used instead of `ProjectId` as long as the value resolves to a numeric CurseForge project ID. Set `Enabled = $false` inside the `CurseForge` block to exclude a pack from publishing.

Publishing requires a CurseForge API token. The token can come from `-PromptForToken`, the `CURSEFORGE_TOKEN` environment variable, or the ignored local state file at `config/curseforge.local.psd1`.

When publishing, uploaded ZIPs are copied with their CurseForge upload filename. ZIPs from `build/<pack>/` are moved into the archive after upload; ZIPs already found in `archive/` are reused in place:

```text
archive/<pack>/<releaseVersion>/<display name> <releaseVersion> MC<minecraftVersion>.zip
```

## Licensing

The repository is licensed under the MIT License; see `LICENSE`. Individual packs may include third-party work with separate credits and license notices in their source folders. Preserve those notices when editing or publishing a pack. The builders include applicable notices in individual ZIPs and collect them for the combined pack.

Artemis Enhanced Visuals collects the included packs' attribution into its generated
`credits.txt`, preserves their original license notices under `licenses/<pack>.txt`,
and includes the current repository `LICENSE` as its root `license.txt`.
