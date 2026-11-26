#!/usr/bin/env bash
# Captures every design frame in light and dark on iPhone 16, plus the set row
# at AX3 (accessibility-extra-large). DEBUG build only: frames come from the
# in-memory fixtures behind -LiftFixture, never from real data.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review}"
BUNDLE=com.benspink.lift
FRAMES=(01-today 02a-welcome 02b-days 02c-build-empty 02d-setup-picker 02e-build-filled 03-workout 04-rest
  05-set-editor 06-pr-banner 07-finish 08-exercise 09-routines 10-history 11-settings 12-history-empty
  13-first-workout 14-health-error 15-restoring 16-exercise-empty 17-choose-workout 18-exercise-picker
  19-reorder 20-finish-changed 21-finish-blank 22-today-day-empty 23-routines-empty
  24a-media-video 24b-media-stills 24c-media-reduce-motion 24d-media-loading 24e-media-none
  25-finish-sets-left 26-discard-toast 27-finish-save-routine)
mkdir -p "$OUT"
UDID=$(xcrun simctl create lift-shots "iPhone 16")
trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
# No QuickPath "slide to type" coaching card over keyboard frames (QA 6).
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true || true
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardContinuousPathEnabled -bool false || true
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
# Pre-grant notifications so no permission alert covers a frame.
xcrun simctl privacy "$UDID" grant notifications "$BUNDLE" 2>/dev/null || true
shoot() { # frame appearance [size]
  xcrun simctl ui "$UDID" appearance "$2"
  xcrun simctl ui "$UDID" content_size "${3:-large}"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture "$1" >/dev/null
  sleep 2.5
  xcrun simctl io "$UDID" screenshot "$OUT/$1-$2${3:+-$3}.png" >/dev/null
}
for f in "${FRAMES[@]}"; do shoot "$f" light; shoot "$f" dark; done
shoot 03-workout light accessibility-extra-large
shoot 03-workout dark accessibility-extra-large
ls "$OUT" | wc -l
