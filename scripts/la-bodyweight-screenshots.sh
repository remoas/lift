#!/usr/bin/env bash
# AC 123: Lock Screen, Dynamic Island, bodyweight rows and the set editor,
# on iPhone 16 Pro so the Island is present. Light and dark where relevant.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/la-bodyweight}"
BUNDLE=com.benspink.lift
mkdir -p "$OUT"
UDID=$(xcrun simctl create lift-la-bw "iPhone 16 Pro")
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
# Lock Screen: Resting, Rest over, Ready — loaded, Bodyweight, belt, assistance.
for f in la-lock-resting-loaded la-lock-resting-bw la-lock-rest-over-loaded la-lock-rest-over-bw \
         la-lock-ready-loaded la-lock-ready-bw la-lock-ready-belt la-lock-ready-assist; do
  shoot "$f" light
  shoot "$f" dark
done
# Island is always dark tokens; shoot dark (and light wallpaper around compact).
for f in la-island-compact-resting la-island-compact-ready la-island-compact-ready-belt \
         la-island-minimal-resting la-island-minimal-ready \
         la-island-expanded-resting la-island-expanded-ready la-island-expanded-ready-bw; do
  shoot "$f" dark
done
# In-app surfaces.
for f in 01e-log-pullup 01f-log-pullup-belt 01g-pullup-belt-hit \
         05b-set-editor-bodyweight 05c-set-editor-add-weight \
         07b-finish-pullup 08b-exercise-pullup \
         10b-history-pullup 10c-history-pullup-belt; do
  shoot "$f" light
  shoot "$f" dark
done
ls "$OUT" | wc -l
