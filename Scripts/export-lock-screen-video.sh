#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PrismDrift.xcodeproj"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build}"
OUTPUT_PATH="$ROOT_DIR/Generated/PrismDrift/prism-drift-lockscreen.mov"
WIDTH=3840
HEIGHT=2160
FPS=240
DURATION=10
LOOP_DURATION="$DURATION"

usage() {
  cat <<'EOF'
Usage: ./Scripts/export-lock-screen-video.sh [options]

Export a loopable HEVC .mov directly from the Prism Drift renderer.

Options:
  --width <pixels>          Output width (default: 3840)
  --height <pixels>         Output height (default: 2160)
  --fps <frames>            Output frame rate (default: 240)
  --duration <seconds>      Video duration (default: 10)
  --loop-duration <seconds> Loop period in the shader (default: same as duration)
  --output <path>           Destination .mov path
  --help                    Show this help message
EOF
}

build_preview_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme PrismDrift \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build \
    >/dev/null
}

preview_app_binary() {
  echo "$DERIVED_DATA_DIR/Build/Products/Release/PrismDrift.app/Contents/MacOS/PrismDrift"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --width)
      WIDTH="$2"
      shift 2
      ;;
    --height)
      HEIGHT="$2"
      shift 2
      ;;
    --fps)
      FPS="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --loop-duration)
      LOOP_DURATION="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$OUTPUT_PATH")"

build_preview_app

APP_BINARY="$(preview_app_binary)"

env \
  "PRISMDRIFT_EXPORT_VIDEO_PATH=$OUTPUT_PATH" \
  "PRISMDRIFT_EXPORT_WIDTH=$WIDTH" \
  "PRISMDRIFT_EXPORT_HEIGHT=$HEIGHT" \
  "PRISMDRIFT_EXPORT_FPS=$FPS" \
  "PRISMDRIFT_EXPORT_DURATION=$DURATION" \
  "PRISMDRIFT_EXPORT_LOOP_DURATION=$LOOP_DURATION" \
  "$APP_BINARY"

echo "Lock-screen video exported to $OUTPUT_PATH"
