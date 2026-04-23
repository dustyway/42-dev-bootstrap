#!/usr/bin/env bash
# install.sh — copy the bootstrap scripts into ~/Apps/bin/, seed the npm
# globals list if missing, and remind the user which shell snippets still
# need to be pasted. Safe to re-run (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/Apps/bin" "$HOME/Apps/etc"

install -m 0755 "$REPO_ROOT/bin/jb-bootstrap"              "$HOME/Apps/bin/jb-bootstrap"
install -m 0755 "$REPO_ROOT/bin/mise-bootstrap"            "$HOME/Apps/bin/mise-bootstrap"
install -m 0755 "$REPO_ROOT/bin/emacs-bootstrap"           "$HOME/Apps/bin/emacs-bootstrap"
install -m 0755 "$REPO_ROOT/bin/postgres-bootstrap"        "$HOME/Apps/bin/postgres-bootstrap"
install -m 0755 "$REPO_ROOT/bin/inotify-tools-bootstrap"   "$HOME/Apps/bin/inotify-tools-bootstrap"
install -m 0755 "$REPO_ROOT/bin/clangd-bootstrap"          "$HOME/Apps/bin/clangd-bootstrap"
install -m 0755 "$REPO_ROOT/bin/gh-bootstrap"              "$HOME/Apps/bin/gh-bootstrap"
install -m 0755 "$REPO_ROOT/bin/jb-patch-elixir-debugger"  "$HOME/Apps/bin/jb-patch-elixir-debugger"
install -m 0755 "$REPO_ROOT/bin/jb-sync-elixir-sdk"        "$HOME/Apps/bin/jb-sync-elixir-sdk"

if [[ ! -e "$HOME/Apps/etc/npm-globals.txt" ]]; then
    cp "$REPO_ROOT/etc/npm-globals.txt.example" "$HOME/Apps/etc/npm-globals.txt"
    echo "[install] seeded $HOME/Apps/etc/npm-globals.txt (edit to customize)"
fi

cat <<EOF

[install] scripts installed to $HOME/Apps/bin/

Next steps — paste the shell snippets into your rc files:
  ~/.profile  ← $REPO_ROOT/shell/profile.snippet
  ~/.zshrc    ← $REPO_ROOT/shell/zshrc.snippet

Then add a login-time hook to ~/.zprofile, e.g.:

  nohup \$HOME/Apps/bin/jb-bootstrap IIU KronicDeth/intellij-elixir &>/dev/null & disown
  nohup \$HOME/Apps/bin/mise-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/emacs-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/postgres-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/inotify-tools-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/clangd-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/gh-bootstrap &>/dev/null & disown

Adjust the JetBrains product code (IIU, WS, CL, …) and plugin list to taste.
See README.md for the full list of supported products and plugin-spec syntax.
EOF
