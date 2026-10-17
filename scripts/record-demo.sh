#!/bin/zsh
# Records the screen while you demo AirSwipe, with its preview window on it (your camera, the
# hand drawn on it, and what AirSwipe is doing), so the video shows you and the Mac at once.
#
#   scripts/record-demo.sh [seconds]      default 90
#
# What it does: builds and starts AirSwipe live with voice and the preview window, counts down
# so you can get your screen ready, then records the whole screen with macOS's own
# `screencapture` and saves ~/Desktop/AirSwipe-demo-<time>.mov. Recording stops by itself.
#
# The first time, macOS asks to let your terminal record the screen (System Settings >
# Privacy & Security > Screen & System Audio Recording). Allow it, then run this again.
set -e

cd "${0:A:h}/.."
SECONDS_TO_RECORD="${1:-90}"
OUT="$HOME/Desktop/AirSwipe-demo-$(date +%Y%m%d-%H%M%S).mov"

swift build -q
.build/debug/airswipe --live --voice --preview &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true' EXIT INT TERM

echo "AirSwipe is running; its preview window is in the bottom-right corner."
echo "Get your screen ready now: the pages or apps you will use, Claude on a throwaway chat."
for n in 10 9 8 7 6 5 4 3 2 1; do
    printf "\rRecording starts in %2d s... " "$n"
    sleep 1
done
printf "\n"

echo "Recording $SECONDS_TO_RECORD s to $OUT"
echo "Do your demo now: arm, swipe, pinch-scroll, a circle with a search, thumbs up, fist to stop."
screencapture -v -x -V "$SECONDS_TO_RECORD" "$OUT"
echo "Saved: $OUT"
