#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_INPUT="$ROOT_DIR/Generated/PrismDrift/prism-drift-lockscreen.mov"
FALLBACK_INPUT="$ROOT_DIR/Docs/preview.gif"
ASSET_DIR="/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS"
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/install-lock-screen-aerial.sh [--input <path>] [--duration <seconds>]
  sudo ./Scripts/install-lock-screen-aerial.sh --install-from <prepared.mov> [--target <file.mov>]

Mode 1, without sudo:
  - transcodes the input into an aerial-compatible HEVC .mov staged under /tmp
  - prints the exact sudo command required for installation

Mode 2, with sudo and --install-from:
  - backs up the original idleassetsd .mov
  - replaces it with the prepared Prism Drift video
  - restarts wallpaper-related processes so macOS reloads the asset

Options:
  --input <path>         Source .gif/.mov/.mp4 to loop and transcode
  --duration <seconds>   Output video duration in seconds (default: 30)
  --install-from <path>  Prepared .mov created by this script in non-root mode
  --target <file.mov>    Explicit target asset inside 4KSDR240FPS
  --help                 Show this help message

Notes:
  - This is an unsupported macOS workaround, not a public Apple API.
  - The preferred source is Generated/PrismDrift/prism-drift-lockscreen.mov.
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

resolve_default_target() {
  find "$ASSET_DIR" -maxdepth 1 -type f -name '*.mov' | sort | head -n 1
}

restart_wallpaper_processes() {
  pkill -f WallpaperAerialsExtension 2>/dev/null || true
  pkill -f WallpaperAgent 2>/dev/null || true
  pkill -f idleassetsd 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true
  killall "System Settings" 2>/dev/null || true
}

prepare_video() {
  local input_path="$1"
  local duration_seconds="$2"
  local output_path="$3"

  require_command ffmpeg

  if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_videotoolbox"; then
    ffmpeg \
      -hide_banner \
      -loglevel error \
      -y \
      -stream_loop -1 \
      -i "$input_path" \
      -t "$duration_seconds" \
      -vf "scale=3840:2160:force_original_aspect_ratio=increase,crop=3840:2160,fps=240,format=p010le" \
      -c:v hevc_videotoolbox \
      -pix_fmt p010le \
      -tag:v hvc1 \
      -movflags +faststart \
      "$output_path"
  else
    ffmpeg \
      -hide_banner \
      -loglevel error \
      -y \
      -stream_loop -1 \
      -i "$input_path" \
      -t "$duration_seconds" \
      -vf "scale=3840:2160:force_original_aspect_ratio=increase,crop=3840:2160,fps=240,format=yuv420p10le" \
      -c:v libx265 \
      -preset medium \
      -pix_fmt yuv420p10le \
      -tag:v hvc1 \
      -movflags +faststart \
      "$output_path"
  fi
}

install_video() {
  local prepared_path="$1"
  local target_path="$2"
  local backup_path="${target_path}.prismdrift-backup-${STAMP}"

  if [[ $EUID -ne 0 ]]; then
    echo "Installation mode requires sudo." >&2
    exit 1
  fi

  if [[ ! -f "$prepared_path" ]]; then
    echo "Prepared video not found: $prepared_path" >&2
    exit 1
  fi

  if [[ ! -f "$target_path" ]]; then
    echo "Target aerial asset not found: $target_path" >&2
    exit 1
  fi

  cp "$target_path" "$backup_path"
  cp "$prepared_path" "$target_path"
  chown root:wheel "$target_path"
  chmod 644 "$target_path"

  restart_wallpaper_processes

  echo "Installed Prism Drift lock-screen aerial to:"
  echo "  $target_path"
  echo
  echo "Backup saved to:"
  echo "  $backup_path"
  echo
  echo "Next step:"
  echo "  Open System Settings > Wallpaper and select the aerial tied to this asset."
}

INPUT_PATH=""
DURATION_SECONDS="30"
INSTALL_FROM=""
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT_PATH="$2"
      shift 2
      ;;
    --duration)
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --install-from)
      INSTALL_FROM="$2"
      shift 2
      ;;
    --target)
      TARGET_PATH="$2"
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

if [[ -n "$INSTALL_FROM" ]]; then
  TARGET_PATH="${TARGET_PATH:-$(resolve_default_target)}"
  install_video "$INSTALL_FROM" "$TARGET_PATH"
  exit 0
fi

if [[ -z "$INPUT_PATH" ]]; then
  INPUT_PATH="$DEFAULT_INPUT"
fi

if [[ ! -f "$INPUT_PATH" && -f "$FALLBACK_INPUT" ]]; then
  INPUT_PATH="$FALLBACK_INPUT"
fi

if [[ ! -f "$INPUT_PATH" ]]; then
  echo "Input file not found: $INPUT_PATH" >&2
  echo "Run ./Scripts/export-lock-screen-video.sh first or pass --input <path>." >&2
  exit 1
fi

TARGET_PATH="${TARGET_PATH:-$(resolve_default_target)}"

if [[ -z "$TARGET_PATH" ]]; then
  echo "No target aerial asset found in $ASSET_DIR" >&2
  exit 1
fi

STAGED_OUTPUT="/tmp/prism-drift-lockscreen-${STAMP}.mov"

prepare_video "$INPUT_PATH" "$DURATION_SECONDS" "$STAGED_OUTPUT"

echo "Prepared aerial video:"
echo "  $STAGED_OUTPUT"
echo
echo "Target system asset:"
echo "  $TARGET_PATH"
echo
echo "Run this command to install it:"
echo "  sudo \"$0\" --install-from \"$STAGED_OUTPUT\" --target \"$TARGET_PATH\""
