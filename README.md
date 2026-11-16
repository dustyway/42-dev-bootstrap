# 42-dev-bootstrap

Scripts that install JetBrains IDEs, Emacs, language runtimes and other tools
on the 42 school cluster machines. They run on every login, do nothing if
everything is in place, and reinstall whatever a storage wipe removed.

## Why

The cluster has three storage locations with different rules:

| Location | Size | Persistent | Speed | Notes |
|---|---|---|---|---|
| `$HOME` (iSCSI) | 5 GB (10 GB upgrade) | yes, on every machine | fast | Hard quota. Going over blocks file creation and breaks apps. |
| `/goinfre` | ~unlimited | no, wiped when another user logs in after you | fastest | Local disk, per machine. |
| `/sgoinfre` (NFS) | 30 GB | yes, on every machine | slow | Wiped Sunday night if over 30 GB, or after 6 months of inactivity. |

Anything over ~500 MB can't go in `$HOME` (quota) or `/goinfre` (volatile), so
it goes on `/sgoinfre`, which can still be wiped. Each script puts its files
in the right place and reinstalls them when they disappear.

Most scripts follow the same layout: the install goes to
`/sgoinfre/<tool>/<version>/`, the downloaded archive is cached in
`/sgoinfre/.cache/`, and launchers are symlinks in `~/bin`. Where upstream
publishes checksums, downloads are verified against them.

## Scripts

### `jb-bootstrap <PRODUCT_CODE>[@VERSION] [owner/repo[@tag] …]`

Installs a JetBrains IDE.

- Binary, cached tarball and config go to `/sgoinfre`; indexes and logs go to
  `/goinfre`.
- Adds a `~/bin/<slug>` launcher and a `.desktop` entry with the IDE's icon.
- Installs plugins from GitHub releases, since the marketplace often lags.
- `<CODE>@VERSION` pins an IDE release; `owner/repo@tag` pins a plugin.
- Backs up selected IDE settings to `$HOME/Apps/etc/jetbrains-backup/` on every
  login and restores them after a `/sgoinfre` wipe.

Product codes: `IIU IIC WS PS PCP PCC CL GO RM RD DG AC RR` (IntelliJ IDEA
Ultimate/Community, WebStorm, PhpStorm, PyCharm Pro/Community, CLion, GoLand,
RubyMine, Rider, DataGrip, Aqua, RustRover).

### `mise-bootstrap`

Reinstalls the runtimes pinned in `~/.config/mise/config.toml` and sets up
extras for the tools it finds there:

| Tool in config | Extra setup |
|---|---|
| `erlang` | Builds wxWidgets 3.2 on `/sgoinfre` (`wx-bootstrap`) and compiles Erlang from source against it with the `asdf-erlang` plugin. mise's default prebuilt Erlang links against wx 3.0, which the cluster doesn't have, so `:observer.start()` would fail. |
| `erlang` or `elixir` | Adds the wx library path to `LD_LIBRARY_PATH` in `~/.profile`, and a logger filter to `~/.iex.exs` that hides harmless GTK3 style-context warnings. |
| `elixir` | Installs the `hex`, `rebar` and `phx_new` archives and the `livebook` escript for the active Elixir version. Without this, a version bump makes the next `mix deps.get` prompt, and `livebook` drops off `PATH`. |
| `node` | Reinstalls global npm packages listed in `~/Apps/etc/npm-globals.txt`. |
| `rust` | Sets `MISE_RUSTUP_HOME` and `MISE_CARGO_HOME` under `/sgoinfre`. The cluster's `/etc/zsh/zshenv` points `RUSTUP_HOME` and `CARGO_HOME` at root-owned `/opt/rust`, which isn't on `PATH`, so apt's `rustc` 1.75 would win. `mise activate` exports the user-owned paths, so `cargo install` and `rustup component add` work. |

The `~/.profile` and `~/.iex.exs` edits are marked with comments and only
added once.

### `emacs-bootstrap [VERSION]`

