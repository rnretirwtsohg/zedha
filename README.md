# Zedha

Zedha is a personal-first, public-compatible downstream distribution of
[Zed](https://github.com/zed-industries/zed).

It follows a VSCodium-style model: this repository does not vendor Zed source.
It pins an upstream Zed stable release, fetches that source, applies a small
ordered patch set, and packages the result.

## Status

| | |
|---|---|
| Upstream pin | Zed **v1.12.0** (`f96212f2c50f54d93712fa130d6226b1ce7d76b5`) |
| Published builds | **Unsigned and not notarized** Apple Silicon DMGs |
| Auto-updates | Not available yet |
| Intel Macs | No published DMG yet |

Native code signing, notarization, and a Zedha-owned update feed are deferred
until Apple Developer credentials are in place.

## Install (macOS, Apple Silicon)

1. Download `Zedha-aarch64.dmg` from the
   [latest GitHub Release](https://github.com/rnretirwtsohg/zedha/releases/latest).
2. Open the DMG and drag **Zedha** into **Applications**.
3. First launch will be blocked by Gatekeeper because the build is unsigned.
   Either:
   - Right-click **Zedha.app** → **Open** → **Open**, or
   - Clear the quarantine flag:

     ```bash
     xattr -dr com.apple.quarantine /Applications/Zedha.app
     ```

4. Optional CLI: in Zedha, use the built-in **Install CLI** action. That creates
   `/usr/local/bin/zedha`. You can also invoke the packaged binary directly:

   ```bash
   /Applications/Zedha.app/Contents/MacOS/cli
   ```

## Verify the download

Each release publishes a SHA-256 for the DMG. After downloading:

```bash
shasum -a 256 ~/Downloads/Zedha-aarch64.dmg
```

Compare the output to the checksum in the release notes. They must match
exactly.

## What you get

```text
App name:     Zedha
CLI command:  zedha
Bundle ID:    me.ghostwriternr.Zedha
URL scheme:   zedha://
```

Zedha also carries a terminal-launcher patch from the personal Zed fork:
launcher sessions can create, reuse, and close terminal tabs by session id.

Official Zed remains a separate product and install.

## Differences from Zed

- Product identity is Zedha (name, CLI, bundle ID, URL scheme).
- Includes the terminal launcher behavior described above.
- Does **not** use Zed’s official update feed.
- Public DMGs are unsigned until signing infrastructure exists.

## Attribution

Zed is developed by [Zed Industries](https://zed.dev).
Zedha is an independent downstream distribution and is **not affiliated with,
endorsed by, or supported by Zed Industries**.

- Upstream source and license: https://github.com/zed-industries/zed
- This repository owns the upstream pin, downstream patches, and packaging.

## Build from source

Requirements: macOS, a working Rust toolchain, and the usual Zed native
dependencies.

```bash
# Script / identity regression tests (no full Zed compile)
./tests/test-scripts.sh

# Fetch the pinned upstream into .work/zed
./scripts/fetch-upstream

# Apply patches/ in order
./scripts/apply-patches

# Confirm product identity on the patched tree
./scripts/check-identity

# Targeted validation (includes terminal launcher tests when configured)
./scripts/test

# Produce a local Apple Silicon DMG under artifacts/
./scripts/build-macos-artifact .work/zed aarch64-apple-darwin
```

To point `fetch-upstream` at an existing local Zed checkout:

```bash
ZEDHA_UPSTREAM_REPO=~/github/zed ./scripts/fetch-upstream
```

### Repository layout

```text
upstream/stable.json              pinned upstream Zed stable release
patches/*.patch                   ordered downstream patches
scripts/fetch-upstream            clone pinned upstream source
scripts/apply-patches             apply patches to a Zed checkout
scripts/check-identity            verify patched Zedha product identity
scripts/update-upstream-pin       detect newer strict stable upstream tags
scripts/build-macos-artifact      build a macOS DMG into artifacts/
scripts/test                      run targeted validation
tests/test-scripts.sh             script behavior tests
.github/workflows/upgrade-upstream.yml  opens upgrade PRs for new stables
```

Current patches:

```text
0001-terminal-launcher.patch   terminal launcher behavior
0002-brand-as-zedha.patch      product and distribution identity
```

A scheduled workflow checks for newer upstream `vMAJOR.MINOR.PATCH` tags,
validates that the existing patches still apply, and opens a manual-review
pull request. Nothing is auto-merged.

## Troubleshooting

| Symptom | What to do |
|--------|------------|
| “Zedha is damaged and can’t be opened” / blocked on first launch | Expected for unsigned builds. Right-click → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Zedha.app`. |
| `zedha: command not found` | Open Zedha and use **Install CLI**, or call `/Applications/Zedha.app/Contents/MacOS/cli` directly. |
| No update notifications | Expected. Auto-updates need signed builds and a Zedha update feed. |
| Need an Intel Mac build | Not published yet. Build locally with the appropriate target, or wait. |
| Bug that also happens in upstream Zed | Report it to [zed-industries/zed](https://github.com/zed-industries/zed). Zedha-only issues belong in this repo. |

## License

Upstream Zed’s license terms apply to the Zed source. Downstream patches and
packaging in this repository are provided as-is for a personal-first,
public-compatible distribution.
