#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
OUT_DIR="/tmp/tinyseawar_ocean_review"
SIZE="960x540"
CAMERA="2048,1152"
GODOT_BIN="${GODOT_BIN:-godot}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --size)
      SIZE="$2"
      shift 2
      ;;
    --camera)
      CAMERA="$2"
      shift 2
      ;;
    --godot)
      GODOT_BIN="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

cd "$REPO_ROOT"

if [[ ! -f "project.godot" ]]; then
  echo "Run from the TinySeaWar repository root or pass --repo." >&2
  exit 2
fi

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 2
fi

if command -v magick >/dev/null 2>&1; then
  MAGICK_BIN="magick"
elif command -v convert >/dev/null 2>&1; then
  MAGICK_BIN="convert"
else
  echo "ImageMagick is required: install magick or convert." >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

WEATHERS=(clear cloudy overcast rain thunderstorm)
TIMES=(day dawn dusk night)
IMAGES=()

for weather in "${WEATHERS[@]}"; do
  for time_of_day in "${TIMES[@]}"; do
    palette="${weather}_${time_of_day}"
    output="${OUT_DIR}/${palette}.png"
    log="${OUT_DIR}/${palette}.log"
    "$GODOT_BIN" --path . --script scripts/tests/render_scene_qa.gd -- \
      --size="$SIZE" \
      --palette="$palette" \
      --output="$output" \
      --camera="$CAMERA" >"$log" 2>&1
    if [[ ! -f "$output" ]]; then
      echo "Expected preview was not created: $output" >&2
      cat "$log" >&2
      exit 1
    fi
    IMAGES+=("$output")
  done
done

CONTACT_SHEET="${OUT_DIR}/ocean_20_palette_contact_sheet.png"

if [[ "$MAGICK_BIN" == "magick" ]]; then
  "$MAGICK_BIN" montage \
    -label '%t' \
    "${IMAGES[@]}" \
    -tile 4x5 \
    -geometry 480x270+12+42 \
    -background '#10202d' \
    -fill '#d8eef7' \
    -pointsize 28 \
    "$CONTACT_SHEET"
else
  "$MAGICK_BIN" \
    montage \
    -label '%t' \
    "${IMAGES[@]}" \
    -tile 4x5 \
    -geometry 480x270+12+42 \
    -background '#10202d' \
    -fill '#d8eef7' \
    -pointsize 28 \
    "$CONTACT_SHEET"
fi

echo "$CONTACT_SHEET"
