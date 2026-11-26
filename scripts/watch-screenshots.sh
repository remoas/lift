#!/usr/bin/env bash
# Captures CDO's watch frames (design/watch/w01–w14) on the smallest and the
# largest Apple Watch simulators available. DEBUG build only: frames come
# from WatchFixtures behind -LiftFixture, never real data.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/watch}"
BUNDLE=com.benspink.lift.watchkitapp
FRAMES=(w01-empty w02-exercise w03-counting w04-counting-off w05-first-time w06-rest w07-rest-up
  w08-target-hit w09-add w10-finish w11-always-on w12-unreachable w13-skip-toast w14-rest-picker)
mkdir -p "$OUT"
# Only simulators whose runtime is installed (creating from a device type can
# pick one with no runtime).
AVAIL=$(xcrun simctl list devices available | grep -E "Apple Watch" || true)
echo "$AVAIL"
pick() { echo "$AVAIL" | grep -E "$1" | tail -1 | sed -E 's/^ *//; s/ \(([0-9A-F-]{36})\).*/|\1/'; }
SMALL=$(pick "\((40|41|42)mm\)")
LARGE=$(pick "Ultra.*\(49mm\)"); [ -n "$LARGE" ] || LARGE=$(pick "\((45|46)mm\)")
shoot_on() { # "name|udid" suffix
  local UDID="${1##*|}"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b
  xcrun simctl status_bar "$UDID" override --time 10:22 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  for f in "${FRAMES[@]}"; do
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" -LiftFixture "$f" >/dev/null
    sleep 3
    xcrun simctl io "$UDID" screenshot "$OUT/$f-$2.png" >/dev/null
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
echo "small: $SMALL · large: $LARGE"
[ -n "$SMALL" ] && shoot_on "$SMALL" "$(echo "$SMALL" | grep -oE '[0-9]+mm')"
[ -n "$LARGE" ] && shoot_on "$LARGE" "$(echo "$LARGE" | grep -oE '[0-9]+mm')"
ls "$OUT"
