#!/usr/bin/env bash
# Captures the watch frames on the newest Apple Watch simulator. DEBUG build
# only: frames come from WatchFixtures behind -LiftFixture, never real data.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/watch}"
BUNDLE=com.benspink.lift.watchkitapp
FRAMES=(w01-empty w02-exercise w03-target-hit w04-counting w05-rest w06-add w07-end w08-finish)
mkdir -p "$OUT"
UDID="${WATCH_UDID:-}"
if [ -z "$UDID" ]; then
  TYPE=$(xcrun simctl list devicetypes | grep -E "Apple Watch Series [0-9]+ \(4[56]mm\)" | tail -1 | sed -E 's/ \(com\.apple.*//')
  UDID=$(xcrun simctl create lift-watch-shots "$TYPE")
  trap 'xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
for f in "${FRAMES[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture "$f" >/dev/null
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$f.png" >/dev/null
done
ls "$OUT"
