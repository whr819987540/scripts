#!/usr/bin/env bash

set -euo pipefail

readonly TMUX_VERSION="3.7b"
readonly TMUX_SHA256="87f2e99e3b685973f2ca002ffd6ed7e51a5744f7009daae5a15670b6d532db96"
readonly TMUX_DOWNLOAD_URL="${tmux_download_url:-https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz}"
readonly INSTALL_PREFIX="$HOME/.local"
readonly TMUX_BIN="$INSTALL_PREFIX/bin/tmux"
readonly TMUX_CONF_FILE="$HOME/.tmux.conf"
# The PATH that `ssh host command` starts with, before any shell startup file runs.
readonly SSH_COMMAND_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly PATH_BLOCK_BEGIN="# >>> ~/.local/bin for non-interactive shells (tmux_install.sh) >>>"
readonly PATH_BLOCK_END="# <<< ~/.local/bin for non-interactive shells <<<"
readonly LOCALE_BLOCK_BEGIN="# >>> UTF-8 locale for tmux (tmux_install.sh) >>>"
readonly LOCALE_BLOCK_END="# <<< UTF-8 locale for tmux <<<"

usage() {
    cat <<EOF
Usage:
  tmux_install.sh

Build tmux ${TMUX_VERSION} from source into ~/.local/bin, make non-interactive
bash and zsh find it there, fall back to a UTF-8 locale in shells that start
without one (otherwise tmux shows non-ASCII text as "_"), and write ~/.tmux.conf.

Environment:
  tmux_download_url  Source tarball URL (defaults to the GitHub release);
                     the SHA-256 checksum is verified either way
EOF
}

if (( $# > 1 )); then
    printf '%s\n\n' 'Too many arguments.' >&2
    usage >&2
    exit 2
fi

case "${1:-}" in
    "") ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

log() {
    printf '[tmux-setup] %s\n' "$*"
}

run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        printf 'Cannot install missing dependencies without root privileges or sudo access.\n' >&2
        exit 1
    fi
}

has_build_dependencies() {
    { command -v cc || command -v gcc; } >/dev/null 2>&1 &&
        command -v make >/dev/null 2>&1 &&
        command -v pkg-config >/dev/null 2>&1 &&
        { pkg-config --exists libevent_core || pkg-config --exists libevent; } &&
        { pkg-config --exists ncursesw || pkg-config --exists ncurses || pkg-config --exists tinfo; }
}

has_yacc() {
    command -v bison >/dev/null 2>&1 ||
        command -v byacc >/dev/null 2>&1 ||
        command -v yacc >/dev/null 2>&1
}

install_build_dependencies() {
    if has_build_dependencies; then
        log "Build dependencies are already installed"
        return
    fi

    if command -v apt-get >/dev/null 2>&1; then
        log "Installing build dependencies with apt"
        run_as_root apt-get update
        run_as_root apt-get install -y gcc make pkg-config libevent-dev libncurses-dev
    elif command -v dnf >/dev/null 2>&1; then
        log "Installing build dependencies with dnf"
        run_as_root dnf install -y gcc make pkgconfig libevent-devel ncurses-devel
    elif command -v yum >/dev/null 2>&1; then
        log "Installing build dependencies with yum"
        run_as_root yum install -y gcc make pkgconfig libevent-devel ncurses-devel
    else
        printf '%s\n' 'No supported package manager found. Install a C compiler, make, pkg-config,' \
            'and the libevent and ncurses development files first.' >&2
        exit 1
    fi
}

build_and_install() {
    local archive="$work_dir/tmux-${TMUX_VERSION}.tar.gz"
    local source_dir="$work_dir/tmux-${TMUX_VERSION}"
    local configure_args=(--prefix="$INSTALL_PREFIX")
    local current_version=""
    local installed_version

    if [[ -x "$TMUX_BIN" ]]; then
        current_version="$("$TMUX_BIN" -V 2>/dev/null || true)"
        if [[ "$current_version" == "tmux ${TMUX_VERSION}" ]]; then
            log "${TMUX_BIN} is already tmux ${TMUX_VERSION}; skipping the build"
            return
        fi
        log "Replacing ${current_version:-the existing binary} at ${TMUX_BIN}"
    fi

    if ! command -v curl >/dev/null 2>&1; then
        printf '%s\n' 'curl is required to download tmux.' >&2
        exit 1
    fi
    install_build_dependencies

    log "Downloading ${TMUX_DOWNLOAD_URL}"
    curl -fsSL --retry 3 "$TMUX_DOWNLOAD_URL" -o "$archive"
    if ! printf '%s  %s\n' "$TMUX_SHA256" "$archive" | sha256sum -c --status; then
        printf 'SHA-256 mismatch for %s; expected %s\n' "$TMUX_DOWNLOAD_URL" "$TMUX_SHA256" >&2
        exit 1
    fi
    tar -xzf "$archive" -C "$work_dir"

    # The release tarball ships the generated cmd-parse.c, so configure only checks
    # that some yacc exists. Without one, YACC=false passes that check, and any
    # unexpected attempt to regenerate the parser fails instead of going unnoticed.
    if ! has_yacc; then
        configure_args+=(YACC=false)
    fi

    log "Building tmux ${TMUX_VERSION}"
    (
        cd "$source_dir"
        ./configure "${configure_args[@]}"
        make -j"$(nproc 2>/dev/null || echo 2)"
        make install
    )

    installed_version="$("$TMUX_BIN" -V)"
    if [[ "$installed_version" != "tmux ${TMUX_VERSION}" ]]; then
        printf '%s reports %s instead of tmux %s\n' "$TMUX_BIN" "$installed_version" "$TMUX_VERSION" >&2
        exit 1
    fi
    log "Installed ${installed_version} to ${TMUX_BIN}"
}

