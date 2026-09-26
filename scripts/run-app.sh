#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh debug
open .build/Phosphorus.app --args "$@"
