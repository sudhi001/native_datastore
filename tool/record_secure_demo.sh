#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# record_secure_demo.sh — Record the Secure Storage demo GIF on a booted iOS
# simulator using the self-driving demo entrypoint (lib/demo_main.dart), which
# performs real SecureDatastore operations on a loop.
#
#   tool/record_secure_demo.sh <simulator-udid> [seconds]
#
# Produces doc/assets/secure-demo.gif. Requires a BOOTED simulator + ffmpeg.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/.."
SIM_ID="${1:?usage: record_secure_demo.sh <simulator-udid> [seconds]}"
SECS="${2:-13}"
BUNDLE_ID="in.sudhi.androidDatastoreExample"

echo "Building demo app for the simulator..."
( cd example && flutter build ios --debug --simulator -t lib/demo_main.dart )
APP="example/build/ios/iphonesimulator/Runner.app"

echo "Installing..."
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP"

MOV="$(mktemp -t secure_demo).mov"
echo "Recording $SECS s -> $MOV"
xcrun simctl io "$SIM_ID" recordVideo --codec h264 --force "$MOV" &
REC_PID=$!
sleep 1.5

# Cold-launch so the loop starts at its intro frame.
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null
sleep "$SECS"

echo "Stopping recorder..."
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true

echo "Converting to GIF..."
OUT="doc/assets/secure-demo.gif"
PALETTE="$(mktemp -t secure_pal).png"
# 10 fps, ~1/3 width; two-pass palette for a small, clean GIF.
FILT="fps=10,scale=320:-1:flags=lanczos"
ffmpeg -y -i "$MOV" -vf "$FILT,palettegen=max_colors=96" "$PALETTE" >/dev/null 2>&1
ffmpeg -y -i "$MOV" -i "$PALETTE" \
  -lavfi "$FILT[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$OUT" >/dev/null 2>&1

rm -f "$MOV" "$PALETTE"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
