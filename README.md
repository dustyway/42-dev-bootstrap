# 42-dev-bootstrap

Idempotent scripts to install JetBrains IDEs, Emacs, language runtimes, and
related tooling on **42 school cluster machines** — where storage is split
across three tiers with different persistence, size, and wipe rules. Designed
to run on every login, do nothing when everything is already in place, and
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
- `~/.local/share/applications/<slug>.desktop` so the IDE shows up in the
  GNOME/Unity/KDE launcher with its real icon
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
Installs a modern Emacs (tree-sitter + native-comp, GTK3/X11) from a tarball
built by this repo's own GitHub Actions workflow and published as a Release
asset. Downloads once, caches the tarball on `/sgoinfre/.cache/`, extracts
to `/sgoinfre/emacs/<version>/`, symlinks `~/bin/emacs` + `~/bin/emacsclient`.
No sudo, no system packages — the build toolchain runs on GitHub's Ubuntu
runner; your cluster machine only downloads and extracts. Rebuild by pushing
a new `emacs-<VERSION>` tag; `emacs-bootstrap VERSION` picks it up on next
login.

**`postgres-bootstrap`**
Installs/heals a PostgreSQL server via theseus-rs's prebuilt, sha256-verified
binaries. Avoids the apt-or-source bind (no sudo available; building from
source needs bison + flex, which aren't in mise). Extracts to
`/sgoinfre/postgres/<version>/` and symlinks every pg tool (`psql`, `pg_ctl`,
`initdb`, …) into `~/bin`. `PGDATA` is per-project and **not** managed here —
run `initdb -D /sgoinfre/.../<app>-pgdata` inside your app repo.

**`inotify-tools-bootstrap`**
Installs `inotifywait` / `inotifywatch` — the file watchers Phoenix's
`file_system` dep uses for dev live-reload. mise has no plugin, apt needs
root, upstream ships no prebuilt tarball; this repo's
`build-inotify-tools.yml` GitHub Actions workflow builds a static-linked
tarball, and the bootstrap downloads + extracts it.

**`clangd-bootstrap`**
Installs a modern `clangd` (LSP server for C/C++) from the upstream
`clangd/clangd` prebuilt releases. Shadows Ubuntu's apt clangd-14 via a
`~/bin/clangd` symlink so Emacs's eglot gets a current binary with
up-to-date `.clang-format` support (the apt build rejects clang-format 16+
keys like `InsertNewlineAtEOF`). Ships `clangd` only — no standalone
`clang-format` CLI, but clangd has libFormat built in, so
`eglot-format-buffer` / on-type formatting read `~/.clang-format` correctly.

**`gh-bootstrap`**
Installs the GitHub CLI (`gh`) from the upstream `cli/cli` prebuilt
releases. apt's `gh` is usually a release behind and needs sudo anyway;
upstream ships a glibc-only tarball that drops in cleanly. Auth tokens
(`gh auth login`) live in `~/.config/gh/` on `$HOME`, so they survive
`/sgoinfre` wipes — no re-auth on Sunday nights.

**`graphviz-bootstrap`**
Installs graphviz (`dot`, `neato`, `fdp`, …) without sudo via
`apt-get download` + `dpkg-deb -x`, since mise has no plugin and a
source build pulls in cairo/pango/libpng/freetype. Extracts the jammy
.debs into `/sgoinfre/graphviz/<version>/`, regenerates `config6` (the
plugin registry that `dot -c` writes post-install — not shipped in the
.deb), and drops wrapper scripts into `~/bin` that set
`LD_LIBRARY_PATH` and `GVBINDIR` to the non-standard prefix. Plugins
dlopen cairo/pango from the system at runtime, so PNG/SVG/PDF output
all work.

**`ollama-bootstrap`**
Installs ollama (single static linux-amd64 tarball from upstream
`ollama/ollama` releases) into `/sgoinfre/ollama/<version>/` and drops
a `~/bin/ollama` wrapper that pins `OLLAMA_MODELS=/sgoinfre/ollama/models`
so models live where they fit. Reads desired models from
`~/Apps/etc/ollama-models.txt` (default: `qwen2.5-coder:7b` — strongest
small open coding model that fits sgoinfre with headroom) and re-pulls
anything missing on next login, so a Sunday-night `/sgoinfre` wipe
self-heals. Daemon is not auto-started — run `ollama serve` in a
terminal when you want to use it.

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
git clone https://github.com/<you>/42-dev-bootstrap.git ~/Code/42-dev-bootstrap
cd ~/Code/42-dev-bootstrap
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
nohup $HOME/Apps/bin/jb-bootstrap IIU KronicDeth/intellij-elixir &>/dev/null & disown
nohup $HOME/Apps/bin/mise-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/emacs-bootstrap &>/dev/null & disown
```

Backgrounded so they don't block the login.

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
| PostgreSQL binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download (sha256 verified) |
| inotify-tools binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download from GitHub Release |
| clangd binary on /sgoinfre | ✅ | Re-extract from cached zip, else re-download from clangd/clangd Release |
| gh binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download (sha256 verified against upstream checksums) |
| gh auth tokens | ✅ (implicit) | Live in `~/.config/gh/` on $HOME; survive /sgoinfre wipes |
| graphviz binaries on /sgoinfre | ✅ | Re-extract from cached .debs, else re-download via `apt-get download` |
| ollama binary on /sgoinfre | ✅ | Re-extract from cached tarball, else re-download from ollama/ollama Release |
| ollama models on /sgoinfre | ✅ | Re-pull anything missing from `~/Apps/etc/ollama-models.txt` |
| Global npm packages | ✅ | Re-install from npm-globals.txt |
| Go tools (`~/go/bin/*`) | ✅ (implicit) | Binaries live in $HOME; survive /sgoinfre wipes |
| Project-specific settings (workspace/, history, recents) | ❌ | Not backed up — rebuild when you reopen the project |

## Possible future additions

Same shape as the existing scripts (single-binary tarball, persistent on
`/sgoinfre`, idempotent re-fetch):

- **`restic` + `rclone`** — encrypted, deduplicated, incremental backup of
  `$HOME` and curated `/sgoinfre` state to B2/Drive/SFTP. Closes whole-machine
  loss as a recovery scenario (the matrix above only heals `/sgoinfre` wipes).
- **`texlive-bootstrap`** — `install-tl` is scriptable, ~6 GB; the canonical
  "no apt, can't fit in $HOME" candidate.
- **LSP toolbelt** — `rust-analyzer`, `lua-language-server`, `taplo`, `tinymist`,
  `pyright`. Each mirrors `clangd-bootstrap` almost verbatim.
- **CLI toolbelt** — `ripgrep`, `fd`, `bat`, `fzf`, `jq`, `just`, `direnv`,
  `zoxide`, `delta`. One bundled `qol-bootstrap` for the lot.
- **`uv-bootstrap`** — Astral's Python toolchain; per-project envs in
  milliseconds, complements mise.

Won't fit the constraints (don't try):

- Anything needing a 24/7 listener reachable from outside the cluster (gitea,
  syncthing, jellyfin) — the cluster network and per-login session lifetime
  kill it.
- Rootless Podman/Docker — needs `/etc/subuid` + `/etc/subgid` entries, which
  need root.

## Known issues

- **Elixir plugin debugger** `:int.interpreted/0` crash on Elixir 1.15+ —
  auto-patched by `jb-patch-elixir-debugger`. Reapplied each time the plugin
  is (re)installed.

## License

[Unlicense](./LICENSE) — public domain, no attribution required, no warranty.
