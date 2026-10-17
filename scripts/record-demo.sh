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
echo "Saved: $OUT ($(du -h "$OUT" | cut -f1))"

# A raw Retina screen recording is hundreds of MB, too big to email or attach. Make a 1080p
# copy of about 45 MB that is easy to share (Apple's own encoder; the original is kept).
SHARE="${OUT%.mov}-share.mp4"
echo "Making a small copy to share (about half a minute)..."
if swift scripts/shrink-video.swift "$OUT" "$SHARE" "${AIRSWIPE_SHARE_MB:-45}" >/dev/null 2>&1; then
    echo "Share this one: $SHARE ($(du -h "$SHARE" | cut -f1))"
else
    echo "Could not make the small copy; the full recording is at $OUT"
fi
