#!/usr/bin/env bash

set -euo pipefail

APP_PATH="/tmp/NpmBrewMenuBarDerivedData/Build/Products/Debug/NpmBrewMenuBar.app"

if [[ ! -d "$APP_PATH" ]]; then
  printf 'App introuvable: %s\n' "$APP_PATH" >&2
  printf 'Lance d abord ./build_and_run_swift_app.sh pour la builder.\n' >&2
  exit 1
fi

open "$APP_PATH"
