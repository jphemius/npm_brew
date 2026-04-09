#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/swift/NpmBrewMenuBar.xcodeproj"
SCHEME_NAME="NpmBrewMenuBar"
DERIVED_DATA_PATH="/tmp/NpmBrewMenuBarDerivedData"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/Debug"
APP_PATH="$BUILD_DIR/$SCHEME_NAME.app"

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'xcodebuild est introuvable. Installe Xcode ou les Command Line Tools.\n' >&2
  exit 1
fi

mkdir -p "$DERIVED_DATA_PATH"

log "Build de l'application Swift"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  printf 'Application introuvable apres le build: %s\n' "$APP_PATH" >&2
  exit 1
fi

log "Lancement de l'application"
open "$APP_PATH"