Installs Emacs with tree-sitter and native compilation (GTK3/X11). The
tarball is built by `.github/workflows/build-emacs.yml` and published as a
release on this repo. To build a new version, push an `emacs-<VERSION>` tag.

### `postgres-bootstrap`

Installs a PostgreSQL server from theseus-rs's prebuilt binaries. apt needs
sudo and a source build needs bison and flex. All pg tools (`psql`,
`pg_ctl`, `initdb`, …) are linked into `~/bin`. Data directories are not
managed: run `initdb -D /sgoinfre/.../<app>-pgdata` per project.

### `docker-bootstrap`

Moves rootless Docker's data-root to `/goinfre/$USER/docker`. It doesn't
install Docker; it uses the cluster's `docker` CLI and systemd `--user` unit.

By default the data-root is `~/.local/share/docker`, which fills the `$HOME`
quota (one dev stack was 3.3 GB). On `/goinfre` it is wiped when another user
logs in, which is acceptable because images and volumes can be rebuilt or
pulled again.

`daemon.json` is a regular file in `~/.config/docker` (an older version used a
symlink to `/goinfre`, which gets replaced). It has to exist at boot, or the
daemon starts with the default root and fills the quota before the bootstrap
runs. The script restarts the daemon only when the config or the live root
is wrong. It never deletes the old `~/.local/share/docker`; it prints the
`rm -rf` command so you can do that yourself.

### `docker-build`

Wrapper for `docker buildx build` that keeps the BuildKit layer cache at
`$SGO/docker-buildcache`, so a `/goinfre` wipe doesn't force a full rebuild.
The data-root can't live on NFS (overlayfs), but the `type=local` cache is
plain files and can.

`type=local` needs the `docker-container` builder driver. That builder is a
container in the data-root, so the wrapper recreates it when it's gone. Use
it like `docker buildx build`:

```sh
docker-build --push -t ghcr.io/<owner>/myapp:latest .
```

With this driver the result isn't loaded into `docker images` automatically;
pass `--load` or `--push`. Images pulled from a registry
(`docker compose pull`) don't need this.

### `inotify-tools-bootstrap`

Installs `inotifywait` and `inotifywatch`, which Phoenix's `file_system`
dependency uses for live reload. There is no mise plugin or upstream binary,
so `build-inotify-tools.yml` builds a static tarball.

### `clangd-bootstrap`

Installs `clangd` from the `clangd/clangd` releases. `~/bin/clangd` shadows
apt's clangd 14, which rejects newer `.clang-format` keys such as
`InsertNewlineAtEOF`. Only `clangd` is included, but it has clang-format
built in, so formatting through the editor (e.g. `eglot-format-buffer`)
works.

### `gh-bootstrap`

Installs the GitHub CLI from the `cli/cli` releases. apt's `gh` lags behind
and needs sudo. Auth tokens live in `~/.config/gh/` and survive `/sgoinfre`
wipes.

### `fzf-bootstrap [VERSION]`

