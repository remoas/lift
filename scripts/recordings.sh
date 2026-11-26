#!/usr/bin/env bash
# Screen recordings for the shared-transition flows (AC 61), iPhone 16, default
# text size: normal speed light + dark, Slow Animations light, Reduce Motion light.
# Uses the DEBUG build's UI-test bundle in build/dd (FlowRecordings drives the app).
set -uo pipefail
OUT="${1:-screenshots-review/recordings}"
LOG="${2:-review-logs/recordings.log}"
mkdir -p "$OUT" "$(dirname "$LOG")"
BUNDLE=com.benspink.lift
UDID=$(xcrun simctl create lift-rec "iPhone 16")
trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
boot() {
  xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b >/dev/null
  # No QuickPath "slide to type" coaching card over keyboard frames (QA 6).
  xcrun simctl spawn "$UDID" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardContinuousPathEnabled -bool false || true
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl ui "$UDID" content_size large
}
boot
FLOWS=(testFlow1TodayToWorkout testFlow2ExerciseRowToDetail testFlow3PRBanner)
NAMES=(flow1-today-to-workout flow2-row-to-detail flow3-pr-banner)
rec() { # variant appearance slowFactor
  xcrun simctl ui "$UDID" appearance "$2"
  for i in 0 1 2; do
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    FILE="$OUT/${NAMES[$i]}-$1.mp4"
    echo "== ${NAMES[$i]} $1" >> "$LOG"
    ( env TEST_RUNNER_LIFT_RECORD=1 ${3:+TEST_RUNNER_LIFT_SLOW=$3} \
      xcodebuild test-without-building -project Lift.xcodeproj -scheme Lift -destination "id=$UDID" \
      -derivedDataPath build/dd -only-testing:"LiftUITests/FlowRecordings/${FLOWS[$i]}" >> "$LOG" 2>&1 \
      && echo "   passed" >> "$LOG" || echo "   FAILED" >> "$LOG" ) &
    XB=$!
    # Start recording only once Lift itself is running (skip test-runner start-up).
    for _ in $(seq 1 240); do
      xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE" && break
      kill -0 "$XB" 2>/dev/null || break
      sleep 0.5
    done
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$FILE" >/dev/null 2>&1 &
    PID=$!
    wait "$XB"
    kill -INT "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
    ls -la "$FILE" >> "$LOG" 2>&1
  done
}
rec normal-light light ""
rec normal-dark dark ""
rec slow-light light 10
# Reduce Motion: set the accessibility preference, then reboot so apps read it.
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
xcrun simctl shutdown "$UDID"; boot
rec reduce-motion-light light ""
grep -E "^==|passed|FAILED" "$LOG"
ls "$OUT"
