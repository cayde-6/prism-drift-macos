#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PrismDrift.xcodeproj"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build}"
INSTALLED_SAVER_PATH="$HOME/Library/Screen Savers/PrismDriftSaver.saver"

usage() {
  cat <<'EOF'
Usage: ./Scripts/install-saver.sh

Build and install the PrismDriftSaver bundle into ~/Library/Screen Savers,
then select it as the active screen saver.
EOF
}

build_screen_saver() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme PrismDriftSaver \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build \
    >/dev/null
}

screen_saver_bundle() {
  echo "$DERIVED_DATA_DIR/Build/Products/Release/PrismDriftSaver.saver"
}

restart_screen_saver_hosts() {
  pkill legacyScreenSaver 2>/dev/null || true
  pkill WallpaperAgent 2>/dev/null || true
  pkill ScreenSaverEngine 2>/dev/null || true
}

select_installed_saver() {
  defaults -currentHost write com.apple.screensaver moduleDict -dict \
    moduleName PrismDriftSaver \
    path "$INSTALLED_SAVER_PATH" \
    type -int 0

  killall cfprefsd 2>/dev/null || true
  killall "System Settings" 2>/dev/null || true
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SOURCE_BUNDLE="$(screen_saver_bundle)"
DEST_DIR="$HOME/Library/Screen Savers"
DEST_BUNDLE="$INSTALLED_SAVER_PATH"

build_screen_saver

mkdir -p "$DEST_DIR"

if [[ -e "$DEST_BUNDLE" ]]; then
  # Preserve the previous bundle so users can roll back without rebuilding.
  mv "$DEST_BUNDLE" "$DEST_BUNDLE.bak-$(date +%Y%m%d-%H%M%S)"
fi

ditto "$SOURCE_BUNDLE" "$DEST_BUNDLE"

restart_screen_saver_hosts
select_installed_saver

echo "Installed screen saver to $DEST_BUNDLE"
open -R "$DEST_BUNDLE"
