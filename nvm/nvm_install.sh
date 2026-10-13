#!/usr/bin/env bash

set -eo pipefail

usage() {
    cat <<'EOF'
Usage:
  nvm_install.sh

Install or update to the latest stable nvm release, install the latest stable
version of Node.js, and set stable as the default Node.js version.
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

if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' 'curl is required to install nvm.' >&2
    exit 1
fi

readonly NVM_LATEST_URL="https://github.com/nvm-sh/nvm/releases/latest"
release_url="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "$NVM_LATEST_URL")"
nvm_version="${release_url##*/}"

if [[ ! "$nvm_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Could not determine the latest stable nvm version from: %s\n' "$release_url" >&2
    exit 1
fi

installer_url="https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh"
installer_path="$(mktemp)"

cleanup() {
    rm -f "$installer_path"
}
trap cleanup EXIT

printf 'Installing nvm %s...\n' "$nvm_version"
curl -fsSL --retry 3 "$installer_url" -o "$installer_path"
bash "$installer_path"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    printf 'nvm was not installed at the expected path: %s\n' "$NVM_DIR" >&2
    exit 1
fi

# nvm is implemented as shell functions and must be loaded in this process.
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"

printf 'Installed nvm version: %s\n' "$(nvm --version)"
printf '%s\n' 'Installing the latest stable version of Node.js...'
nvm install stable
nvm alias default stable

printf '\nDefault Node.js version: %s\n' "$(node --version)"
printf '%s\n' 'Start a new terminal to use nvm, or load it in the current shell with:'
printf '  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"\n'
printf '  source "$NVM_DIR/nvm.sh"\n'
