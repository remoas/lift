#!/usr/bin/env bash
# Captures every design frame in light and dark on iPhone 16, plus the set row
# at AX3 (accessibility-extra-large). DEBUG build only: frames come from the
# in-memory fixtures behind -LiftFixture, never from real data.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review}"
BUNDLE=com.benspink.lift
FRAMES=(01-log-empty 01b-log-active 01c-target-hit 01d-stale-saved-toast 03-workout 04-rest 05-set-editor 06-pr-banner 07-finish 08-exercise
  10-history 11-settings 12-history-empty 13-first-workout 14-health-error 15-restoring 16-exercise-empty
  18a-picker-empty 18a2-picker-empty-scrolled 18b-picker-bench 18c-picker-rdl 18d-picker-zzqx 18e-picker-press 18f-picker-squat
  18g-picker-deadlift 18h-picker-pull-up 18i-picker-db-incline 18j-picker-benhc 18k-picker-pull-ups 19-reorder 24a-media-video 24b-media-stills 24c-media-reduce-motion 24d-media-loading
  24e-media-none 25-finish-sets-left 26-discard-toast)
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
# AC 68: 01b at AX3 (and 03 for the set rows).
shoot 01b-log-active light accessibility-extra-large
shoot 01b-log-active dark accessibility-extra-large
shoot 03-workout light accessibility-extra-large
# §10.8: 18c at AX3.
shoot 18c-picker-rdl light accessibility-extra-large
shoot 18c-picker-rdl dark accessibility-extra-large
ls "$OUT" | wc -l
