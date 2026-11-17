#!/usr/bin/env bash
# install.sh — copy the bootstrap scripts into ~/Apps/bin/, seed the npm
# globals list if missing, and remind the user which shell snippets still
# need to be pasted. Safe to re-run (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/Apps/bin" "$HOME/Apps/etc" "$HOME/Apps/lib"

# Everything in bin/ and lib/: a new script needs no line here.
for f in "$REPO_ROOT"/bin/*; do
    install -m 0755 "$f" "$HOME/Apps/bin/$(basename "$f")"
done
for f in "$REPO_ROOT"/lib/*.bash; do
    install -m 0644 "$f" "$HOME/Apps/lib/$(basename "$f")"
done

# Record what was installed, for `42-dev-heal --status`. "dirty" means the
# working copy had uncommitted changes, so ~/Apps may differ from the commit.
{
    commit=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
    dirty=no
    if [[ "$commit" != unknown && -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
        dirty=yes
    fi
    printf 'commit=%s\ndirty=%s\ninstalled=%s\nrepo=%s\n' \
        "$commit" "$dirty" "$(date '+%Y-%m-%d %H:%M')" "$REPO_ROOT"
} > "$HOME/Apps/etc/42-dev-bootstrap.version"

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
