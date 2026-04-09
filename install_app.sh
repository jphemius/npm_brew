#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/swift/NpmBrewMenuBar.xcodeproj"
SCHEME_NAME="NpmBrewMenuBar"
DERIVED_DATA_PATH="/tmp/NpmBrewMenuBarDerivedData"
CONFIGURATION="Release"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$SCHEME_NAME.app"
DEST_DIR="$HOME/Applications"

if [[ "${1:-}" == "--system" ]]; then
  DEST_DIR="/Applications"
fi

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'xcodebuild est introuvable. Installe Xcode ou les Command Line Tools.\n' >&2
  exit 1
fi

mkdir -p "$DERIVED_DATA_PATH"

log "Build Release de l'application"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  printf 'Application introuvable apres le build: %s\n' "$APP_PATH" >&2
  exit 1
fi

log "Installation dans $DEST_DIR"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/$SCHEME_NAME.app"
cp -R "$APP_PATH" "$DEST_DIR/"

log "Installation terminee: $DEST_DIR/$SCHEME_NAME.app"
log "Ouvre l'application une fois, puis active 'Demarrage auto' dans l'interface."
