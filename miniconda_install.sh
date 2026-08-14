#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  miniconda_install.sh [silent] [installer-path]

Install the latest Miniconda for the current operating system and architecture
to ~/miniconda3 without prompts. Reuse installer-path when it already contains
an installer. The optional "silent" argument is retained for compatibility.
EOF
}

if (( $# > 2 )); then
    printf '%s\n\n' 'Too many arguments.' >&2
    usage >&2
    exit 2
fi

installer_path=""

case "${1:-}" in
    "") ;;
    silent) installer_path="${2:-}" ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *) installer_path="$1" ;;
esac

if [[ "${1:-}" != "silent" && $# -eq 2 ]]; then
    printf 'Unknown argument: %s\n\n' "$2" >&2
    usage >&2
    exit 2
fi

system_name="$(uname -s)"
machine_arch="$(uname -m)"

case "$system_name" in
    Linux)
        installer_system="Linux"
        case "$machine_arch" in
            x86_64|amd64) installer_arch="x86_64" ;;
            aarch64|arm64) installer_arch="aarch64" ;;
            ppc64le) installer_arch="ppc64le" ;;
            s390x) installer_arch="s390x" ;;
            *)
                printf 'Unsupported Linux architecture: %s\n' "$machine_arch" >&2
                exit 1
                ;;
        esac
        ;;
    Darwin)
        installer_system="MacOSX"
        case "$machine_arch" in
            x86_64|amd64) installer_arch="x86_64" ;;
            arm64|aarch64) installer_arch="arm64" ;;
            *)
                printf 'Unsupported macOS architecture: %s\n' "$machine_arch" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        printf 'Unsupported operating system: %s\n' "$system_name" >&2
        exit 1
        ;;
esac

installer_name="Miniconda3-latest-${installer_system}-${installer_arch}.sh"
installer_url="https://repo.anaconda.com/miniconda/${installer_name}"
install_dir="${HOME}/miniconda3"
installer_path="${installer_path:-${HOME}/.cache/miniconda/${installer_name}}"
download_path="${installer_path}.part.$$"

cleanup() {
    rm -f "$download_path"
}
trap cleanup EXIT

if [[ -s "$installer_path" && -f "$installer_path" ]]; then
    printf 'Reusing Miniconda installer: %s\n' "$installer_path"
else
    if [[ -e "$installer_path" && ! -f "$installer_path" ]]; then
        printf 'Installer path is not a regular file: %s\n' "$installer_path" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$installer_path")"
    printf 'Downloading %s for %s/%s...\n' "$installer_name" "$system_name" "$machine_arch"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 "$installer_url" -o "$download_path"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 "$installer_url" -O "$download_path"
    else
        printf '%s\n' 'curl or wget is required to download Miniconda.' >&2
        exit 1
    fi
    mv -f "$download_path" "$installer_path"
    printf 'Saved Miniconda installer: %s\n' "$installer_path"
fi

# Batch mode accepts the installer license and supplies all installation choices.
bash "$installer_path" -b -u -p "$install_dir"

printf '\nMiniconda is installed at %s.\n' "$install_dir"
printf 'Run the following command to activate it:\n  source %s/bin/activate\n' "$install_dir"
