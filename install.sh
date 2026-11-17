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
install -m 0755 "$REPO_ROOT/bin/docker-build"             "$HOME/Apps/bin/docker-build"
install -m 0755 "$REPO_ROOT/bin/inotify-tools-bootstrap"   "$HOME/Apps/bin/inotify-tools-bootstrap"
install -m 0755 "$REPO_ROOT/bin/clangd-bootstrap"          "$HOME/Apps/bin/clangd-bootstrap"
install -m 0755 "$REPO_ROOT/bin/gh-bootstrap"              "$HOME/Apps/bin/gh-bootstrap"
install -m 0755 "$REPO_ROOT/bin/ghidra-bootstrap"          "$HOME/Apps/bin/ghidra-bootstrap"
install -m 0755 "$REPO_ROOT/bin/ocaml-bootstrap"           "$HOME/Apps/bin/ocaml-bootstrap"
install -m 0755 "$REPO_ROOT/bin/graphviz-bootstrap"        "$HOME/Apps/bin/graphviz-bootstrap"
install -m 0755 "$REPO_ROOT/bin/ollama-bootstrap"          "$HOME/Apps/bin/ollama-bootstrap"
install -m 0755 "$REPO_ROOT/bin/aider-bootstrap"           "$HOME/Apps/bin/aider-bootstrap"
install -m 0755 "$REPO_ROOT/bin/opencode-bootstrap"        "$HOME/Apps/bin/opencode-bootstrap"
install -m 0755 "$REPO_ROOT/bin/cuda-bootstrap"            "$HOME/Apps/bin/cuda-bootstrap"
install -m 0755 "$REPO_ROOT/bin/tailscale-bootstrap"       "$HOME/Apps/bin/tailscale-bootstrap"
install -m 0755 "$REPO_ROOT/bin/tor-browser-bootstrap"     "$HOME/Apps/bin/tor-browser-bootstrap"
install -m 0755 "$REPO_ROOT/bin/torsocks-bootstrap"        "$HOME/Apps/bin/torsocks-bootstrap"
install -m 0755 "$REPO_ROOT/bin/actionlint-bootstrap"      "$HOME/Apps/bin/actionlint-bootstrap"
install -m 0755 "$REPO_ROOT/bin/act-bootstrap"             "$HOME/Apps/bin/act-bootstrap"
install -m 0755 "$REPO_ROOT/bin/fzf-bootstrap"             "$HOME/Apps/bin/fzf-bootstrap"
install -m 0755 "$REPO_ROOT/bin/glow-bootstrap"            "$HOME/Apps/bin/glow-bootstrap"
install -m 0755 "$REPO_ROOT/bin/clang++-libcxx"            "$HOME/Apps/bin/clang++-libcxx"
install -m 0755 "$REPO_ROOT/bin/repo-bootstrap"            "$HOME/Apps/bin/repo-bootstrap"
install -m 0755 "$REPO_ROOT/bin/jb-sync-elixir-sdk"        "$HOME/Apps/bin/jb-sync-elixir-sdk"
install -m 0755 "$REPO_ROOT/bin/42-dev-install"            "$HOME/Apps/bin/42-dev-install"
install -m 0755 "$REPO_ROOT/bin/42-dev-uninstall"          "$HOME/Apps/bin/42-dev-uninstall"
install -m 0755 "$REPO_ROOT/bin/42-dev-validate"           "$HOME/Apps/bin/42-dev-validate"
install -m 0755 "$REPO_ROOT/bin/42-dev-heal"               "$HOME/Apps/bin/42-dev-heal"
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

Then pick what reinstalls on every login, either with the TUI
(\`42-dev-install\`, "install+self-heal") or by listing commands in
~/Apps/etc/heal.list, one per line, e.g.:

  mise-bootstrap
  emacs-bootstrap
  jb-bootstrap IIU KronicDeth/intellij-elixir
  repo-bootstrap git@github.com:you/yourrepo.git

and add the login hook that runs them (creates the manifest if missing):

  42-dev-heal --ensure-hook

Coming from \`(nohup ~/Apps/bin/<x>-bootstrap &>/dev/null &)\` lines in
~/.zprofile? \`42-dev-heal --migrate\` moves them into the manifest.

Adjust the JetBrains product code (IIU, WS, CL, …) and plugin list to taste.
See README.md for the full list of supported products and plugin-spec syntax.
EOF
