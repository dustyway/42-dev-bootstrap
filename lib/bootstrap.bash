#!/usr/bin/env bash
# Shared helpers for bin/*-bootstrap. Source it near the top of a bootstrap:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/bootstrap.bash"
#
# That path works both from the repo (bin/ → lib/) and from the installed
# copy (~/Apps/bin → ~/Apps/lib). Sourcing sets:
#
#   BS_NAME   the script's name, used in log lines and the version marker
#             (set BS_LOG_NAME to change only the log prefix)
#   SGO      the user's /sgoinfre directory (BOOTSTRAP_SGO overrides it,
#             so tests can point a bootstrap at a scratch directory)
#   CACHE     $SGO/.cache, where downloads are kept for re-extraction
#
# Typical use, for a tool shipped as a tarball:
#
#   APP_HOME="$SGO/foo/$VERSION"
#   if needs_install "$APP_HOME" "$VERSION" foo; then
#       fetch "$URL" "$CACHE/$ASSET"
#       fetch "$SUMS_URL" "$CACHE/foo_${VERSION}_checksums.txt"
#       verify_sha256 "$CACHE/$ASSET" "$CACHE/foo_${VERSION}_checksums.txt"
#       install_tarball "$CACHE/$ASSET" "$APP_HOME" "$VERSION" foo
#   fi
#   link_launcher "$APP_HOME/foo"

BS_NAME="${BS_NAME:-$(basename "$0")}"

log() { printf '[%s] %s\n' "${BS_LOG_NAME:-$BS_NAME}" "$*"; }
die() { log "$*" >&2; exit 1; }

if [[ -n "${BOOTSTRAP_SGO:-}" ]]; then
    SGO="$BOOTSTRAP_SGO"
else
    SGO="$(ls -d /sgoinfre/goinfre/Perso/*"${USER}"* 2>/dev/null | head -n1)"
fi
[[ -n "$SGO" && -d "$SGO" ]] || die "sgoinfre path not found for $USER"
CACHE="$SGO/.cache"
mkdir -p "$CACHE"

# One run at a time per bootstrap and arguments (so jb-bootstrap WS and
# jb-bootstrap PCP still run in parallel). Two concurrent installs share
# APP_HOME.tmp and delete each other's half-extracted files: a login heal
# run started during a manual run once left an install missing 9 of its
# libraries. The lock is on $SGO, so it also covers another machine; the
# second run waits, then finds the install done.
#
# The script re-executes itself under `flock -o`: the flock process holds the
# lock until the script exits, and the script gets no copy of the lock's file
# descriptor, so daemons it starts (tailscaled, ollama serve) can't keep
# holding it. _BS_LOCKED names the key already held, so a bootstrap that
# calls another (mise-bootstrap → wx-bootstrap) still locks the inner one.
_bs_lock_key=$(printf '%s' "$BS_NAME $*" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-120)
if [[ "${_BS_LOCKED:-}" != "$_bs_lock_key" ]]; then
    mkdir -p "$CACHE/.locks"
    _bs_lock="$CACHE/.locks/$_bs_lock_key"
    # To stderr: wx-bootstrap's stdout carries only its install path.
    flock -n "$_bs_lock" true || log "another run is in progress; waiting for it" >&2
    _BS_LOCKED="$_bs_lock_key" exec flock -o -w "${BOOTSTRAP_LOCK_TIMEOUT:-7200}" \
        "$_bs_lock" "$0" "$@"
fi

# fetch URL DEST
# Download URL to DEST unless DEST is already there. The download goes to
# DEST.part first, so an interrupted one is never mistaken for a cached file.
fetch() {
    local url="$1" dest="$2"
    [[ -s "$dest" ]] && return 0
    log "downloading $(basename "$dest")"
    mkdir -p "$(dirname "$dest")"
    # Progress meter only on a terminal; in 42-dev-heal logs it's noise.
    local quiet=()
    [[ -t 2 ]] || quiet=(-sS)
    curl -fL --retry 3 "${quiet[@]}" -o "$dest.part" "$url" || { rm -f "$dest.part"; die "download failed: $url"; }
    mv "$dest.part" "$dest"
}

