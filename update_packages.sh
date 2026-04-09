#!/usr/bin/env bash

set -euo pipefail

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

cleanup_npm_global_temp_dirs() {
  local npm_root="$1"
  local found=0

  while IFS= read -r dir; do
    found=1
    log "Suppression du dossier temporaire npm global: $dir"
    rm -rf "$dir"
  done < <(find "$npm_root" -maxdepth 1 -mindepth 1 -type d \( -name '.*-*' -o -name '.npm-*' \) 2>/dev/null || true)

  if [[ "$found" -eq 0 ]]; then
    log "Aucun dossier temporaire npm global a nettoyer"
  fi
}

update_npm_global_packages() {
  local npm_root
  local packages=()
  local path
  local rel

  npm_root="$(npm root -g)"
  cleanup_npm_global_temp_dirs "$npm_root"

  while IFS= read -r path; do
    [[ "$path" == "$(dirname "$npm_root")" ]] && continue

    rel="${path#"$npm_root"/}"
    [[ -z "$rel" ]] && continue
    packages+=("$rel")
  done < <(npm ls -g --depth=0 --parseable 2>/dev/null || true)

  if [[ "${#packages[@]}" -eq 0 ]]; then
    log "Aucun paquet npm global detecte"
    return 0
  fi

  for package in "${packages[@]}"; do
    log "Mise a jour de $package"
    npm install -g "${package}@latest"
  done
}

run_if_available() {
  local cmd="$1"
  local label="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    log "$label"
    return 0
  fi

  log "$cmd n'est pas installe, etape ignoree."
  return 1
}

if run_if_available brew "Mise a jour de Homebrew"; then
  brew update

  log "Mise a niveau des formules Homebrew"
  brew upgrade

  log "Nettoyage Homebrew"
  brew cleanup
fi

if run_if_available npm "Mise a jour des paquets npm globaux"; then
  update_npm_global_packages
fi

log "Termine."
