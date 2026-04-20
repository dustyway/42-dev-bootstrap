# 42-jetbrains-bootstrap

Idempotent scripts to install JetBrains IDEs, language runtimes, and related
plugins on **42 school cluster machines** — where storage is split across
three tiers with different persistence, size, and wipe rules. Designed to
run on every login, do nothing when everything is already in place, and
quietly heal the setup when sgoinfre gets wiped.

## Why

The 42 cluster storage layout:

| Location | Size | Persistent | Speed | Notes |
|---|---|---|---|---|
| `$HOME` (iSCSI) | 5 GB (10 GB upgrade) | yes, everywhere | fast | **Hard quota** — over-limit blocks file creation and breaks apps. |
| `/goinfre` | \~unlimited | no — wiped when another user logs in after you | fastest | Local disk. Per-machine. |
| `/sgoinfre` (NFS) | 30 GB | yes, everywhere | slow | Sunday-night wipe if > 30 GB; 6-month-inactivity wipe. |

Anything \~500 MB+ can't live in `$HOME` (quota) or `/goinfre` (volatile), so
it has to live on `/sgoinfre` — which is the one that can vanish on Sunday
night. These scripts encode the right placement per kind of file and
re-bootstrap whatever was lost.

## What you get

**`jb-bootstrap <PRODUCT_CODE>[@VERSION] [owner/repo[@tag] …]`**
Installs a JetBrains IDE with caching and self-healing:
- Binary + cached tarball → `/sgoinfre`, config → `/sgoinfre`, indexes/logs → `/goinfre`
- `~/bin/<slug>` symlink launcher, under quota
- Optional plugin installs from GitHub releases (marketplace often lags)
- `<CODE>@VERSION` pins a specific IDE release; `owner/repo@tag` pins a plugin
- Curated IDE-settings backup to `$HOME/Apps/etc/jetbrains-backup/` on every
  login, restored if `/sgoinfre` was wiped

Supported product codes: `IIU IIC WS PS PCP PCC CL GO RM RD DG AC RR`
(IntelliJ IDEA Ultimate/Community, WebStorm, PhpStorm, PyCharm Pro/Community,
CLion, GoLand, RubyMine, Rider, DataGrip, Aqua, RustRover).

**`mise-bootstrap`**
Restores mise-managed runtimes (Node / Go / Elixir / Erlang / …) and global
npm packages after a `/sgoinfre` wipe. Pulls pins from `~/.config/mise/config.toml`
and globals from `~/Apps/etc/npm-globals.txt`. Idempotent.

**`emacs-bootstrap`**
Installs a modern Emacs (tree-sitter + native-comp + pgtk) from a tarball
built by this repo's own GitHub Actions workflow and published as a Release
asset. Downloads once, caches the tarball on `/sgoinfre/.cache/`, extracts
to `/sgoinfre/emacs/<version>/`, symlinks `~/bin/emacs` + `~/bin/emacsclient`.
No sudo, no system packages — the build toolchain runs on GitHub's Ubuntu
runner; your cluster machine only downloads and extracts. Rebuild by pushing
a new `emacs-<VERSION>` tag; `emacs-bootstrap VERSION` picks it up on next
login.

**`jb-patch-elixir-debugger`**
Patches `intellij-elixir`'s debugger so `:int.interpreted/0` doesn't fail on
modern Elixir (1.15+) where `mix` runs with a reduced code path that drops
Erlang's `debugger-*/ebin`. Runs automatically after the Elixir plugin
installs via `jb-bootstrap`.

**`jb-sync-elixir-sdk`**
Rewrites every JetBrains product's `jdk.table.xml` so the `Elixir SDK` and
`Erlang SDK for Elixir SDK` entries point at the current mise-managed
install paths. Runs at the end of `mise-bootstrap` (catches version bumps)
and `jb-bootstrap` (catches SDK-containing XML restored from backup).
Without this, a `mise use --global elixir@…` upgrade leaves the IDE
pointing at a path that may not exist after a /sgoinfre wipe.

## Install

```sh
git clone https://github.com/<you>/42-jetbrains-bootstrap.git ~/Code/42-jetbrains-bootstrap
cd ~/Code/42-jetbrains-bootstrap
./install.sh
```

Then paste the snippets into your rc files:

```sh
# append to ~/.profile
cat shell/profile.snippet >> ~/.profile

# append to ~/.zshrc
cat shell/zshrc.snippet >> ~/.zshrc
```

Finally, add a login-time hook in `~/.zprofile`. Example:

```sh
nohup $HOME/Apps/bin/jb-bootstrap IIU@2025.3.4 KronicDeth/intellij-elixir@v22.0.1 &>/dev/null & disown
nohup $HOME/Apps/bin/mise-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/emacs-bootstrap &>/dev/null & disown
```

Backgrounded so they don't block the login.

## Pin versions? When and why

- **IDE pin (`@VERSION`)** — use when a plugin you rely on breaks on newer
  IDE builds (e.g. `intellij-elixir` v22 hits EDT threading violations on
  IntelliJ 2026.1). Without a pin, `jb-bootstrap` follows JetBrains'
  "latest" redirector.
- **Plugin pin (`@tag`)** — use when the latest release is a prerelease with
  regressions, or when you need a specific version for compatibility.

Example using both:
`jb-bootstrap IIU@2025.3.4 KronicDeth/intellij-elixir@v22.0.1`

## mise runtime pinning

Declare runtimes in `~/.config/mise/config.toml` (or via `mise use --global`).
`mise-bootstrap` reads this on login and reinstalls anything missing.

```toml
[tools]
node = "22"
go = "1.26.2"
elixir = "1.18.2"
erlang = "27.2"
```

Global npm packages live in `~/Apps/etc/npm-globals.txt`, one per line. The
bootstrap only reinstalls packages that are actually missing.

## Self-healing matrix

| Wiped / lost | Heals? | How |
|---|---|---|
| IDE binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download |
| Cached tarball | ✅ | Re-download on next install |
| IDE plugins | ✅ | Re-fetch from GitHub releases via marker files |
| IDE settings (options/, keymaps/, codestyles/, …) | ✅ | Curated backup/restore via $HOME |
| mise runtimes | ✅ | `mise install` reads config.toml |
| Emacs binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download from GitHub Release |
| Global npm packages | ✅ | Re-install from npm-globals.txt |
| Go tools (`~/go/bin/*`) | ✅ (implicit) | Binaries live in $HOME; survive /sgoinfre wipes |
| Project-specific settings (workspace/, history, recents) | ❌ | Not backed up — rebuild when you reopen the project |

## Known issues

- **IntelliJ 2026.1 EDT threading violation** in `intellij-elixir` SDK
  creation. Workaround: pin IDE to `IIU@2025.3.4` and plugin to
  `KronicDeth/intellij-elixir@v22.0.1`.
- **Elixir plugin debugger** `:int.interpreted/0` crash on Elixir 1.15+ —
  auto-patched by `jb-patch-elixir-debugger`. Reapplied each time the plugin
  is (re)installed.

## License

[Unlicense](./LICENSE) — public domain, no attribution required, no warranty.
