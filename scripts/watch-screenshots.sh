#!/usr/bin/env bash
# Captures CDO's watch frames (design/watch/w01–w14) on the smallest and the
# largest Apple Watch simulators available. DEBUG build only: frames come
# from WatchFixtures behind -LiftFixture, never real data.
set -euo pipefail
APP="$1"; OUT="${2:-screenshots-review/watch}"
BUNDLE=com.benspink.lift.watchkitapp
FRAMES=(w01-empty w02-exercise w03-counting w04-counting-off w05-first-time w06-rest w07-rest-up
  w08-target-hit w09-add w10-finish w11-always-on w12-unreachable w13-skip-toast w14-rest-picker
  w15-target-hit-quiet w16-health-off w17-rest-off w18-finish-sets-left w19-crown-focus w20-after-miss)
mkdir -p "$OUT"
# Only simulators whose runtime is installed (creating from a device type can
# pick one with no runtime).
AVAIL=$(xcrun simctl list devices available | grep -E "Apple Watch" || true)
echo "$AVAIL"
pick() { echo "$AVAIL" | grep -E "$1" | tail -1 | sed -E 's/^ *//; s/ \(([0-9A-F-]{36})\).*/|\1/' || true; }
SMALL=$(pick "\((40|41)mm\)")
# The 41 and 45 mm classes (CDO QA 3): Series 7–9 sims if installed, else Series 10/11
# at 42 and 46 mm, which take the same layout branch (WatchTheme.isLarge = width ≥ 198).
MID_S=$(pick "\(41mm\)" | grep -v "^$SMALL$" || true); [ -n "$MID_S" ] || MID_S=$(pick "Series (10|11) \(42mm\)")
MID_L=$(pick "\(45mm\)"); [ -n "$MID_L" ] || MID_L=$(pick "Series (10|11) \(46mm\)")
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
    # Add loads the whole library; a slow small simulator can still show the launch screen at 15 s.
    if [ "$f" = w09-add ]; then sleep 30; else sleep 3; fi
    xcrun simctl io "$UDID" screenshot "$OUT/$f-$2.png" >/dev/null
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
echo "small: $SMALL · 41-class: $MID_S · 45-class: $MID_L · large: $LARGE"
for D in "$SMALL" "$MID_S" "$MID_L" "$LARGE"; do
  if [ -n "$D" ]; then shoot_on "$D" "$(echo "${D%%|*}" | grep -oE '[0-9]+mm' | tail -1)"; fi
done
mkdir -p "$OUT/../watch-logs"; cp ~/Library/Logs/DiagnosticReports/LiftWatch* "$OUT/../watch-logs/" 2>/dev/null || true
ls "$OUT"