Installs the [fzf](https://github.com/junegunn/fzf) fuzzy finder from the
upstream releases and links `~/bin/fzf`.

### `actionlint-bootstrap [VERSION]`

Installs [actionlint](https://github.com/rhysd/actionlint), a linter for
GitHub Actions workflows, from the upstream releases. It isn't in apt.

### `act-bootstrap [VERSION]`

Installs [act](https://github.com/nektos/act), which runs GitHub Actions
workflows locally, from the upstream releases. Jobs run in containers on
the cluster's rootless Docker (see `docker-bootstrap`).

### `cuda-bootstrap [CUDA_PKG_SUFFIX]`

Installs CUDA 12, cuDNN 9 and NCCL 2 libraries without sudo, for GPU
EXLA (Nx/Axon). Downloads the packages from NVIDIA's Ubuntu 22.04 repository
and extracts them to `$SGO/cuda/`. The cached packages take about 2.5 GB.

The default is CUDA 12.9 (`12-9`), which matches XLA's `nvrtc-builtins`
library; pass e.g. `12-8` for another minor version. `libxla_extension.so`
requires three NVSHMEM libraries that single-GPU work never calls, so the
script builds empty stubs with the right names. It adds `LD_LIBRARY_PATH`,
`PATH` and `XLA_FLAGS` to `~/.profile` once. Afterwards, recompile EXLA in
your project:

```sh
XLA_TARGET=cuda12 mix deps.compile exla --force
```

### `glow-bootstrap [VERSION]`

Installs [glow](https://github.com/charmbracelet/glow), a terminal Markdown
viewer, from the upstream releases. It isn't in Ubuntu 22.04's apt.

### `ocaml-bootstrap [VERSION]`

Installs OCaml 5 with `ocamlfind`, `utop`, `ocaml-lsp-server` and `dune` from
a tarball built by `build-ocaml.yml`. apt's OCaml is 4.13, and building with
opam on NFS after each wipe would be slow.

An OCaml install records its own absolute path, so the workflow builds it at
the real `$SGO/ocaml/<version>` path. It only works for the login set in
`OCAML_ROOT`. There is no opam on the cluster: adding a package means editing
the workflow and rebuilding. `~/bin/ocaml` and `~/bin/utop` are wrappers that
set the variables `opam env` would.

### `ghidra-bootstrap [VERSION]`

Installs [Ghidra](https://github.com/NationalSecurityAgency/ghidra). Ghidra 12
needs JDK 21 and the cluster has 17, so the script also installs a private
Temurin 21 JDK under `/sgoinfre/ghidra/` and sets `JAVA_HOME_OVERRIDE` in
Ghidra's `launch.properties`.

Adds `~/bin/ghidra` (GUI), `~/bin/ghidra-headless` (`analyzeHeadless`) and a
`.desktop` entry. Settings live in `~/.config/ghidra/`. Keep large projects on
`/sgoinfre`, not `$HOME`. Uses about 1.2 GB installed plus 750 MB of cached
downloads.

### `graphviz-bootstrap`

Installs graphviz (`dot`, `neato`, `fdp`, …) without sudo by extracting the
Ubuntu packages with `apt-get download` and `dpkg-deb -x`. A source build
would need cairo, pango, libpng and freetype.

The script also generates `config6`, the plugin registry that `dot -c`
normally writes after install. The `~/bin` wrappers set `LD_LIBRARY_PATH` and
`GVBINDIR`. Plugins load the system's cairo and pango, so PNG, SVG and PDF
output work.

### `ollama-bootstrap`

Runs a second ollama daemon under your account, next to the cluster's
system daemon. It uses the system `/bin/ollama`, listens on port 11435
(`OLLAMA_HOST` is set in `profile.snippet`), and stores models in
`/sgoinfre/ollama/models`. Adds a `~/bin/ollama-serve` launcher and pulls any
model listed in `~/Apps/etc/ollama-models.txt` that is missing. The default
model is `qwen2.5-coder:7b`.

### `aider-bootstrap`

Installs aider with `uv tool`. The Python environment (200–500 MB) goes in
`/sgoinfre/uv-tools/` via `UV_TOOL_DIR`; only the `~/.local/bin/aider` shim is
in `$HOME`. Reinstalls when the environment is gone.

With `ollama-bootstrap` it can run fully locally:

```sh
aider --model ollama_chat/qwen2.5-coder:7b --edit-format whole
```

`profile.snippet` sets `OLLAMA_API_BASE` so aider finds your daemon.

### `opencode-bootstrap`

Installs OpenCode v2 through mise (`mise use -g npm:@opencode/cli`), with the
binaries under `/sgoinfre/mise-data/`. It is listed separately in
`42-dev-install`, but `mise-bootstrap` restores it after a wipe. Removes a
leftover v1 `github:anomalyco/opencode` entry. If Tailscale is installed, it
routes OpenCode's background service through the Tailscale HTTP proxy.

### `tailscale-bootstrap`

Installs the [Tailscale](https://tailscale.com) client without root, in
userspace-networking mode (no TUN device or routing changes). Tailnet traffic
goes through a SOCKS5 proxy on `127.0.0.1:1055`
(`ALL_PROXY=socks5://127.0.0.1:1055`) or an HTTP proxy on `127.0.0.1:1056`
(`HTTP_PROXY=http://127.0.0.1:1056`) for clients without SOCKS support. The
`~/bin/tailscale` wrapper passes the socket path, so `tailscale up` and
`tailscale status` work unchanged. Auth state lives in `~/.config/tailscale/`.

With a self-hosted control server (Headscale), the first `tailscale up` on a
machine needs `--login-server=https://headscale.example.com`; otherwise it
registers with Tailscale's own servers. The URL is stored in the auth state
after that.

To point OpenCode at the proxy by hand:

```sh
opencode service set env HTTP_PROXY http://127.0.0.1:1056
opencode service set env HTTPS_PROXY http://127.0.0.1:1056
opencode service set env NO_PROXY localhost,127.0.0.1,::1
```

Then run `opencode service restart` and restart any open OpenCode TUI.

### `tor-browser-bootstrap [VERSION]`

Installs [Tor Browser](https://www.torproject.org/) from the official
tarball. Defaults to the latest stable release from Tor's update feed and
downloads from `archive.torproject.org`, verified against
`sha256sums-signed-build.txt`. Adds `~/bin/tor-browser` and a `.desktop`
entry.

The built-in updater is disabled in `distribution/policies.json`; rerunning
the bootstrap updates instead, and removes old versions. The profile lives in
the install directory, so it resets on each version change. While open, Tor
Browser serves a SOCKS5 proxy on `127.0.0.1:9150` that other tools can use:

```sh
curl --socks5-hostname 127.0.0.1:9150 http://xxx.onion
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:9150 %h %p" -p 4242 user@xxx.onion
```

### `torsocks-bootstrap [VERSION]`

Installs [torsocks](https://gitlab.torproject.org/tpo/core/torsocks) the same
way as graphviz. torsocks preloads `libtorsocks.so` so a program's
connections and DNS lookups go through Tor's SOCKS port. It doesn't include
Tor itself: it is configured for port 9150, so Tor Browser must be open.
`~/bin/torsocks` sets `TORSOCKS_CONF_FILE`; use `TORSOCKS_TOR_PORT=9050` for
another port.

```sh
torsocks ssh -p 4242 user@xxx.onion
torsocks curl http://xxx.onion
```

### `repo-bootstrap <git-url> [dest-dir]`

Clones a repository onto `/goinfre` on login if it's missing (default
`/goinfre/$USER/<repo-name>`). An existing checkout is left alone and never
pulled, since it may have uncommitted work. SSH clones use `BatchMode`, so a
missing key fails instead of waiting for a passphrase. One `~/.zprofile` line
per repository:

```sh
(nohup ~/Apps/bin/repo-bootstrap git@github.com:you/yourrepo.git &>/dev/null &)
```

### `jb-sync-elixir-sdk`

Updates every JetBrains product's `jdk.table.xml` so the `Elixir SDK` and
`Erlang SDK for Elixir SDK` entries point at the current mise install paths.
Runs at the end of `mise-bootstrap` and `jb-bootstrap`. Without it, an Elixir
upgrade leaves the IDE pointing at a path that may no longer exist.

## Install

```sh
git clone https://github.com/<you>/42-dev-bootstrap.git ~/Code/42-dev-bootstrap
cd ~/Code/42-dev-bootstrap
./install.sh
```

Append the shell snippets:

```sh
cat shell/profile.snippet >> ~/.profile
cat shell/zshrc.snippet >> ~/.zshrc
```

Add the bootstraps you want to `~/.zprofile`. They run in the background so
login isn't blocked:

```sh
nohup $HOME/Apps/bin/jb-bootstrap IIU KronicDeth/intellij-elixir &>/dev/null & disown
nohup $HOME/Apps/bin/mise-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/emacs-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/tailscale-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/tor-browser-bootstrap &>/dev/null & disown
nohup $HOME/Apps/bin/docker-bootstrap &>/dev/null & disown
```

## mise runtimes

Pin runtimes in `~/.config/mise/config.toml` (or with `mise use --global`).
`mise-bootstrap` reads it on login and installs whatever is missing.

```toml
[tools]
node = "24"       # npm globals from ~/Apps/etc/npm-globals.txt
go = "1.26.3"
rust = { version = "1.99.1", components = "rust-src,rust-analyzer" } # needs MISE_RUSTUP_HOME/MISE_CARGO_HOME from shell/*.snippet
elixir = "1.20.1-otp-29" # hex / rebar / phx_new archives, livebook, IEx GTK filter
erlang = "29.0.2"        # wx 3.2 build, Erlang compiled from source, LD_LIBRARY_PATH
```

A current GCC comes from conda-forge through mise's `conda:` backend. The
cluster's newest is g++-12, whose standard library lacks most of C++23.
Programs it builds find the newer `libstdc++` through an rpath, without
`LD_LIBRARY_PATH`:

```toml
"conda:gxx" = "16.2.0"   # g++ / c++
```

Extras are only set up for tools in the config. Global npm packages go in
`~/Apps/etc/npm-globals.txt`, one per line.

## What survives a wipe

"Reinstalled" means: re-extracted from the cached archive if it's still
there, otherwise downloaded again.

| Lost | Recovered? | How |
|---|---|---|
| IDE binary on /sgoinfre | yes | Reinstalled |
| Cached archives | yes | Downloaded again on next install |
| IDE plugins | yes | Fetched again from GitHub releases |
| IDE settings (options/, keymaps/, codestyles/, …) | yes | Restored from the backup in $HOME |
| Project-specific IDE state (workspace/, history, recents) | no | Not backed up; rebuilt when you reopen the project |
| mise runtimes, OpenCode | yes | `mise install` from config.toml |
| Global npm packages | yes | Reinstalled from npm-globals.txt |
| Go tools (`~/go/bin/*`) | not affected | Live in $HOME |
| Emacs, PostgreSQL, inotify-tools, clangd, gh, glow, fzf, act, actionlint, OCaml, Ghidra + JDK, Tailscale, Tor Browser | yes | Reinstalled |
| graphviz, torsocks | yes | Reinstalled from cached .debs or `apt-get download` |
| CUDA libraries | yes | Re-extracted from cached .debs, else downloaded from NVIDIA's repository |
| ollama models | yes | Missing models from ollama-models.txt pulled again |
| gh and Tailscale auth | not affected | Live in $HOME |
| Docker config after a /goinfre wipe | yes | `daemon.json` is in $HOME; data-root recreated and daemon restarted |
| Docker images, volumes, containers | no | On /goinfre; rebuild or pull again |
| Working clones on /goinfre | yes | `repo-bootstrap` clones them again |
| Uncommitted work in those clones | no | Commit and push before logging out |

## Possible additions

Would fit the same pattern:

- `restic` + `rclone`: encrypted incremental backups of `$HOME` and selected
  `/sgoinfre` state to B2, Drive or SFTP. Would cover losing everything, not
  just a `/sgoinfre` wipe.
- `texlive-bootstrap`: `install-tl` is scriptable; about 6 GB, too big for
  `$HOME`.
- Language servers: `lua-language-server`, `taplo`, `tinymist`, `pyright`.
  Each would be close to a copy of `clangd-bootstrap`.
- CLI tools: `ripgrep`, `fd`, `bat`, `jq`, `just`, `direnv`, `zoxide`,
  `delta`, perhaps as one script.
- `uv-bootstrap`: Astral's Python toolchain, alongside mise.

## License

[Unlicense](./LICENSE): public domain, no warranty.