# verify_sha256 FILE SUMS [NAME]
# Check FILE against the entry for NAME (default: FILE's basename) in SUMS, a
# `sha256sum`-style list ("<hash>  <name>", "<hash> *<name>" and single-space
# forms all work), or a file holding only the bare hash. Use NAME when the
# cached file was renamed from the upstream asset name. On a mismatch or a
# missing entry, FILE and SUMS are deleted so the next run downloads both
# again.
verify_sha256() {
    local file="$1" sums="$2" name="${3:-$(basename "$1")}" want got
    want=$(awk -v n="$name" '
        NR == 1 && NF == 1 && $1 ~ /^[0-9a-f]+$/ && length($1) == 64 { bare = $1 }
        { f = $2; sub(/^\*/, "", f) }
        f == n { print $1; found = 1; exit }
        END { if (!found && NR == 1 && bare != "") print bare }' "$sums")
    if [[ -z "$want" ]]; then
        rm -f "$file" "$sums"
        die "no sha256 for $name in $(basename "$sums")"
    fi
    got=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$got" != "$want" ]]; then
        rm -f "$file" "$sums"
        die "sha256 mismatch for $name"
    fi
}

# fetch_github_digest OWNER/REPO TAG ASSET DEST
# For releases without a checksums file: write the sha256 that GitHub records
# for ASSET (the API's `digest` field) to DEST as a sha256sum line, for
# verify_sha256. Unauthenticated API calls are limited to 60 an hour, which is
# plenty: this runs only when installing, and DEST is cached afterwards.
fetch_github_digest() {
    local repo="$1" tag="$2" asset="$3" dest="$4" json digest
    [[ -s "$dest" ]] && return 0
    json=$(curl -fsSL --retry 3 "https://api.github.com/repos/$repo/releases/tags/$tag") \
        || die "GitHub API request failed for $repo $tag"
    digest=$(python3 -I -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(a.get("digest") or "")
' "$asset" <<<"$json")
    [[ "$digest" == sha256:* ]] || die "GitHub has no sha256 digest for $asset in $repo $tag"
    printf '%s  %s\n' "${digest#sha256:}" "$asset" >"$dest"
}

# apt_download DIR PACKAGE[=VERSION]...
# Fetch .debs into DIR without root. apt-get checks them against the signed
# apt index, so no separate checksum is needed. apt-get warns that it can't
# drop privileges to `_apt` when DIR isn't readable by that user; the
# download still succeeds.
apt_download() {
    local dir="$1"
    shift
    log "downloading $* (apt)"
    mkdir -p "$dir"
    (cd "$dir" && apt-get download "$@") || die "apt-get download failed: $*"
}

# installed_version APP_HOME — the version recorded by install_tarball, or "".
installed_version() {
    local marker="$1/.$BS_NAME-version"
    [[ -f "$marker" ]] && cat "$marker" || true
}

# needs_install APP_HOME VERSION BIN
# True if APP_HOME/BIN isn't executable or APP_HOME holds another version.
needs_install() {
    local app="$1" version="$2" bin="$3" have
    have=$(installed_version "$app")
    [[ -x "$app/$bin" && "$have" == "$version" ]] && return 1
    [[ -n "$have" && "$have" != "$version" ]] && log "switching version: '$have' -> '${version:-unpinned}'"
    return 0
}

# install_begin APP_HOME VERSION / install_commit APP_HOME VERSION
# For layouts install_tarball can't handle: install_begin gives an empty
# APP_HOME.tmp to fill, install_commit records VERSION and swaps it in for
# APP_HOME. A failure in between leaves the old APP_HOME (if any) untouched
# until the next run.
install_begin() {
    local app="$1" version="$2"
    log "installing ${version:+$version }to $app"
    rm -rf "$app.tmp"
    mkdir -p "$app.tmp"
}
install_commit() {
    local app="$1" version="$2"
    printf '%s' "$version" >"$app.tmp/.$BS_NAME-version"
    rm -rf "$app"
    mv "$app.tmp" "$app"
}

# install_tarball TARBALL APP_HOME VERSION [TAR_ARGS...]
# Extract TARBALL into APP_HOME via install_begin/install_commit and record
# VERSION. TAR_ARGS go after the archive, e.g. member names or
# --strip-components=1.
install_tarball() {
    local tarball="$1" app="$2" version="$3"
    shift 3
    install_begin "$app" "$version"
    tar -xf "$tarball" -C "$app.tmp" "$@" || { rm -rf "$app.tmp"; die "extracting $(basename "$tarball") failed"; }
    install_commit "$app" "$version"
}

# link_launchers DIR
# Symlink every executable file in DIR into ~/bin under its own name.
link_launchers() {
    local f
    for f in "$1"/*; do
        [[ -f "$f" && -x "$f" ]] && link_launcher "$f"
    done
    return 0
}

# write_launcher NAME
# Write stdin to ~/bin/NAME as an executable script, for launchers that need
# environment or arguments a symlink can't carry. Removes the old file first,
# so an old symlink is replaced rather than written through.
write_launcher() {
    local dest="$HOME/bin/$1"
    mkdir -p "$HOME/bin"
    rm -f "$dest"
    cat >"$dest"
    chmod 0755 "$dest"
}

# write_desktop_entry NAME
# Write stdin to ~/.local/share/applications/NAME.desktop and refresh the
# desktop database. Rewritten every run, so paths follow version switches.
write_desktop_entry() {
    local dir="$HOME/.local/share/applications"
    mkdir -p "$dir"
    cat >"$dir/$1.desktop"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$dir" >/dev/null 2>&1 || true
    fi
}

# link_launcher TARGET [NAME]
# Symlink ~/bin/NAME (default: TARGET's basename) to TARGET.
link_launcher() {
    local target="$1" name="${2:-$(basename "$1")}"
    mkdir -p "$HOME/bin"
    ln -sfn "$target" "$HOME/bin/$name"
}
