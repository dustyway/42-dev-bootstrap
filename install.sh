#!/usr/bin/env bash
# install.sh — copy the bootstrap scripts into ~/Apps/bin/, seed the npm
# globals list if missing, and remind the user which shell snippets still
# need to be pasted. Safe to re-run (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/Apps/bin" "$HOME/Apps/etc" "$HOME/Apps/lib"

install -m 0755 "$REPO_ROOT/bin/jb-bootstrap"              "$HOME/Apps/bin/jb-bootstrap"
install -m 0755 "$REPO_ROOT/bin/mise-bootstrap"            "$HOME/Apps/bin/mise-bootstrap"
install -m 0755 "$REPO_ROOT/bin/wx-bootstrap"              "$HOME/Apps/bin/wx-bootstrap"
install -m 0755 "$REPO_ROOT/bin/emacs-bootstrap"           "$HOME/Apps/bin/emacs-bootstrap"
install -m 0755 "$REPO_ROOT/bin/postgres-bootstrap"        "$HOME/Apps/bin/postgres-bootstrap"
install -m 0755 "$REPO_ROOT/bin/docker-bootstrap"          "$HOME/Apps/bin/docker-bootstrap"
install -m 0755 "$REPO_ROOT/bin/inotify-tools-bootstrap"   "$HOME/Apps/bin/inotify-tools-bootstrap"
install -m 0755 "$REPO_ROOT/bin/clangd-bootstrap"          "$HOME/Apps/bin/clangd-bootstrap"
install -m 0755 "$REPO_ROOT/bin/gh-bootstrap"              "$HOME/Apps/bin/gh-bootstrap"
install -m 0755 "$REPO_ROOT/bin/graphviz-bootstrap"        "$HOME/Apps/bin/graphviz-bootstrap"
install -m 0755 "$REPO_ROOT/bin/ollama-bootstrap"          "$HOME/Apps/bin/ollama-bootstrap"
install -m 0755 "$REPO_ROOT/bin/aider-bootstrap"           "$HOME/Apps/bin/aider-bootstrap"
install -m 0755 "$REPO_ROOT/bin/opencode-bootstrap"        "$HOME/Apps/bin/opencode-bootstrap"
install -m 0755 "$REPO_ROOT/bin/cuda-bootstrap"            "$HOME/Apps/bin/cuda-bootstrap"
install -m 0755 "$REPO_ROOT/bin/tailscale-bootstrap"       "$HOME/Apps/bin/tailscale-bootstrap"
install -m 0755 "$REPO_ROOT/bin/actionlint-bootstrap"      "$HOME/Apps/bin/actionlint-bootstrap"
install -m 0755 "$REPO_ROOT/bin/act-bootstrap"             "$HOME/Apps/bin/act-bootstrap"
install -m 0755 "$REPO_ROOT/bin/fzf-bootstrap"             "$HOME/Apps/bin/fzf-bootstrap"
install -m 0755 "$REPO_ROOT/bin/jb-sync-elixir-sdk"        "$HOME/Apps/bin/jb-sync-elixir-sdk"
install -m 0755 "$REPO_ROOT/bin/42-dev-install"            "$HOME/Apps/bin/42-dev-install"
install -m 0755 "$REPO_ROOT/bin/42-dev-uninstall"          "$HOME/Apps/bin/42-dev-uninstall"
install -m 0755 "$REPO_ROOT/bin/42-dev-validate"           "$HOME/Apps/bin/42-dev-validate"
install -m 0644 "$REPO_ROOT/lib/components.bash"           "$HOME/Apps/lib/components.bash"

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
  nohup \$HOME/Apps/bin/docker-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/inotify-tools-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/clangd-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/gh-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/graphviz-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/ollama-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/aider-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/opencode-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/cuda-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/tailscale-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/actionlint-bootstrap &>/dev/null & disown
  nohup \$HOME/Apps/bin/act-bootstrap &>/dev/null & disown

Adjust the JetBrains product code (IIU, WS, CL, …) and plugin list to taste.
See README.md for the full list of supported products and plugin-spec syntax.
EOF
