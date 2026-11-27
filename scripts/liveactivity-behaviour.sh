#!/usr/bin/env bash
# Behaviour proof for the rest Live Activity (AC 99, 106–109): runs the DEBUG
# harness against real ActivityKit on iPhone 16 Pro, records the simulator, and
# backgrounds Lift for the two rest-end steps so the Dynamic Island shows them.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/liveactivity/behaviour}"
BUNDLE=com.benspink.lift
mkdir -p "$OUT"
# Every simctl call is bounded: a hung simulator call must not eat the job.
t() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
UDID=$(t 120 xcrun simctl create lift-la-beh "iPhone 16 Pro")
trap 't 60 xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
t 120 xcrun simctl boot "$UDID"
t 240 xcrun simctl bootstatus "$UDID" -b
t 60 xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 || true
t 120 xcrun simctl install "$UDID" "$APP"
t 30 xcrun simctl privacy "$UDID" grant notifications "$BUNDLE" 2>/dev/null || true
t 30 xcrun simctl ui "$UDID" appearance dark
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/la-behaviour.mp4" &
REC=$!
sleep 2
# simctl launch can block well past the app starting on a cold simulator: don't wait on it, wait on the log.
( t 240 xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture 03-workout -LiftLiveActivityBehaviour >/dev/null || echo "launch call returned late or failed" ) &
DATA=$(t 60 xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
LOG="$DATA/Documents/la-behaviour.log"
until_log() { # pattern [timeout]
  for _ in $(seq 1 $(( ${2:-60} * 4 ))); do grep -q "$1" "$LOG" 2>/dev/null && return 0; sleep 0.25; done
  echo "timed out waiting for: $1"; return 0
}
until_log "14 rest 150s" 300
t 30 xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null || true   # Lift to the background: the system Island
sleep 4; t 30 xcrun simctl io "$UDID" screenshot "$OUT/island-system-running.png" >/dev/null || true
t 30 xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null || true                 # back to Lift (no relaunch while it runs)
until_log "DONE" 60
sleep 1; t 30 xcrun simctl io "$UDID" screenshot "$OUT/harness-log-end.png" >/dev/null || true
kill -INT $REC || true
# recordVideo can fail to exit; give it 20 s to finish the file, then stop it.
for _ in $(seq 1 40); do kill -0 $REC 2>/dev/null || break; sleep 0.5; done
kill -9 $REC 2>/dev/null || true; wait $REC 2>/dev/null || true
cp "$LOG" "$OUT/la-behaviour.log" || echo "no harness log"
cat "$OUT/la-behaviour.log" || true
ls -la "$OUT"
