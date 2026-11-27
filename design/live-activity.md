# Lift · Rest-timer Live Activity (phone)

Draft by CDO, 26 Nov 2026, 4:51pm Bermuda time. Drafts only. Nothing ships, goes to TestFlight or is published without Ben’s own yes.

Ben asked at **4:47pm Bermuda time, 26 Nov**, relayed by the iOS Developer: a Live Activity for Lift’s rest timer between sets, covering the Lock Screen and the Dynamic Island (compact, minimal and expanded). It is no longer deferred. The Live Activity part of `watch.md` AC 76 is **active**; this file is the source of truth for it. Complications and the Smart Stack row in AC 81 stay deferred.

It follows the quick-log model, the rest rules in `watch.md` §3.8–3.9 (`Exercise.restSec`, +30s / Skip, device-winner alerts), and Ben’s prefill rule from **2:16pm Bermuda time, 26 Nov**, in CDO chat: “Prefill the next set with what I just did.” Tokens come from `DESIGN.md`. Ember is used only for the countdown ring or draining line, and for Skip (the one primary).

Mocks: `live-activity/mock.html` · board: `live-activity/board.png`. The older phone frame `29-rest-live-activity` in `mock.html` is superseded by these.

Deployment: iOS 17, ActivityKit. Dynamic Island is hardware-dependent (iPhone 14 Pro and later); other iPhones get the Lock Screen (and StandBy) only. No deployment-target bump.

---

## 1. When it runs

Start a single Live Activity when rest starts after a logged set, unless rest is Off (`watch.md` §3.10). If a previous rest-over Activity is still on screen, update it in place with the new exercise, set and end date — do not stack a second one.

It is started even when the phone is in the foreground on the workout, so the Island and a later lock are already in place. The in-app rest bar remains the in-app surface (DESIGN.md signature 2).

Do not start one when rest is Off, when the workout is already finished, or when Live Activities are disabled for Lift. If `Activity.request` throws, fail silently: the rest bar, the watch rest page and the existing rest-end path in `watch.md` §3.9 still run. There is no extra permission prompt for Live Activities; notification permission continues to be asked at the first rest, never at launch.

---

## 2. Content and sources

Four facts, from the same sources as the phone rest bar and the watch rest page:

| Fact | Source | Example (Ben, lb) |
|---|---|---|
| Exercise name | The lift this rest belongs to | Barbell Bench Press |
| Next set | The **prefill**, not “Beat it” | Set 3 · 185 lb × 9 |
| Countdown | This break’s remaining time | 1:42 |
| End state | The set that is now due | Rest over · Set 3 |

**Prefill, not the target.** The first set of an exercise prefills at the target. Every later set prefills with the set just logged in this session (`spec.md` §9, Ben 2:16pm). “Beat it” and *the bar* on the Log screen and the watch keep the target; they do not appear on the Live Activity. So after aiming for 180 × 9 and logging 180 × 7, the Activity reads **Set 3 · 180 lb × 7**, not 180 × 9.

**Units** follow the exercise’s unit (the per-exercise override, otherwise the Settings default). Ben uses lb, so the fixtures are **185 lb × 9**, not kg. A kg session reads “80 kg × 8”. Do not also show the other unit, even if “Show the other unit too” is on in Settings. Format is `{weight} {unit} × {reps}`, with spaces around `×`. Bodyweight with no added load is **“9 reps”**, never “0 lb × 9”. With added load: “BW + 25 lb × 9”.

**Set N** is the set that is now due, not the one just logged. After logging set 2, rest shows “Set 3 · …”; at zero it reads “Rest over · Set 3”.

The countdown uses the system timer, so it ticks without Activity updates:

- `Text(timerInterval: start...end, countsDown: true, showsHours: false)` for the tabular m:ss (SF Pro, `.monospacedDigit()`, the `timer` token on Lock Screen and expanded; a smaller title style in compact trailing).
- `ProgressView(timerInterval: start...end, countsDown: true)` for the ring or the draining line, tinted Ember, linear over the rest (`restDrain`).