path_block() {
    printf '%s\n' "$PATH_BLOCK_BEGIN"
    cat <<'EOF'
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac
EOF
    printf '%s\n' "$PATH_BLOCK_END"
}

# tmux replaces non-ASCII text with "_" unless the first of LC_ALL, LC_CTYPE and LANG
# that is set names a UTF-8 locale. Containers often set none of them, so fall back to
# an installed UTF-8 locale whenever the shell starts without one.
locale_block() {
    printf '%s\n' "$LOCALE_BLOCK_BEGIN"
    cat <<EOF
case "\${LC_ALL:-\${LC_CTYPE:-\${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) export LANG=$1 ;;
esac
EOF
    printf '%s\n' "$LOCALE_BLOCK_END"
}

is_utf8_locale() {
    [[ "$1" =~ [Uu][Tt][Ff]-?8 ]]
}

# Print the UTF-8 locale to fall back on: en_US.UTF-8 when installed (as on the HUST
# machines), otherwise C.UTF-8, otherwise any installed UTF-8 locale.
pick_utf8_locale() {
    local locales
    local candidate

    locales="$(locale -a 2>/dev/null || true)"
    for candidate in en_US C; do
        if grep -qix "${candidate}\.utf-\?8" <<<"$locales"; then
            printf '%s.UTF-8\n' "$candidate"
            return
        fi
    done
    grep -i -m 1 'utf-\?8$' <<<"$locales" || true
}

# Add a marked block to an rc file once, at the top or at the bottom. The first argument
# after the description is the command that prints the block.
add_rc_block() {
    local rc_file="$1"
    local position="$2"
    local begin_marker="$3"
    local description="$4"
    local generated_file
    local backup_file

    shift 4
    if [[ -f "$rc_file" ]] && grep -qF "$begin_marker" "$rc_file"; then
        log "${rc_file} already has the ${description} block"
        return
    fi

    generated_file="$work_dir/$(basename "$rc_file")"
    if [[ "$position" == top ]]; then
        "$@" >"$generated_file"
        if [[ -f "$rc_file" ]]; then
            printf '\n' >>"$generated_file"
            cat "$rc_file" >>"$generated_file"
        fi
    else
        : >"$generated_file"
        if [[ -f "$rc_file" ]]; then
            cat "$rc_file" >>"$generated_file"
            printf '\n' >>"$generated_file"
        fi
        "$@" >>"$generated_file"
    fi

    if [[ -e "$rc_file" ]]; then
        backup_file="${rc_file}.backup.$(date +%Y%m%d%H%M%S)"
        cp -p "$rc_file" "$backup_file"
        log "Backed up ${rc_file} to ${backup_file}"
    fi

    # Write through the existing file so a symlinked dotfile keeps its link.
    cat "$generated_file" >"$rc_file"
    log "Added the ${description} block to ${rc_file}"
}

# Ubuntu's ~/.bashrc returns early in non-interactive shells, so its blocks must come
# before that check; bash reads ~/.bashrc when it runs an SSH command. zsh reads
# ~/.zshenv in every shell, including non-interactive ones.
add_shell_block() {
    add_rc_block "$HOME/.bashrc" top "$@"
    add_rc_block "$HOME/.zshenv" bottom "$@"
}

setup_utf8_locale() {
    local current="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    local utf8_locale

    utf8_locale="$(pick_utf8_locale)"
    if [[ -z "$utf8_locale" ]]; then
        log "Warning: no UTF-8 locale is installed, so tmux will show non-ASCII text as \"_\"."
        log "Generate one first, for example: sudo locale-gen en_US.UTF-8"
        return
    fi

    if is_utf8_locale "$current"; then
        log "This shell uses the UTF-8 locale ${current}; other shells fall back to ${utf8_locale} without one"
    else
        log "This shell's locale (${current:-unset}) is not UTF-8, so tmux would show non-ASCII text as \"_\"; falling back to ${utf8_locale}"
    fi
    add_shell_block "$LOCALE_BLOCK_BEGIN" "UTF-8 locale" locale_block "$utf8_locale"
}

