#!/usr/bin/env bash

set -euo pipefail

readonly OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
readonly ZSHRC_FILE="$HOME/.zshrc"
# Minimum versions recommended by the Oh My Zsh README.
readonly MIN_ZSH_VERSION="5.0.8"
readonly MIN_GIT_VERSION="2.4.11"
readonly ZSHRC_BLOCK_BEGIN="# >>> scripts zsh configuration (zsh_install.sh) >>>"
readonly ZSHRC_BLOCK_END="# <<< scripts zsh configuration <<<"

log() {
    printf '[zsh-setup] %s\n' "$*"
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

# Print the first dotted version number in `<command> --version`.
command_version() {
    local output

    output="$("$1" --version 2>/dev/null)" || return 1
    [[ "$output" =~ [0-9]+(\.[0-9]+)+ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[0]}"
}

# Succeed when dotted version $1 is at least $2.
version_at_least() {
    local have=()
    local need=()
    local i

    IFS=. read -r -a have <<<"$1"
    IFS=. read -r -a need <<<"$2"
    for (( i = 0; i < ${#need[@]}; i++ )); do
        if (( 10#${have[i]:-0} != 10#${need[i]} )); then
            (( 10#${have[i]:-0} > 10#${need[i]} ))
            return
        fi
    done
    return 0
}

meets_minimum_version() {
    local version

    version="$(command_version "$1")" || return 1
    version_at_least "$version" "$2"
}

require_minimum_version() {
    local version

    if meets_minimum_version "$1" "$2"; then
        return
    fi

    version="$(command_version "$1" || true)"
    printf '%s %s or newer is required, but found: %s\n' "$1" "$2" "${version:-not installed}" >&2
    exit 1
}

install_packages() {
    local outdated_packages=()

    meets_minimum_version zsh "$MIN_ZSH_VERSION" || outdated_packages+=(zsh)
    meets_minimum_version git "$MIN_GIT_VERSION" || outdated_packages+=(git)

    if (( ${#outdated_packages[@]} == 0 )); then
        log "Zsh $(command_version zsh) and Git $(command_version git) meet the minimum versions; skipping package installation"
        return
    fi

    # Installing an already installed package upgrades it to the newest version the
    # package manager offers. The versions are checked again afterwards.
    if command -v apt-get >/dev/null 2>&1; then
        log "Installing or upgrading with apt: ${outdated_packages[*]}"
        run_as_root apt-get update
        run_as_root apt-get install -y "${outdated_packages[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        log "Installing or upgrading with dnf: ${outdated_packages[*]}"
        run_as_root dnf install -y "${outdated_packages[@]}"
    elif command -v yum >/dev/null 2>&1; then
        log "Installing or upgrading with yum: ${outdated_packages[*]}"
        run_as_root yum install -y "${outdated_packages[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        log "Installing or upgrading with pacman: ${outdated_packages[*]}"
        run_as_root pacman -Sy --needed --noconfirm "${outdated_packages[@]}"
    elif command -v brew >/dev/null 2>&1; then
        log "Installing or upgrading with Homebrew: ${outdated_packages[*]}"
        brew install "${outdated_packages[@]}"
    else
        printf 'No supported package manager found. Install or upgrade these commands first: %s\n' \
            "${outdated_packages[*]}" >&2
        exit 1
    fi

    require_minimum_version zsh "$MIN_ZSH_VERSION"
    require_minimum_version git "$MIN_GIT_VERSION"
}

clone_or_update() {
    local repository="$1"
    local destination="$2"

    if [[ -d "$destination/.git" ]]; then
        log "Updating ${destination}"
        git -C "$destination" pull --ff-only
    elif [[ -e "$destination" ]]; then
        printf '%s exists but is not a Git repository. Move it aside and rerun this script.\n' "$destination" >&2
        exit 1
    else
        log "Installing ${destination}"
        git clone --depth=1 "$repository" "$destination"
    fi
}

# The configuration lives in a marked block inside ~/.zshrc, like `conda init` does.
# Only the block is ever rewritten, so personal settings outside it are kept. Keeping
# it inside ~/.zshrc rather than in a separately sourced file also lets installers
# that check ~/.zshrc for their own lines (nvm looks for "/nvm.sh") see them there
# and not append duplicates.
write_zshrc() {
    local block_file
    local generated_file
    local backup_file
    local begin_lines=""
    local end_lines=""

    block_file="$(mktemp)"
    generated_file="$(mktemp)"
    trap 'rm -f "${block_file:-}" "${generated_file:-}"' RETURN

    {
        printf '%s\n' "$ZSHRC_BLOCK_BEGIN"
        cat <<'EOF'
# Managed by https://github.com/whr819987540/scripts/blob/main/zsh_install.sh
# Rerunning the script rewrites this block. Put personal settings below it.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

# Keep startup predictable; update the installation by rerunning zsh_install.sh.
zstyle ':omz:update' mode disabled
DISABLE_AUTO_UPDATE=true

plugins=(
    git
    extract
    conda-zsh-completion
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# Initialize Conda like `conda init` does, so conda's own auto_activate_base setting
# decides whether base is activated. conda is not on PATH in a fresh shell, so also
# look in the usual install locations.
for __conda_bin in "$(command -v conda 2>/dev/null)" \
    "$HOME/miniconda3/bin/conda" "$HOME/anaconda3/bin/conda"; do
    [[ -x "$__conda_bin" ]] && break
done
if [[ -x "$__conda_bin" ]]; then
    if __conda_setup="$("$__conda_bin" shell.zsh hook 2>/dev/null)"; then
        eval "$__conda_setup"
    elif [[ -f "${__conda_bin:h:h}/etc/profile.d/conda.sh" ]]; then
        source "${__conda_bin:h:h}/etc/profile.d/conda.sh"
    fi
fi
unset __conda_bin __conda_setup

# Load personal environment variables without making them part of this file.
# They come after Conda so they can override what Conda sets.
[[ -f "$HOME/.env_var" ]] && source "$HOME/.env_var"

# Homebrew uses different standard prefixes on Linux, Intel macOS and Apple Silicon.
if command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Homebrew prepends its own bin directory. Keep user-installed tools such as
# ~/.local/bin/tmux (tmux_install.sh) ahead of it, and drop duplicate entries.
typeset -U path PATH
path=("$HOME/.local/bin" $path)

[[ -f "$HOME/.config/clash-for-linux/profile.sh" ]] && \
    source "$HOME/.config/clash-for-linux/profile.sh"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Persist history at shell exit while keeping concurrent terminals isolated.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
unsetopt SHARE_HISTORY
unsetopt INC_APPEND_HISTORY
unsetopt INC_APPEND_HISTORY_TIME
EOF
        printf '%s\n' "$ZSHRC_BLOCK_END"
    } >"$block_file"

    if [[ -f "$ZSHRC_FILE" ]]; then
        begin_lines="$(grep -nxF "$ZSHRC_BLOCK_BEGIN" "$ZSHRC_FILE" | cut -d: -f1 || true)"
        end_lines="$(grep -nxF "$ZSHRC_BLOCK_END" "$ZSHRC_FILE" | cut -d: -f1 || true)"
    fi

    if [[ -n "$begin_lines" || -n "$end_lines" ]]; then
        # Accept exactly one begin marker followed by exactly one end marker.
        if [[ -z "$begin_lines" || -z "$end_lines" || "$begin_lines$end_lines" == *$'\n'* ]] ||
            (( begin_lines > end_lines )); then
            printf '%s has unmatched or repeated managed-block markers. Fix them by hand and rerun.\n' \
                "$ZSHRC_FILE" >&2
            exit 1
        fi
        awk -v begin="$begin_lines" -v end="$end_lines" -v block="$block_file" '
            NR == begin { while ((getline line < block) > 0) print line }
            NR < begin || NR > end { print }
        ' "$ZSHRC_FILE" >"$generated_file"
    elif [[ ! -s "$ZSHRC_FILE" ]]; then
        cp "$block_file" "$generated_file"
    elif grep -qE '^[^#]*oh-my-zsh\.sh' "$ZSHRC_FILE"; then
        # Adding the block would load Oh My Zsh, Conda and nvm a second time.
        log "${ZSHRC_FILE} already loads Oh My Zsh outside a managed block; leaving it unchanged"
        log "To switch to the managed configuration: mv ~/.zshrc ~/.zshrc.old, rerun this script,"
        log "then copy any personal settings from ~/.zshrc.old below the managed block"
        return
    else
        # Put the block first so that the existing settings after it can override it.
        { cat "$block_file"; printf '\n'; cat "$ZSHRC_FILE"; } >"$generated_file"
    fi

    if [[ -f "$ZSHRC_FILE" ]] && cmp -s "$generated_file" "$ZSHRC_FILE"; then
        log "${ZSHRC_FILE} is already up to date"
        return
    fi

    if [[ -s "$ZSHRC_FILE" ]]; then
        backup_file="${ZSHRC_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp -p "$ZSHRC_FILE" "$backup_file"
        log "Backed up the existing configuration to ${backup_file}"
    fi

    if [[ -e "$ZSHRC_FILE" ]]; then
        # Write through the existing file so a symlinked ~/.zshrc keeps its link.
        cat "$generated_file" >"$ZSHRC_FILE"
    else
        install -m 0644 "$generated_file" "$ZSHRC_FILE"
    fi
    log "Updated the managed block in ${ZSHRC_FILE}"
}

set_default_shell() {
    local zsh_path

    zsh_path="$(command -v zsh)"
    # -ef also matches /bin/zsh and /usr/bin/zsh on systems where /bin links to /usr/bin.
    if [[ "${SHELL:-}" -ef "$zsh_path" ]]; then
        return
    fi

    if chsh -s "$zsh_path"; then
        log "Set the default shell to ${zsh_path}"
    else
        printf 'Could not change the default shell. Run: chsh -s %s\n' "$zsh_path" >&2
    fi
}

install_packages
clone_or_update "https://github.com/ohmyzsh/ohmyzsh.git" "$OH_MY_ZSH_DIR"
clone_or_update "https://github.com/conda-incubator/conda-zsh-completion.git" \
    "$OH_MY_ZSH_DIR/custom/plugins/conda-zsh-completion"
clone_or_update "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$OH_MY_ZSH_DIR/custom/plugins/zsh-autosuggestions"
clone_or_update "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
    "$OH_MY_ZSH_DIR/custom/plugins/zsh-syntax-highlighting"
write_zshrc
set_default_shell

log "Installation complete. Start a new terminal or run: exec zsh"
