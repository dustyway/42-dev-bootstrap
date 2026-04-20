#!/bin/sh
# Relocation wrapper — installed as bin/emacs, replacing the symlink that
# make-install creates. Sets EMACS* env vars relative to this script's own
# location so the install tree is portable across extract paths. Without
# this, the absolute --prefix baked in at configure time (/opt/emacs) wins
# and Emacs can't find its lisp/libexec dirs unless installed literally there.
#
# __EMACS_VERSION__ / __EMACS_ARCH__ are substituted by the CI workflow.
VER=__EMACS_VERSION__
ARCH=__EMACS_ARCH__
here="$(cd "$(dirname -- "$(readlink -f -- "$0" 2>/dev/null || printf '%s\n' "$0")")" && pwd)"
root="$(cd "$here/.." && pwd)"
EMACSLOADPATH="$root/share/emacs/$VER/site-lisp:$root/share/emacs/$VER/lisp:$root/share/emacs/site-lisp"
EMACSDATA="$root/share/emacs/$VER/etc"
EMACSDOC="$root/share/emacs/$VER/etc"
EMACSPATH="$root/libexec/emacs/$VER/$ARCH:$root/libexec"
INFOPATH="$root/share/info${INFOPATH:+:$INFOPATH}"
export EMACSLOADPATH EMACSDATA EMACSDOC EMACSPATH INFOPATH
exec "$root/bin/emacs-$VER" "$@"
