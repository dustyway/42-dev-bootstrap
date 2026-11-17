# 42-dev-bootstrap

Scripts that install JetBrains IDEs, Emacs, language runtimes and other tools
on the 42 school cluster machines. `42-dev-heal` runs them on every login;
they do nothing if everything is in place, and reinstall whatever a storage
wipe removed.

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

## How it works

Together, the scripts work like a small package manager for one user:

- **Registry and commands.** `lib/components.bash` lists every component.
  `42-dev-install` and `42-dev-uninstall` add or remove one, including its
  line in the heal manifest.
- **Desired state.** `~/Apps/etc/heal.list` lists what you want installed.
  `42-dev-heal` runs it on every login and reinstalls whatever is missing;
  new terminals report failed entries and storage that is nearly full.
- **Layout.** An install goes to `/sgoinfre/<tool>/<version>/`, its download
  is cached in `/sgoinfre/.cache/`, and launchers go in `~/bin`.
- **Pinned versions.** Each bootstrap has a default version, or takes one as
  an argument. A marker file in the install records what's there, and a
  different version means a reinstall.
- **Verified downloads.** Every archive a bootstrap downloads itself is
  checked against a sha256 published upstream, the digest GitHub records for
  a release asset, or apt's signed index. A mismatch deletes the download.
  Tools installed through mise, npm or uv rely on those tools' own checks.
- **Atomic installs.** An install is assembled in `<install>.tmp` and swapped
  in only when complete, so a failed or interrupted install leaves the
  previous one working.
- **One run at a time.** Runs of the same bootstrap with the same arguments
  take turns, through a lock on `/sgoinfre` that also covers a second machine.
- **Own builds.** Tools without a usable upstream binary (Emacs, wxWidgets,
  OCaml, inotify-tools) are built by this repo's GitHub Actions and
  published as releases with a `.sha256` file. A `-r<N>` tag marks a rebuild
  of the same version, which installs pick up on their next run.
- **Cache pruning.** After an upgrade, the bootstraps for the larger tools
  delete downloads the new version no longer needs.
