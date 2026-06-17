#!/usr/bin/env bash
# Shared component registry for 42-dev-install and 42-dev-uninstall.
#
# Row format:
#   name | bootstrap_cmd | sgo_subpath | restore_pattern | class | description
#
# - bootstrap_cmd   : exact argv to exec, relative to ~/Apps/bin
# - sgo_subpath     : installed? check, expanded under $SGO
# - restore_pattern : ERE for matching an active shell-init bootstrap line
# - class           : "safe" if bootstrap can restore it, "DATA" otherwise
# - description     : one-line human description

COMPONENTS=(
    "emacs|emacs-bootstrap|emacs|emacs-bootstrap|safe|Modern Emacs (tree-sitter + native-comp, GTK3/X11) ~100 MB"
    "clangd|clangd-bootstrap|clangd|clangd-bootstrap|safe|clangd LSP server for C/C++ ~250 MB"
    "postgres|postgres-bootstrap|postgres|postgres-bootstrap|safe|PostgreSQL server binary (theseus-rs prebuilt) ~40 MB"
    "docker|docker-bootstrap|docker|docker-bootstrap|safe|Rootless Docker: data-root -> /goinfre, daemon.json healed in \$HOME (no sgoinfre payload)"
    "gh|gh-bootstrap|gh|gh-bootstrap|safe|GitHub CLI (cli/cli prebuilt) ~40 MB"
    "act|act-bootstrap|act|act-bootstrap|safe|Run GitHub Actions locally (nektos/act) ~20 MB"
    "actionlint|actionlint-bootstrap|actionlint|actionlint-bootstrap|safe|GitHub Actions workflow linter ~5 MB"
    "graphviz|graphviz-bootstrap|graphviz|graphviz-bootstrap|safe|graphviz dot/neato/fdp via apt-get download ~5 MB"
    "inotify-tools|inotify-tools-bootstrap|inotify-tools|inotify-tools-bootstrap|safe|inotifywait/inotifywatch (Phoenix dev live-reload) <1 MB"
    "tailscale|tailscale-bootstrap|tailscale|tailscale-bootstrap|safe|Tailscale VPN client (userspace SOCKS5) ~60 MB"
    "fzf|fzf-bootstrap|fzf|fzf-bootstrap|safe|fzf fuzzy finder (junegunn/fzf) ~2 MB"
    "wx|wx-bootstrap|wx|wx-bootstrap|mise-bootstrap|safe|wxWidgets 3.2 for Erlang's :observer ~80 MB"
    "mise-data|mise-bootstrap|mise-data|mise-bootstrap|safe|mise runtimes (reads ~/.config/mise/config.toml) varies"
    "aider|aider-bootstrap|uv-tools/aider-chat|aider-bootstrap|safe|aider terminal pair-programmer via uv tool ~500 MB"
    "opencode|opencode-bootstrap|mise-data/installs/github-anomalyco-opencode|opencode-bootstrap|mise-bootstrap|safe|OpenCode AI coding agent (restored transitively by mise-bootstrap)"
    "cuda|cuda-bootstrap|cuda|cuda-bootstrap|safe|CUDA libraries (extracts .debs without sudo) ~3.5 GB"
    "ollama|ollama-bootstrap|ollama|ollama-bootstrap|safe|Ollama daemon + model pulls from ~/Apps/etc/ollama-models.txt"
    "jetbrains/idea-ultimate|jb-bootstrap IIU|jetbrains/idea-ultimate|jb-bootstrap[[:space:]]+IIU([[:space:]@]|\$)|safe|IntelliJ IDEA Ultimate ~4 GB"
    "jetbrains/idea-community|jb-bootstrap IIC|jetbrains/idea-community|jb-bootstrap[[:space:]]+IIC([[:space:]@]|\$)|safe|IntelliJ IDEA Community ~1 GB"
    "jetbrains/webstorm|jb-bootstrap WS|jetbrains/webstorm|jb-bootstrap[[:space:]]+WS([[:space:]@]|\$)|safe|WebStorm ~3 GB"
    "jetbrains/phpstorm|jb-bootstrap PS|jetbrains/phpstorm|jb-bootstrap[[:space:]]+PS([[:space:]@]|\$)|safe|PhpStorm ~3 GB"
    "jetbrains/pycharm-pro|jb-bootstrap PCP|jetbrains/pycharm-pro|jb-bootstrap[[:space:]]+PCP([[:space:]@]|\$)|safe|PyCharm Professional ~3 GB"
    "jetbrains/pycharm-ce|jb-bootstrap PCC|jetbrains/pycharm-ce|jb-bootstrap[[:space:]]+PCC([[:space:]@]|\$)|safe|PyCharm Community ~1 GB"
    "jetbrains/clion|jb-bootstrap CL|jetbrains/clion|jb-bootstrap[[:space:]]+CL([[:space:]@]|\$)|safe|CLion ~2.5 GB"
    "jetbrains/goland|jb-bootstrap GO|jetbrains/goland|jb-bootstrap[[:space:]]+GO([[:space:]@]|\$)|safe|GoLand ~2.5 GB"
    "jetbrains/rubymine|jb-bootstrap RM|jetbrains/rubymine|jb-bootstrap[[:space:]]+RM([[:space:]@]|\$)|safe|RubyMine ~3 GB"
    "jetbrains/rider|jb-bootstrap RD|jetbrains/rider|jb-bootstrap[[:space:]]+RD([[:space:]@]|\$)|safe|Rider ~3 GB"
    "jetbrains/datagrip|jb-bootstrap DG|jetbrains/datagrip|jb-bootstrap[[:space:]]+DG([[:space:]@]|\$)|safe|DataGrip ~2 GB"
    "jetbrains/aqua|jb-bootstrap AC|jetbrains/aqua|jb-bootstrap[[:space:]]+AC([[:space:]@]|\$)|safe|Aqua ~3 GB"
    "jetbrains/rustrover|jb-bootstrap RR|jetbrains/rustrover|jb-bootstrap[[:space:]]+RR([[:space:]@]|\$)|safe|RustRover ~3 GB"
)

parse_component_row() {
    local needle="$1" row rest
    for row in "${COMPONENTS[@]}"; do
        C_NAME=${row%%|*}
        [[ "$C_NAME" != "$needle" ]] && continue
        rest=${row#*|}
        C_CMD=${rest%%|*};     rest=${rest#*|}
        C_PATH=${rest%%|*};    rest=${rest#*|}
        C_DESC=${rest##*|}
        rest=${rest%|*}
        C_CLASS=${rest##*|}
        C_PATTERN=${rest%|*}
        return 0
    done
    return 1
}