Push an Activity update only when the facts change: +30s (new end date), Skip, a new rest starting, rest ending, or the workout ending. At zero, the same rest-end handler that already owns the watch/phone alert also updates the Activity to the rest-over state. Do not depend on a local notification as the only update path.

---

## 3. Dynamic Island

The Island is always dark. Use the dark tokens (`textPrimary` #F5F4F1, `textSecondary` #A6A39E, Ember `#FF8A3D`). The mini-ring track is `separator` (#2C2C30) or `controlStroke` (#6E6B67) — not Ember. No *bar*. No buttons in compact or minimal.

**Compact leading:** an Ember mini ring, 22–24 pt, 2.5 pt stroke, butt caps, starting at 12 o’clock, draining to empty as rest runs out. This is a small cousin of the watch rest ring, not a Fitness gauge (no ticks, no fill). Remaining time is not written inside it; that sits in trailing.

**Compact trailing:** tabular m:ss in `textPrimary`. At zero, keep `0:00`.

**Minimal:** the Ember mini ring alone, same construction, sized to the minimal slot.

**Expanded:**

- Exercise name, `bodyEmphasis` / semibold, one line (see §8).
- Next set on the line below, `secondary`: “Set 3 · 185 lb × 9”.
- A large tabular m:ss in `textPrimary`, with an Ember ring (32–40 pt, 3 pt stroke) beside or around it — the time must stay readable; if the ring would shrink the numerals below ~22 pt, put the ring beside the time, not around it.
- **+30s** and **Skip** along the bottom, via App Intents (`LiveActivityIntent`). **Skip is the primary:** Ember text, not a fill. +30s is `textPrimary` on a sunken chip. Both are the same height, at least 44 pt where they fit; never below 36 pt in the Island. No confirm.

A tap on the Island that is not a button opens the in-progress workout on this exercise (`§7`).

---

## 4. Lock Screen

The system draws the header (Lift icon, “Lift”, “now”). Our content below:

- A **3 pt Ember draining line** along the top of the card (DESIGN.md signature 2, the same language as the in-app rest bar). It shrinks left-to-right to zero, left-anchored, 2 pt cap radius. No ring on the Lock Screen; the line is the progress.
- Exercise name, `bodyEmphasis`, one line.
- Next set, `secondary`: “Set 3 · 185 lb × 9”.
- A large tabular m:ss in `textPrimary` (title / `timer` scale, ~28–34 pt), trailing or under the name so it reads at arm’s length.
- **+30s** and **Skip** along the bottom, same App Intents as the Island, 44 pt tall and at least 56 pt wide, `radiusChip` 12. Skip is Ember text; +30s is `textPrimary` on `bgSunken`. No confirm.

The card uses `bgRaised` and the matching light or dark text tokens, with `activityBackgroundTint` so a colourful wallpaper cannot wash out the type. Contrast of every text colour against that tint is at least **4.5:1** in both appearances (textPrimary, textSecondary, Ember `#C2410C` on light and `#FF8A3D` on dark, onAccent if used). Do not put textTertiary on `accentSoft`, and do not use the light Ember on a dark card.

No *bar* on the Lock Screen either. Next is the prefill, and the bar means the target.

A tap that is not a button opens the in-progress workout on this exercise.

---

## 5. Rest over

When the timer reaches zero, update the Activity to an **alert-style** end state.

Copy: **“Rest over · Set N”** as the lead line. Keep the exercise name and the next prefill (“185 lb × 9”). Replace the countdown with tabular `0:00` (or drop it if the lead line plus the prefill are clearer). Hide +30s and Skip. The draining line or ring sits empty.

**Highlight for about 2 seconds:** use the ActivityKit `alertConfiguration` as the prominent moment, and tint the card `accentSoft` for those two seconds, then settle back to `bgRaised` with the same copy. If a follow-up update at 2 s cannot be scheduled from the background, the alert presentation itself is the highlight — do not fail QA for a missing tint. Reduce Motion: no pulse, scale or flash; the copy and optional tint change with `fadeReduced` (0.15 s).

**When the watch is the device winner** (worn, and this workout’s `HKWorkoutSession` is running): still update the Activity to Rest over, so a glance at the phone is honest. **Suppress the alert.** No `alertConfiguration`, no sound, no haptic, no time-sensitive notification. The watch haptic in `watch.md` §3.9 is the only rest-end signal. This is the same device-winner rule as the phone notification, extended to the Activity.

**When the phone is the winner** (watch not worn, not in a session, or not reachable) and the phone is locked or backgrounded: fire the alert-style update. Do **not** also send the time-sensitive local notification — that would be two banners. If the phone is already in the foreground on the workout, the rest bar is enough; update the Activity quietly, with no alert.

**If the Live Activity is not running** (disabled, failed to start): fall back to the existing time-sensitive notification in `watch.md` §3.9, with the lead “Rest over.” — “Rest over. Barbell Bench Press, 185 lb × 9.” The watch on-wrist copy stays “Rest’s up”.

**Stale and dismissal (accepted, no push server).** Lift cannot push an Activity update or an `alertConfiguration` while it is suspended. The accepted path, confirmed in `acdb179` and the behaviour harness (`qa-live-activity-run2.md`):

- While rest is running, `staleDate` is set to **rest-end** (not rest-end + 2 minutes), so the system can mark the Activity stale at zero. The Live Activity *view* treats stale (or `now >= end`) as Rest over on its own: “Rest over · Set N”, tabular `0:00`, empty line or ring, +30s and Skip hidden. No Activity update is required for that visual flip.
- When Lift itself writes Rest over (the rest-end handler ran), stale moves to rest-end + **2 minutes** and dismissal is `.after(rest-end + 5 minutes)`. The ~2 s `accentSoft` highlight and `alertConfiguration` fire only when the phone is the device winner and Lift is not on screen.
- The time-sensitive local notification is the rest-end fallback while Lift is suspended. **Schedule it only when the phone is the device winner at rest start** (no watch `HKWorkoutSession` for this workout). When the watch is the winner, do not schedule a phone notification at all — a suspended Lift cannot cancel it, and the watch haptic is already the one signal. When Lift next becomes active, cancel any leftover notification.
- Because `end(dismissalPolicy:)` cannot be applied while Lift is suspended, a stale Rest over card may remain until Lift next opens. An on-open `sweep()` then ends it immediately if it is past +5 minutes, or ends it with `.after(rest-end + 5 minutes)` if it is still inside the window. This is an accepted platform limit, not a product fail. A new rest still updates the same Activity in place; Finish still ends it `.immediate`.
- If the Activity is not running, the existing `watch.md` §3.9 notification path is unchanged.

---

## 6. +30s, Skip, Finish

**+30s** lengthens only this break. It never writes `Exercise.restSec`. Push one Activity update with the new end date; the system timer and progress jump to the new remaining time. The same action, the same App Intent, as the in-app and watch chips, and it syncs to the watch.

**Skip** ends rest immediately, with no confirm. The Activity updates to Rest over **without** an alert (the user just skipped). It dismisses after **5 seconds**, which matches the in-app “Rest skipped · Undo” window. There is no Undo on the Activity itself. If Undo is used on the phone or the watch, restore the Activity with the remaining time.

**Logging the next set** ends this rest (no toast) and, if that lift has rest, updates the same Activity to the new rest. If rest is Off, end the Activity immediately (`.immediate`).

**Finish workout**, Discard, and the 3 h auto-finish: `end` the Activity immediately with `.immediate` dismissal. Do not pass through Rest over. The Activity must be gone before the Finish screen lands.

---

## 7. Tap, Always-On, StandBy, Reduce Motion

**Tap** (anywhere that is not +30s or Skip) opens the in-progress workout on the current exercise, with the rest bar showing if rest is still running. It does not open Today, and it does not log a set.

**Always-On** (Lock Screen, iPhone 14 Pro and later): use the system timer and `ProgressView` so the m:ss and the line keep moving while dimmed. The time stays `textPrimary` so it remains the most readable thing (same lesson as watch QA item 16). Ember can sit at a lower luminance. +30s and Skip are not tappable until the display wakes (raise or tap). No bright flash at rest-end; the alert (when allowed) and the words “Rest over · Set N” do the work.

**StandBy** is in, because it is cheap on iOS 17: there is no separate StandBy Activity family, so the Lock Screen presentation is reused at StandBy scale. Use text styles, not fixed tiny sizes, so the name, the next set and the m:ss stay readable in landscape. No custom StandBy layout and no requirement to hide or add buttons if the system already has a view. Night StandBy (the red tint) is left to the system; do not force Ember through it. A tap opens the workout. Visual QA includes one StandBy frame.

**Reduce Motion:** no translation or scale on appear, update or rest-over. State changes use `fadeReduced` (0.15 s, `.easeInOut`). The timer and the progress still run; they are the information, not decoration. The rest-over highlight is a copy change (and the optional tint), never a pulse.

---

## 8. Truncation

- **Compact and minimal:** no name, no set line. Nothing to truncate except the m:ss, which is always `m:ss` (or `mm:ss` if +30s has pushed a break past 9:59).
- **Exercise name** (expanded, Lock Screen, StandBy): one line. `minimumScaleFactor` 0.85, then tail ellipsis at a word boundary if possible. Never mid-word if a word boundary fits, and never mid-number.
- **Next set:** never truncate mid-number. If “Set 3 · 185 lb × 9” does not fit: drop “Set 3 ·” first, keep “185 lb × 9”. If it is still tight: “185×9”. Bodyweight follows the same ladder: “Set 3 · 9 reps” → “9 reps”.
- Dynamic Type: everything scales. At AX3, prefer dropping “Set N ·” over shrinking the m:ss. The timer stays tabular and untruncated.

---

## 9. Ember, type, contrast

Ember is only on the compact/minimal/expanded ring, the Lock Screen draining line, and Skip. One primary: Skip, as Ember text, not a fill. No Ember on the exercise name, the set line, +30s, or the m:ss. No *bar* on this surface.

Type is SF Pro (the phone), all numerals `.monospacedDigit()`. Sentence case. No uppercase labels, no stat strips, no card grids. The mocks use Inter as a stand-in.

Measured contrast must hold on the dark Island, on a light Lock Screen card, and on a dark Lock Screen card, as in DESIGN.md.

---

## 10. Acceptance criteria (99–112)

99. A single Live Activity starts when rest starts after a log, unless rest is Off. It starts even if the phone is in the foreground. If Live Activities are disabled or `Activity.request` fails, fail silently; the rest bar and `watch.md` §3.9 still run. No second Activity is stacked; a new rest updates the existing one in place. iOS 17, ActivityKit, no target bump.

100. The Activity shows the exercise name, the next set from the **prefill** source in `spec.md` §9 (Ben, 2:16pm: first set is the target, later sets are what was just logged), and a countdown. Units follow the exercise’s unit setting; fixtures use **185 lb × 9**. Bodyweight with no added load reads “9 reps”, never “0 lb × 9”. “Beat it” and *the bar* do not appear. Set N is the set now due.

101. The countdown is `Text(timerInterval:countsDown:)` and the ring or line is `ProgressView(timerInterval:countsDown:)`, tinted Ember, so both tick without Activity updates. Updates are pushed only for +30s, Skip, a new rest, rest-end, or workout end. The rest-end handler updates the Activity at zero.

102. Compact leading is an Ember mini ring (22–24 pt, 2.5 pt stroke). Compact trailing is tabular m:ss. Minimal is the ring alone. No name, no bar, no buttons in compact or minimal. The Island uses dark tokens; Ember is `#FF8A3D`.

103. Expanded Island shows the name, “Set N · {w} {unit} × {r}”, a large tabular m:ss with an Ember ring, and +30s and Skip via App Intents. Skip is the primary (Ember text, not a fill). +30s is `textPrimary` on a sunken chip. Targets are 44 pt where they fit, never below 36 pt.

104. Lock Screen: system header, 3 pt Ember draining line (signature 2, left-anchored), name, next set, large tabular m:ss, and the same +30s / Skip at 44 × ≥56 pt, `radiusChip` 12. Light and dark `bgRaised` tints, all text ≥ 4.5:1. No bar. Visual QA of `live-activity/` light and dark Lock Screen frames.

105. At zero the Activity shows “Rest over · Set N”, the name, the prefill, and `0:00` (or no timer), with +30s and Skip hidden. The view may reach that state on its own when the system marks the Activity stale at rest-end (no push required). A ~2 s highlight uses the alert-style update (and an `accentSoft` tint if a follow-up update is possible) only when Lift can write Rest over and the phone is the winner off-screen. While rest is running, `staleDate` is rest-end; once Lift writes Rest over, stale moves to rest-end + 2 minutes and dismissal is `.after(rest-end + 5 minutes)`. If Lift stayed suspended, an on-open sweep applies that dismissal, or ends the Activity immediately if it is already past +5 minutes.

106. Device winner matches `watch.md` §3.9 and extends to the Activity: a worn watch in this session means the Activity still goes to Rest over (by a write if Lift is awake, or by becoming stale at zero if it is not), but the phone alert is suppressed — no `alertConfiguration`, no sound, no haptic, and **no local notification is scheduled**. When the phone is the winner, schedule the time-sensitive local notification as the fallback if Lift may be suspended at zero; if Lift is awake at rest-end and is locked or backgrounded, the Activity alert is the one banner and the notification is cancelled, not also fired. If the Activity is not running, fall back to “Rest over. {name}, {prefill}.” Permission stays at the first rest.

107. +30s updates the end date only and never writes `Exercise.restSec`. Skip ends rest with no confirm and no alert, dismisses the Activity after 5 s, and a phone or watch Undo restores it with the remaining time. Logging the next set updates the Activity to the new rest, or ends it immediately if rest is Off.

108. Finish, Discard, and the 3 h auto-finish end the Activity immediately with `.immediate` dismissal, before the Finish screen lands, and never pass through Rest over.

109. A tap that is not +30s or Skip opens the in-progress workout on the current exercise. It does not open Today and does not log a set.

110. Reduce Motion: `fadeReduced` only, no pulse or scale; the timer and progress still run. Always-On: system timer and line keep moving, m:ss stays `textPrimary`, Ember may dim, buttons wait for a wake, no flash at rest-end. StandBy reuses the Lock Screen presentation at StandBy scale, with text styles that stay readable; no custom StandBy family. Night StandBy is left to the system.

111. Truncation follows §8: one-line names, no mid-number ellipsis, “Set N ·” drops first. Compact and minimal never show a name.

112. Ember is only on the ring or draining line and on Skip. Type is SF Pro, tabular numerals, sentence case. Contrast holds on the dark Island and on light and dark Lock Screen tints. Visual QA: the frames in `live-activity/mock.html` and `live-activity/board.png`, light and dark, plus one StandBy frame and one Always-On Lock Screen frame.

---

## 11. Decisions (this delta)

Resolved here, nothing to wait on from Ben:

- Next is the prefill (Ben, 2:16pm), never the Beat it target, so *the bar* stays off this surface.
- Units follow the exercise setting; examples are in lb (185 lb × 9). The other-unit toggle is not shown.
- System `Text(timerInterval:)` and `ProgressView(timerInterval:)` drive the tick, so rest does not need a push every second.
- Compact leading is the Ember mini ring; compact trailing is m:ss; minimal is the ring alone.
- Skip is the one primary, Ember text, on Lock Screen and expanded only.
- The Lock Screen uses signature 2 (the 3 pt line), not a ring. The Island uses a ring, because a 3 pt line is too thin in the compact slot.
- Rest-over copy is “Rest over · Set N”. The watch on-wrist line stays “Rest’s up”.
- A worn watch in session still shows the Activity, but the phone alert is suppressed, so there is no double buzz.
- Finish dismisses immediately.
- StandBy is the Lock Screen view, scaled; no extra layout work.
- Without a push server: `staleDate` is rest-end while the timer runs, so the view can show “Rest over” on its own; once Lift writes Rest over, stale is rest-end + 2 minutes and dismissal is + 5 minutes. If Lift stayed suspended, an on-open sweep applies that dismissal. The local notification is scheduled only when the phone is the device winner.
- Complications and the Smart Stack row (AC 81) stay deferred.

Open: nothing for Ben. The earlier question about saying clips are AI-generated is unrelated and stays out of this file.