- **Shared code and checks.** The bootstraps share `lib/bootstrap.bash`
  (see [Writing a bootstrap](#writing-a-bootstrap)), and `42-dev-validate`
  checks the scripts, the registry and the library's use.

## Scripts

### `jb-bootstrap <PRODUCT_CODE>[@VERSION] [owner/repo[@tag] …]`

Installs a JetBrains IDE.

- Binary, cached tarball and config go to `/sgoinfre`; indexes and logs go to
  `/goinfre`.
- Adds a `~/bin/<slug>` launcher and a `.desktop` entry with the IDE's icon.
  The launcher passes the IDE a properties file kept outside the install
  (`<ENV>_PROPERTIES`, e.g. `WEBIDE_PROPERTIES`), so an in-place IDE update
  that resets `bin/idea.properties` can't send it back to the default
  `~/.config` and `~/.local/share` paths in `$HOME`.
- Installs plugins from GitHub releases, since the marketplace often lags.
- `<CODE>@VERSION` pins an IDE release; `owner/repo@tag` pins a plugin.
  Without a pin, the IDE is the latest release at first install and then
  updates itself; the script only reinstalls it after a wipe or a pin change.
- Verifies the IDE tarball against JetBrains' published sha256, and each
  plugin zip against the digest GitHub records. A tarball cached before this
  check existed is extracted unverified once and replaced on the next
  download.
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
| `erlang` | Installs a CI-built wxWidgets 3.2 on `/sgoinfre` (`wx-bootstrap`, from this repo's `wx-<version>` release, sha256-verified) and compiles Erlang from source against it with the `asdf-erlang` plugin. mise's default prebuilt Erlang links against wx 3.0, which the cluster doesn't have, so `:observer.start()` would fail. |
| `erlang` or `elixir` | Adds the wx library path to `LD_LIBRARY_PATH` in `~/.profile`, and a logger filter to `~/.iex.exs` that hides harmless GTK3 style-context warnings. |
| `elixir` | Installs the `hex`, `rebar` and `phx_new` archives and the `livebook` escript for the active Elixir version. Without this, a version bump makes the next `mix deps.get` prompt, and `livebook` drops off `PATH`. |
| `node` | Reinstalls global npm packages listed in `~/Apps/etc/npm-globals.txt`. |
| `rust` | Sets `MISE_RUSTUP_HOME` and `MISE_CARGO_HOME` under `/sgoinfre`. The cluster's `/etc/zsh/zshenv` points `RUSTUP_HOME` and `CARGO_HOME` at root-owned `/opt/rust`, which isn't on `PATH`, so apt's `rustc` 1.75 would win. `mise activate` exports the user-owned paths, so `cargo install` and `rustup component add` work. |

The `~/.profile` and `~/.iex.exs` edits are marked with comments and only
added once.

### `emacs-bootstrap [VERSION]`

Installs Emacs with tree-sitter and native compilation (GTK3/X11). The
tarball is built by `.github/workflows/build-emacs.yml` and published as a
release on this repo, with a `.sha256` file that the bootstrap requires. To
build a new version, push an `emacs-<VERSION>` tag.

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
so `build-inotify-tools.yml` builds a static tarball, published with a
`.sha256` file that the bootstrap requires. Upstream's 4.25.9.0 tag still
declares 4.23.9.0, so the build sets the version string itself (release
`4.25.9.0-r1`). Upstream 4.26 is a Rust rewrite; the workflow builds the
4.25 line.

### `clangd-bootstrap`

Installs `clangd` from the `clangd/clangd` releases, verified against the
sha256 digest GitHub records for the release file (upstream publishes no
checksums file). `~/bin/clangd` shadows
apt's clangd 14, which rejects newer `.clang-format` keys such as
`InsertNewlineAtEOF`. Only `clangd` is included, but it has clang-format
built in, so formatting through the editor (e.g. `eglot-format-buffer`)
works.

`~/bin/clangd` is a wrapper that passes `--query-driver` for compilers under
`MISE_DATA_DIR`, so clangd reads the C++ headers of mise's GCC 16 instead of
the system GCC 12 ones (where `<print>` doesn't exist). Old versions are
removed when the version changes.

### `cuda-bootstrap [CUDA_PKG_SUFFIX]`

Installs CUDA 12, cuDNN 9 and NCCL 2 libraries without sudo, for GPU
EXLA (Nx/Axon). Downloads the packages from NVIDIA's Ubuntu 22.04 repository,
verifies each against the sha256 in the repository's package index, and
extracts them to `$SGO/cuda/` (about 3.7 GB, plus 1.7 GB of cached packages).
The tree is assembled in `$SGO/cuda.tmp` and swapped in when complete, so
switching versions never mixes libraries from two CUDA releases; the packages
are unpacked on local `/goinfre`, and cached packages the current version no
longer uses are deleted.

The default is CUDA 12.9 (`12-9`), which matches XLA's `nvrtc-builtins`
library; pass e.g. `12-8` for another minor version. `libxla_extension.so`
requires three NVSHMEM libraries that single-GPU work never calls, so the
script builds empty stubs with the right names. It adds `LD_LIBRARY_PATH`,
`PATH` and `XLA_FLAGS` to `~/.profile` once. Afterwards, recompile EXLA in
your project:

```sh
XLA_TARGET=cuda12 mix deps.compile exla --force
```

### `ocaml-bootstrap [RELEASE]`

Installs OCaml 5 with `ocamlfind`, `utop`, `ocaml-lsp-server` and `dune` from
a tarball built by `build-ocaml.yml`. apt's OCaml is 4.13, and building with
opam on NFS after each wipe would be slow.

The workflow builds at a neutral prefix, and the toolchain runs from wherever
it's unpacked (OCaml 5.5 finds its stdlib relative to the compiler). There is
no opam on the cluster: adding a package means editing the workflow and
rebuilding under a new `ocaml-<version>-r<N>` tag; the bootstrap's default
release then picks it up. `~/bin/ocaml`, `~/bin/utop` and `~/bin/ocamllsp` are
wrappers that set the variables `opam env` would, plus `OCAMLLIB` and
`OCAMLFIND_CONF` for the paths utop and ocamllsp carry from the build.

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
in `$HOME`. Reinstalls when the environment is gone. It pins Python 3.13:
aider's scipy has no prebuilt wheels for 3.14, and building it needs a
Fortran compiler. uv downloads that Python (about 110 MB) into
`~/.local/share/uv/python` unless `UV_PYTHON_INSTALL_DIR` points elsewhere.

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
Each run also starts the daemon (`~/bin/tailscale-serve`) unless it's already
up; `TAILSCALE_NO_START=1` installs without starting it.

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
missing key fails instead of waiting for a passphrase. One heal manifest line
per repository:

```sh
repo-bootstrap git@github.com:you/yourrepo.git
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

Then choose what reinstalls on login. Either pick components in
`42-dev-install` ("install+self-heal"), or list them in the
[heal manifest](#42-dev-heal) and add the login hook:

```sh
42-dev-heal --ensure-hook
```

Coming from an older setup with one `(nohup ~/Apps/bin/<x>-bootstrap &>/dev/null &)`
line per tool in `~/.zprofile`? `42-dev-heal --migrate` moves those lines into
the manifest, comments out the originals and adds the hook. It lists the
changes and asks first.

## Managing components

`lib/components.bash` is the registry of everything the bootstraps can
install: name, bootstrap command, install path on `/sgoinfre` and a short
description. Three commands work from it.

### `42-dev-install`

An fzf picker over the registry that shows each component's install state,
size, and whether it reinstalls on login. Enter on a row offers:

- **install**: run the bootstrap once.
- **install+self-heal**: run it and add it to the heal manifest, so it comes
  back after a wipe.

`42-dev-install --list` prints the same table without the picker. fzf comes
from mise (see [mise runtimes](#mise-runtimes)).

### `42-dev-uninstall`

The reverse, with the same picker. Each row shows how much space removing it
frees. Enter offers:

- **cleanup**: delete the files only. If the component is in the manifest,
  the next login reinstalls it, which is a cheap way to repair a broken install
  or free space for one session.
- **uninstall**: delete the files and comment out its manifest line.

Launcher symlinks in `~/bin` and `.desktop` entries pointing into the removed
directories go too. Non-interactive forms: `42-dev-uninstall <name>
[--uninstall] [-y]`, `--all-safe` for every reinstallable component, and
`--list` for a table with the reclaimable total. Components marked `DATA`
(IDE config, database data) have no bootstrap to restore them, and the
listing says so.

### `42-dev-heal`

Reinstalls what's missing on login. `~/Apps/etc/heal.list` holds one command
from `~/Apps/bin` per line; `#` starts a comment:

```sh
mise-bootstrap
emacs-bootstrap
jb-bootstrap IIU KronicDeth/intellij-elixir
tailscale-bootstrap
repo-bootstrap git@github.com:you/yourrepo.git
```

A single `~/.zprofile` line runs it in the background, so login isn't
blocked:

```sh
(nohup ~/Apps/bin/42-dev-heal &>/dev/null &)
```

It runs three entries at a time (`-j N`), each with a two-hour timeout
(`HEAL_TIMEOUT`), stdin closed and its own log in
`/goinfre/$USER/42-dev-heal/logs/`. A lock stops overlapping runs on the same
machine. The `zshrc.snippet` line `42-dev-heal --report` prints a line in
new terminals when the last run had failures, and one per storage tier that
is nearly full; otherwise it prints nothing:

```
42-dev-heal: $HOME is 87% full (8.1G of 9.3G); when full, nothing can be written. See 42-dev-heal --disk
42-dev-heal: /sgoinfre holds 27.4G of 30.0G; a folder over 30 GB is wiped Sunday night. See 42-dev-heal --disk
```

The thresholds are 85% of `$HOME` (`HEAL_HOME_WARN_PCT`) and 27 GiB on
`/sgoinfre` (`HEAL_SGO_WARN_GB`). The check uses `df` and `quota`, which take
milliseconds.

| Command | Does |
|---|---|
| `42-dev-heal` | Run every manifest entry |
| `42-dev-heal --status` | Disk usage of both tiers, then the result, duration and log path of each entry from the last run |
| `42-dev-heal --disk` | Disk usage and the largest directories in `$HOME` and `/sgoinfre`, labelled with the components installed there (walks `/sgoinfre`: about 30 s) |
| `42-dev-heal --failed` | Run again only what failed |
| `42-dev-heal --ensure-hook` | Create the manifest and add the `~/.zprofile` line if missing |
| `42-dev-heal --migrate` | Move old `(nohup ~/Apps/bin/<x> &>/dev/null &)` lines from the shell init files into the manifest and comment them out |

Run state lives on `/goinfre`, so it's per machine: `--status` on another
machine shows that machine's last run.

## Writing a bootstrap

`lib/bootstrap.bash` has the shared parts. Sourcing it sets `$SGO` and
`$CACHE` (`$SGO/.cache`) and provides:

| Helper | Does |
|---|---|
| `fetch URL DEST` | Download to `DEST` unless it's already cached; goes through `DEST.part`, so an interrupted download is never reused |
| `verify_sha256 FILE SUMS [NAME]` | Check `FILE` against its line in a `sha256sum`-style list, or against a file holding only the hash; on a mismatch, delete both so the next run downloads them again |
| `fetch_github_digest REPO TAG ASSET DEST` | For releases without a checksums file: write the sha256 GitHub records for `ASSET` to `DEST`, for `verify_sha256` |
| `apt_download DIR PKG[=VER]…` | Fetch `.debs` without root (`apt-get download`, checked against the signed apt index), to unpack with `dpkg-deb -x` |
| `needs_install APP_HOME VERSION BIN` | True if `BIN` is missing or another version is installed |
| `install_tarball TARBALL APP_HOME VERSION [TAR_ARGS…]` | Extract into `APP_HOME.tmp`, record the version, swap it in |
| `install_begin` / `install_commit APP_HOME VERSION` | The same swap for layouts `install_tarball` can't handle: fill `APP_HOME.tmp` in between (see `clangd-bootstrap`) |
| `link_launcher TARGET [NAME]` | Symlink `~/bin/NAME` to `TARGET` |
| `link_launchers DIR` | Symlink every executable in `DIR` into `~/bin` |
| `write_launcher NAME` | Write stdin to `~/bin/NAME` as an executable wrapper script, for launchers that need environment or arguments |
| `write_desktop_entry NAME` | Write stdin to `~/.local/share/applications/NAME.desktop` and refresh the desktop database |
| `log`, `die` | Messages prefixed with the script name (set `BS_LOG_NAME` to change the prefix, as `jb-bootstrap` does per IDE) |

Sourcing the library also makes runs of the same bootstrap with the same
arguments take turns: the script re-runs itself under `flock`, with the
lock in `$SGO/.cache/.locks/`, so it covers a second machine too. A login
heal run that starts while you run a bootstrap by hand waits, then finds the
install done, instead of extracting into the same `APP_HOME.tmp`. Daemons a
bootstrap starts don't inherit the lock. A run gives up after
`BOOTSTRAP_LOCK_TIMEOUT` seconds (default 7200).

`inotify-tools-bootstrap` is the shortest example, `ghidra-bootstrap` the fullest (two
installs, a wrapper and a desktop entry). `install.sh` copies everything in
`bin/` and `lib/`, so a new script needs no other registration; add a
registry row in `lib/components.bash` if `42-dev-install` should offer it.

To try a bootstrap without touching your real installs, point it at scratch
directories:

```sh
BOOTSTRAP_SGO=/goinfre/$USER/sgo-test HOME=/goinfre/$USER/home-test bin/inotify-tools-bootstrap
```

`42-dev-install` and `42-dev-uninstall` honour `BOOTSTRAP_SGO` too. A script
that found `/sgoinfre` from `$USER` itself would ignore it, so a test would
touch your real installs. `bin/42-dev-validate` counts the bootstraps on the
library, fails on one that still does its own lookup, and lists any other
script that does:

```
[ok] lib/bootstrap.bash: 16 of 19 bootstraps
```

The three others don't look up `/sgoinfre`: `docker` and `repo` work on
`/goinfre`, and `aider` installs into `UV_TOOL_DIR` from your profile.

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

Current C/C++ compilers and tools come from conda-forge through mise's
`conda:` backend. The cluster's newest is g++-12, whose standard library lacks
most of C++23. Programs built with these compilers find the newer
`libstdc++` through an rpath, without `LD_LIBRARY_PATH`:

```toml
"conda:gxx" = "16.2.0"            # g++ / c++
"conda:clangxx" = "23.1.5"        # clang++, uses GCC 16's libstdc++
"conda:clang-format" = "23.1.5"
"pipx:clang-tidy" = "23.1.4"      # see "Open" below
"conda:libcxx-devel" = "23.1.5"   # libc++ for clang++-libcxx
```

Only `g++`/`c++` and `clang++` change; `gcc`/`cc` and `clang` stay the system
versions. Use `clangd-bootstrap` for clangd, not conda's `clang-tools`: its
clangd and clang-tidy can't find clang's built-in headers and would shadow the
`~/bin/clangd` wrapper.

`clang++-libcxx` (installed to `~/Apps/bin`) runs clang++ against libc++ with
extensive hardening, which traps on checks like out-of-range `operator[]`.
Use it as the compiler of a separate build directory:

```sh
cmake -S . -B build-libcxx -DCMAKE_CXX_COMPILER=clang++-libcxx
```

For a message instead of a bare trap, add
`-U_LIBCPP_HARDENING_MODE -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG`.

Extras are only set up for tools in the config. Global npm packages go in
`~/Apps/etc/npm-globals.txt`, one per line.

Single-binary CLI tools that publish GitHub releases need no bootstrap of
their own: mise's registry installs them through the `aqua:` backend, which
verifies each download's checksum, and for some tools a cosign signature or
GitHub's build attestation as well. These replaced the earlier
`gh`/`fzf`/`glow`/`act`/`actionlint` bootstraps:

```toml
gh = "2.91.0"           # newer than apt's
fzf = "0.65.2"          # also the picker in 42-dev-install/-uninstall
glow = "3.0.0"          # terminal Markdown viewer
act = "0.2.88"          # runs GitHub Actions locally, on rootless Docker
actionlint = "1.7.7"    # GitHub Actions workflow linter
```

GUI apps see these too: `shell/profile.snippet` puts mise's shims on `PATH`.
`mise latest <tool>` shows the newest version; `mise use -g <tool>@<version>`
moves the pin.

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
| mise runtimes and tools (gh, fzf, glow, act, actionlint), OpenCode | yes | `mise install` from config.toml |
| Global npm packages | yes | Reinstalled from npm-globals.txt |
| Go tools (`~/go/bin/*`) | not affected | Live in $HOME |
| Emacs, PostgreSQL, inotify-tools, clangd, OCaml, Ghidra + JDK, Tailscale, Tor Browser | yes | Reinstalled |
| graphviz, torsocks | yes | Reinstalled from cached .debs or `apt-get download` |
| CUDA libraries | yes | Re-extracted from cached .debs, else downloaded from NVIDIA's repository |
| ollama models | yes | Missing models from ollama-models.txt pulled again |
| gh and Tailscale auth | not affected | Live in $HOME |
| Docker config after a /goinfre wipe | yes | `daemon.json` is in $HOME; data-root recreated and daemon restarted |
| Docker images, volumes, containers | no | On /goinfre; rebuild or pull again |
| Working clones on /goinfre | yes | `repo-bootstrap` clones them again |
| Uncommitted work in those clones | no | Commit and push before logging out |

## Open

- MemorySanitizer: conda's clang ships the MSan runtime, but MSan also needs
  a libc++ built with `-fsanitize=memory`, which nobody ships. Plan: build
  libc++/libc++abi 23.1.5 with MSan in CI and add a `clang++-msan` launcher
  next to `clang++-libcxx`.
- `clang-tidy` from the command line reads the system GCC 12 headers
  (`'print' file not found`), because unlike clangd it has no
  `--query-driver`. `--extra-arg-before=--gcc-install-dir=<dir of
  $(g++ -print-libgcc-file-name)>` fixes it. Either wrap it, or rely on
  clangd's built-in clang-tidy in the editor.
- `42-dev-uninstall` leaves a JetBrains IDE's `$SGO/jetbrains-config/<ide>`
  and `/goinfre/$USER/jetbrains/<ide>` behind.
- mise exposes conda clangxx's `x86_64-conda-linux-gnu-clang++.cfg` as a
  command on `PATH`. Harmless, but noise.

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

Package-manager features not built yet, roughly in order of usefulness:

- **Update checking.** Versions are pinned inside each script, and nothing
  reports a newer upstream release. A `42-dev-outdated` command could
  compare each pinned version with upstream's latest.
- **Metadata in one place.** A tool's version, download URL and checksum
  source live in its script, not in the registry, so "what's pinned, what's
  installed" can't be answered without reading code.
- **File lists.** `42-dev-uninstall` removes a component by path patterns
  rather than a record of the files its install created, so a pattern can
  miss something.
- **Declared dependencies.** Some exist (`mise-bootstrap` needs
  `wx-bootstrap`, `jb-bootstrap` runs `jb-sync-elixir-sdk`), but they are
  wired into the scripts rather than declared.
- **Rollback.** An upgrade replaces the previous version, so there is
  nothing to go back to.

## License

[Unlicense](./LICENSE): public domain, no warranty.
