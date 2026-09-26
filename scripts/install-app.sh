#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
require_stopped() {
    if pgrep -x PhosphorusWriter >/dev/null; then
        echo 'Save your work and quit Phosphorus before installing.' >&2
        exit 1
    fi
}
require_stopped
destination=${1:-/Applications}
if [ ! -d "$destination" ] || [ ! -w "$destination" ]; then
    echo 'Choose a writable Applications folder, such as ~/Applications.' >&2
    exit 1
fi
./scripts/build-app.sh release
require_stopped
staging=$(mktemp -d "$destination/.phosphorus-install.XXXXXX")
cleanup() {
    if [ ! -e "$destination/Phosphorus.app" ] && [ -e "$staging/previous.app" ]; then
        mv "$staging/previous.app" "$destination/Phosphorus.app" || return
    fi
    rm -rf "$staging"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ditto .build/Phosphorus.app "$staging/Phosphorus.app"
if [ -e "$destination/Phosphorus.app" ]; then
    mv "$destination/Phosphorus.app" "$staging/previous.app"
fi
if ! mv "$staging/Phosphorus.app" "$destination/Phosphorus.app"; then
    if [ -e "$staging/previous.app" ]; then
        mv "$staging/previous.app" "$destination/Phosphorus.app"
    fi
    exit 1
fi
echo "Installed $destination/Phosphorus.app"
