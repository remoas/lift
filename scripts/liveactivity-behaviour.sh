#!/usr/bin/env bash
# Behaviour proof for the rest Live Activity (AC 99, 106–109): runs the DEBUG
# harness against real ActivityKit on iPhone 16 Pro, records the simulator, and
# backgrounds Lift for the two rest-end steps so the Dynamic Island shows them.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/liveactivity/behaviour}"
BUNDLE=com.benspink.lift
mkdir -p "$OUT"
UDID=$(xcrun simctl create lift-la-beh "iPhone 16 Pro")
trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant notifications "$BUNDLE" 2>/dev/null || true
xcrun simctl ui "$UDID" appearance dark
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/la-behaviour.mp4" &
REC=$!
sleep 2
xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture 03-workout -LiftLiveActivityBehaviour >/dev/null
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
LOG="$DATA/Documents/la-behaviour.log"
until_log() { # pattern [timeout]
  for _ in $(seq 1 $(( ${2:-60} * 4 ))); do grep -q "$1" "$LOG" 2>/dev/null && return 0; sleep 0.25; done
  echo "timed out waiting for: $1"; return 0
}
until_log "14 rest 150s" 150
xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null || true   # Lift to the background: the system Island
sleep 4; xcrun simctl io "$UDID" screenshot "$OUT/island-system-running.png" >/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || true                 # back to Lift (no relaunch while it runs)
until_log "DONE" 60
sleep 1; xcrun simctl io "$UDID" screenshot "$OUT/harness-log-end.png" >/dev/null || true
kill -INT $REC; wait $REC || true
cp "$LOG" "$OUT/la-behaviour.log" || echo "no harness log"
cat "$OUT/la-behaviour.log" || true
ls -la "$OUT"
