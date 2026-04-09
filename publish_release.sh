#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/swift/NpmBrewMenuBar.xcodeproj"
PBXPROJ_PATH="$ROOT_DIR/swift/NpmBrewMenuBar.xcodeproj/project.pbxproj"
SCHEME_NAME="NpmBrewMenuBar"
DERIVED_DATA_PATH="/tmp/NpmBrewMenuBarDerivedData"
CONFIGURATION="Release"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_DIR/$SCHEME_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
REPO_SLUG="jphemius/npm_brew"

usage() {
  cat <<'EOF'
Usage:
  ./publish_release.sh <version> [build_number]

Examples:
  ./publish_release.sh 1.1.0
  ./publish_release.sh 1.1.0 2

What it does:
  1. Updates MARKETING_VERSION in the Xcode project
  2. Optionally updates CURRENT_PROJECT_VERSION
  3. Builds the app in Release mode
  4. Creates dist/NpmBrewMenuBar-v<version>.zip
  5. Creates or updates the GitHub Release v<version>
  6. Uploads the zip asset used by in-app auto-update
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Commande introuvable: %s\n' "$1" >&2
    exit 1
  fi
}

set_build_setting() {
  local key="$1"
  local value="$2"

  perl -0pi -e "s/${key} = [^;]+;/${key} = ${value};/g" "$PBXPROJ_PATH"
}

if [[ "${1:-}" == "" ]]; then
  usage
  exit 1
fi

VERSION="$1"
BUILD_NUMBER="${2:-}"
TAG="v$VERSION"
ZIP_NAME="${SCHEME_NAME}-${TAG}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

require_cmd xcodebuild
require_cmd gh
require_cmd ditto

if ! gh auth status >/dev/null 2>&1; then
  printf 'gh n est pas authentifie. Lance: gh auth login -h github.com\n' >&2
  exit 1
fi

if [[ ! -f "$PBXPROJ_PATH" ]]; then
  printf 'Fichier projet introuvable: %s\n' "$PBXPROJ_PATH" >&2
  exit 1
fi

log "Mise a jour de la version a $VERSION"
set_build_setting "MARKETING_VERSION" "$VERSION"

if [[ -n "$BUILD_NUMBER" ]]; then
  log "Mise a jour du build a $BUILD_NUMBER"
  set_build_setting "CURRENT_PROJECT_VERSION" "$BUILD_NUMBER"
fi

mkdir -p "$DERIVED_DATA_PATH" "$DIST_DIR"

log "Build Release"
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

log "Creation de l'archive $ZIP_NAME"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  log "Release $TAG existante, upload de l'asset"
  gh release upload "$TAG" "$ZIP_PATH" --clobber --repo "$REPO_SLUG"
else
  log "Creation de la release $TAG"
  gh release create "$TAG" "$ZIP_PATH" \
    --repo "$REPO_SLUG" \
    --title "$TAG" \
    --notes "Release $TAG"
fi

log "Release publiee"
log "Page: https://github.com/$REPO_SLUG/releases/tag/$TAG"
