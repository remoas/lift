#!/usr/bin/env bash
# Rest Live Activity review shots on iPhone 16 Pro (design/live-activity.md AC 112).
# la-* frames host the widget's own views in a DEBUG gallery (system chrome is a
# stand-in); island-system-* are the real Dynamic Island from a DEBUG Activity.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/liveactivity}"
BUNDLE=com.benspink.lift
mkdir -p "$OUT"
UDID=$(xcrun simctl create lift-la "iPhone 16 Pro")
trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant notifications "$BUNDLE" 2>/dev/null || true
shoot() { # frame appearance
  xcrun simctl ui "$UDID" appearance "$2"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture "$1" >/dev/null
  sleep 2.5
  xcrun simctl io "$UDID" screenshot "$OUT/$1-$2.png" >/dev/null
}
for f in la-lock-running la-lock-after-miss la-lock-long-name la-lock-rest-over-highlight la-lock-settled la-lock-aod; do
  shoot "$f" light; shoot "$f" dark
done
for f in la-island-compact la-island-minimal la-island-expanded la-island-rest-over la-standby; do shoot "$f" dark; done
# Real system Island: start a DEBUG Activity, then background Lift.
xcrun simctl ui "$UDID" appearance dark
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE" -LiftLiveActivityDemo >/dev/null
sleep 4
xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null || true
sleep 3
xcrun simctl io "$UDID" screenshot "$OUT/island-system-compact-dark.png" >/dev/null || true
xcrun simctl ui "$UDID" appearance light
sleep 2
xcrun simctl io "$UDID" screenshot "$OUT/island-system-compact-light.png" >/dev/null || true
ls "$OUT" | wc -l
