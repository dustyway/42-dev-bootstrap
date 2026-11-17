#!/usr/bin/env bash
# Shared helpers for bin/*-bootstrap. Source it near the top of a bootstrap:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/bootstrap.bash"
#
# That path works both from the repo (bin/ → lib/) and from the installed
# copy (~/Apps/bin → ~/Apps/lib). Sourcing sets:
#
#   BS_NAME   the script's name, used in log lines and the version marker
#   SGO       the user's /sgoinfre directory (BOOTSTRAP_SGO overrides it,
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

log() { printf '[%s] %s\n' "$BS_NAME" "$*"; }
die() { log "$*" >&2; exit 1; }

if [[ -n "${BOOTSTRAP_SGO:-}" ]]; then
    SGO="$BOOTSTRAP_SGO"
else
    SGO="$(ls -d /sgoinfre/goinfre/Perso/*"${USER}"* 2>/dev/null | head -n1)"
fi
[[ -n "$SGO" && -d "$SGO" ]] || die "sgoinfre path not found for $USER"
CACHE="$SGO/.cache"
mkdir -p "$CACHE"

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
# forms all work). Use NAME when the cached file was renamed from the
# upstream asset name. On a mismatch or a missing entry, FILE and SUMS are
# deleted so the next run downloads both again.
verify_sha256() {
    local file="$1" sums="$2" name="${3:-$(basename "$1")}" want got
    want=$(awk -v n="$name" '{ f = $2; sub(/^\*/, "", f) } f == n { print $1; exit }' "$sums")
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
    [[ -n "$have" && "$have" != "$version" ]] && log "switching version: '$have' -> '$version'"
    return 0
}

# install_tarball TARBALL APP_HOME VERSION [TAR_ARGS...]
# Extract TARBALL into APP_HOME (via APP_HOME.tmp, so a failed extract leaves
# no half-installed tree) and record VERSION. TAR_ARGS go after the archive,
# e.g. member names or --strip-components=1.
install_tarball() {
    local tarball="$1" app="$2" version="$3"
    shift 3
    log "installing $version to $app"
    rm -rf "$app.tmp" "$app"
    mkdir -p "$app.tmp"
    tar -xf "$tarball" -C "$app.tmp" "$@" || { rm -rf "$app.tmp"; die "extracting $(basename "$tarball") failed"; }
    printf '%s' "$version" >"$app.tmp/.$BS_NAME-version"
    mv "$app.tmp" "$app"
}

# link_launcher TARGET [NAME]
# Symlink ~/bin/NAME (default: TARGET's basename) to TARGET.
link_launcher() {
    local target="$1" name="${2:-$(basename "$1")}"
    mkdir -p "$HOME/bin"
    ln -sfn "$target" "$HOME/bin/$name"
}