write_tmux_conf() {
    local generated_file="$work_dir/tmux.conf"
    local backup_file

    cat >"$generated_file" <<'EOF'
# Generated by https://github.com/whr819987540/scripts/blob/main/tmux/tmux_install.sh

# Line limit of tmux buffer
set-option -g history-limit 1000000

# Support scroll bar
set-option -g mouse on
set-option -g pane-scrollbars on
set-option -g pane-scrollbars-position right
set -g pane-scrollbars-style "fg=colour245,bg=colour236,width=1,pad=0"

# Keep copy-mode open after mouse selection so the view does not jump to bottom.
# copy-selection-no-clear also copies on tmux 3.0a; copy-pipe-no-clear without a command does not.
bind-key -T copy-mode MouseDown1Pane select-pane \; send-keys -X clear-selection
bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-selection-no-clear
bind-key -T copy-mode-vi MouseDown1Pane select-pane \; send-keys -X clear-selection
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-no-clear
EOF

    if [[ -f "$TMUX_CONF_FILE" ]] && cmp -s "$generated_file" "$TMUX_CONF_FILE"; then
        log "${TMUX_CONF_FILE} is already up to date"
        return
    fi

    if [[ -e "$TMUX_CONF_FILE" ]]; then
        backup_file="${TMUX_CONF_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp -p "$TMUX_CONF_FILE" "$backup_file"
        log "Backed up the existing configuration to ${backup_file}"
    fi

    install -m 0644 "$generated_file" "$TMUX_CONF_FILE"
    log "Wrote ${TMUX_CONF_FILE}"
}

verify_non_interactive_shells() {
    local shell_name
    local shell_path
    local result
    local tmux_result
    local shell_locale
    local failed=0

    for shell_name in bash zsh; do
        shell_path="$(command -v "$shell_name" || true)"
        [[ -n "$shell_path" ]] || continue

        # Reproduce `ssh host command`: start from the bare PATH without locale variables,
        # and set SSH_CLIENT so that bash reads ~/.bashrc the way it does for SSH commands.
        result="$(env -i HOME="$HOME" PATH="$SSH_COMMAND_PATH" SSH_CLIENT="127.0.0.1 0 0" \
            "$shell_path" -c 'command -v tmux && tmux -V; printf "locale=%s\n" "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"' \
            2>/dev/null || true)"
        shell_locale="${result##*locale=}"
        tmux_result="${result%locale=*}"
        tmux_result="${tmux_result%$'\n'}"
        tmux_result="${tmux_result//$'\n'/: }"
        if [[ "$tmux_result" == *"tmux ${TMUX_VERSION}" ]]; then
            log "Non-interactive ${shell_name} runs ${tmux_result} with locale ${shell_locale:-unset}"
        else
            printf 'Non-interactive %s does not run tmux %s (got: %s)\n' \
                "$shell_name" "$TMUX_VERSION" "${tmux_result:-no tmux}" >&2
            failed=1
        fi
        if ! is_utf8_locale "$shell_locale"; then
            log "Warning: non-interactive ${shell_name} has no UTF-8 locale; tmux will show non-ASCII text as \"_\""
        fi
    done

    if (( failed )); then
        exit 1
    fi
}

warn_about_earlier_tmux() {
    local candidate
    local version

    # This PATH comes from the calling shell, which is usually interactive.
    while IFS= read -r candidate; do
        if [[ "$candidate" -ef "$TMUX_BIN" ]]; then
            return
        fi
        version="$("$candidate" -V 2>/dev/null || true)"
        if [[ "$version" != "tmux ${TMUX_VERSION}" ]]; then
            log "Warning: ${candidate} (${version:-unknown version}) comes before ${TMUX_BIN} on the current PATH"
        fi
    done < <(type -aP tmux)

    log "${TMUX_BIN} is not on the current PATH yet; open a new shell to use it"
}

report_running_server() {
    local server_version

    # #{version} is expanded by the server, so this reports the running server's version.
    server_version="$("$TMUX_BIN" display-message -p '#{version}' 2>/dev/null || true)"
    if [[ -z "$server_version" ]]; then
        return
    fi

    if [[ "$server_version" == "$TMUX_VERSION" ]]; then
        log "Reload the running tmux server with: tmux source-file ~/.tmux.conf"
    else
        log "The running tmux server is ${server_version}; restart it (tmux kill-server) to use ${TMUX_VERSION}"
    fi
}

build_and_install
add_shell_block "$PATH_BLOCK_BEGIN" "~/.local/bin PATH" path_block
setup_utf8_locale
write_tmux_conf
verify_non_interactive_shells
warn_about_earlier_tmux
report_running_server

log "Installation complete"
