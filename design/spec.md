# Lift · phase 1 design spec (iPhone, lifting only)

**Status:** CDO draft, 26 Nov 2026. Drafts only. Nothing is built for TestFlight, submitted or published without Ben's own yes.
**Approval to start:** Ben, 6:38am Bermuda time, 26 Nov (relayed by Grok Bot): "Yes, CDO and the iOS Developer can start building Lift".
**Plan:** https://cursor.com/canvas/store-4a287fb7-f67e-49e6-9d24-b3adafe89952/f7f4236a-cf74-48f6-88a4-2ef8558ceaa7
**Stack (from the iOS Developer):** native SwiftUI, iPhone, SwiftData local-first, CloudKit private backup, HealthKit write.
**Files:** tokens in `DESIGN.md` · frames in `mock.html` · renders in `shots/<nn-name>-<light|dark>.png` · icon drafts in `icon/`.
Mock numbers and exercise names are illustrative only. Frames after setup show what Ben's own routines might look like. Nothing in them is seeded, and the app never shows numbers it doesn't have.

## 1. Principles for this app
1. **The tick is the workout.** Every set arrives prefilled with what you did last time. If you matched it, one tap logs it, starts rest and checks for a best.
2. **Always show what to beat.** "Last time" sits beside every set, and every screen names one number to beat.
3. **One primary action per screen:** Today → Start Push · Workout → the current set's ring · Set editor → Log set · Finish → Done · Setup: Welcome → Get started, Days → the day tiles, each Build day → Add exercises (empty) or Next (filled).
4. **Quiet until it matters.** Ember appears only for the next action, a new best, and *the bar* (DESIGN.md signature 1). A new best is the loudest moment in the app.
5. **Suggested, never forced.** PPL is the suggestion. Any routine, a blank workout, or any change on the day is at most two taps away. Changes stay with that day unless Ben chooses to keep them.
6. **Designed for phase 2.** The set row, rest bar and PR banner are self-contained components that Watch, Live Activity and friends will reuse. Don't hard-code them to the phone layout. Keep a `source` (phone/watch) field on each set and leave room in the Today hero for a future "crew" line. Ship none of it now.

## 2. Navigation
Tab bar with three tabs: **Today**, **History**, **Routines**. Settings is a gear (44 pt) top-right on Today, presented as a sheet. The active workout is a full-screen cover over the tabs. "Close" minimises it to a bar above the tab bar ("Push · 18:42 · Resume"), so a workout is never lost. Exercise detail is pushed from any exercise name (Today, Workout header long-press/tap on name, Finish, History, Routines).

## 3. Screens

### 3.1 First run: quick setup (`02a`–`02e`)
Ben's 6:47am answer (relayed by Grok Bot): his own exercises and reps, **not templates**. No routine is pre-filled. Push, Pull and Legs exist as names only, and each starts empty. The exercise **library** stays as a pick list. There's no account and no permission prompt; Health is asked for at the first Finish (§3.6).

Five steps, one primary each. The back chevron sits top-left from step 1 on, and progress shows as an eyebrow ("2 of 4 · Push"), with no progress bar.
1. **Welcome** (`02a-welcome`).
   - Eyebrow "Lift". Hero "Your split, your *lifts*." (the bar under "lifts").
   - Lede: "Set up Push, Pull and Legs with the exercises you actually do. About two minutes, and you can change anything later."
   - Primary: **Get started**.
2. **Days** (`02b-days`). Eyebrow "1 of 4". Hero "How many days a week?"
   - Tiles 3 · 4 · 5 · 6, 64 pt tall. **Tapping a tile is the primary action:** it selects (with `springTick` and a selection haptic) and moves on after 0.25 s, so there's no Continue button.
   - Helper: "Tap one to carry on. Push, Pull, Legs in order; 6 runs each twice. Miss a day and the next one just slides."
   - Below it: "Weights in lb. **Change**" (inline accent, 44 pt target), which opens a lb | kg menu. Default lb.
3–5. **Build Push / Pull / Legs** (`02c-build-empty`, `02e-build-filled`). Eyebrow "{n} of 4 · {Day}". Hero "What's on *{Day}*?" (the bar under the day).
   - **Empty:**
     - Lede "Add the exercises you do on {Day}. Sets and reps go right next to each one."
     - Primary: **Add exercises**, which opens the picker in setup mode (below).
     - Secondary text button "Skip {Day} for now". **Skip** is also in the nav, top-right.
   - **Filled:** one block per exercise.
     - Name (semibold 17) with a drag handle (44 pt target).
     - Inline below it: a sets stepper "− {n} sets +" (44 pt segments, range 1–10, default 3) and a reps chip "{range} reps ▾".
     - The reps menu offers 3–5, 5–8, 6–8, 8–10, 8–12, 10–12, 12–15, 15–20 and Custom… (two number fields). The default comes from the library entry, e.g. 8–10.
     - Swipe left removes an exercise, with the undo toast.
     - Then "Add exercise" (text button), then the row "Rest between sets  2:00 ▾". This is one default for the day (1:00–5:00 in 15 s steps), and individual exercises can override it later in exercise settings.
     - Primary: **Next: {next day}**, and on Legs **Finish setup**.
   - Taps: Ben's typical setup is ≈ 1 + 1 + 3 × (1 + ~5 picks + 1 + 1) ≈ 26 taps. That's Get started, the day tile, then per day: open the picker, the picks, Add {n} and Next. Steppers and rep chips are only needed where the defaults are wrong.
- **Setup picker** (`02d-setup-picker`) is the §3.12 picker in multi-select mode.
  - Title "Add to {Day}", sub "Tap all you do. Order comes next."
  - The search field reads "Search or create".
  - Sections: **Recent** (hidden when there's no history, so hidden on a first install), then **Common on {Day}** (a curated 7–8 from the library, e.g. Push: Bench Press, Overhead Press, Incline Dumbbell Press, Dips, Lateral Raise, Triceps Pushdown, Cable Fly), then "All exercises", then Create "{query}".
  - Rows toggle a check ring. The primary reads **Add {n}**, and it's disabled while nothing is selected.
  - Picks appear in tap order and can be reordered on the build screen.
- **Finish setup** lands on Today. A skipped day stays empty, with no nagging. It's finished later from Today (§3.2, empty day) or Routines (§3.7, empty). If every day is skipped, Today shows the empty day for Push.
- Changing anything later uses the same build screen, opened from Routines → {Day} or Today → Add exercises to {Day} (as a full-height sheet, with the primary **Save**).

### 3.2 Today (`01-today`)
- Eyebrow: weekday ("Thursday").
- Hero: "Next up, *Push*" (the bar under the routine name). The rotation is next-in-line, not fixed weekdays.
- Lede, by case:
  - normal: "Your {ordinal} session this week. Last {Routine} was {weekday}, when you got **{w × r}** on {first lift short name}."
  - target hit: "That's {n} of {n} this week. Anything more is a bonus."
  - first ever: "Your first Push. Pick weights you could lift for the top of each range with good form."
  - back after 7+ days: "Welcome back. Last {Routine} was {date}; we've kept your numbers." Neutral, never a warning.
- Week marks: one dot per target session (3–6), not per weekday. Done = filled textPrimary, next = accent with an accentSoft halo, remaining = controlStroke ring. Then the text "{done} of {target} this week". The accessibility label reads the sentence.
- "Today's lifts": plain rows with the name and "{sets} sets · last {w × r}" (top working set). Tap → exercise detail.
- Primary: **Start {Routine}**, pinned above the tab bar. The suggestion is only a suggestion.
- Under it, two quiet accent text buttons (44 pt, no fill), side by side: **Other routine** · **Blank workout**.
  - *Other routine* opens "Choose a workout" (`17-choose-workout`, medium sheet). Title: "Choose a workout". Sub: "Your rotation picks up from whatever you do." It lists every routine with its last date, and the suggested one carries an accent "Next" tag. "Blank workout" is the last row, in accent, with "Add exercises as you go". Tapping a routine starts it straight away, with no extra confirm.
  - *Blank workout* starts an empty workout (title "Workout"). The screen shows "Add your first exercise" as the current action, and the picker opens straight away.
- Rotation rule: after you finish routine X, the next suggestion is the routine after X. A blank workout doesn't move the rotation, but it does count toward the weekly target.
- In progress: the primary becomes **Resume Push** and the lede becomes "{n} of {m} sets done, {time} in."
- **Suggested day is empty** (`22-today-day-empty`):
  - Lede: "{Day} doesn't have any exercises yet. Add the ones you do and you're ready to go."
  - There's no "Today's lifts" list. The week dots still show.
  - Primary: **Add exercises to {Day}**, which opens the build screen (§3.1) as a sheet with **Save**. After saving, the primary becomes Start {Day}.
  - "Other routine" and "Blank workout" stay under it, unchanged.
  - The rotation never skips an empty day on its own. Ben can pick another routine with Other routine.

### 3.3 Active workout (`03-workout`, `04-rest`, `13-first-workout`)
- Nav: Close (minimise) · title "Push" with elapsed time below (`caption`, monospaced digits) · **Finish** (semibold accent text).
- Per exercise: name (`exercise`), meta "6–8 reps · 2:30 rest", and an optional sticky note in italic `secondary` (the note lives on the exercise, not the routine).
- Column heads once per exercise, `caption`: "Last time", "Today".
- **Set row** (min 56 pt) has four parts: set number (`textTertiary`); last time "185 × 8" (`secondary`); today "185 lb × 8" (`setValue`, with the unit in secondary); and the tick ring (44 pt hit area).
  - *Upcoming:* value in textSecondary medium, ring in controlStroke.
  - *Current* (the first unticked set): row tinted accentSoft (radius 14, inset 12 pt each side), with a 34 pt ring in accent. **This ring is the screen's primary action.**
  - *Done:* the ring fills textPrimary with a check, and the value returns to textPrimary.
  - *Best:* the ring fills accent with a check, and an accent "Best" tag follows the value.
- **Tap the ring** = log the set exactly as shown. Haptic light, `springTick`. Then:
  1. Save immediately (SwiftData, with the set UUID).
  2. Run the PR check.
  3. Start rest.
  4. Move "current" to the next set. Prefill it with the value just logged if it differs from last time; otherwise keep last time's value for that set.
- **Tap the value** (weight × reps) = open the set editor (§3.4).
- **Long-press a row:** set type (Warm-up / Working / Drop / Failure), Delete set, Add note. **Swipe left:** Delete (with undo toast "Set deleted. Undo", 5 s).
- Under each exercise's last set is a quiet "Add set" text button (44 pt). It copies the last set's weight and reps.
- **Exercise menu "•••"** (44 pt, trailing the exercise name, textSecondary) holds: Swap exercise · Add set · Edit today (reorder) · Remove exercise (destructive). Swipe left on the exercise header also removes it.
- At the end of the list, a quiet accent text button **Add exercise** (44 pt) opens the picker (§3.12).
- **Today only.** Adding, swapping, reordering or removing exercises or sets changes this workout and never the routine. The routine changes only through the Finish switch (§3.6) or Routines.
- **Remove** is instant, with no confirm dialog. A toast (`19-reorder`) reads "{Exercise} removed" with **Undo**. It's textPrimary-filled, radius 14, 52 pt tall, sits above the rest bar or home indicator, and lasts 5 s or until the next action. Undo restores the exercise in its place, with any ticked sets. Removing an exercise that has ticked sets works the same way; its logged sets are dropped only once the toast expires. Removing a set works the same way: "Set 3 removed · Undo".
- **Untick:** tapping a done ring asks nothing. It unticks, removes the set's PR if it had one, and stops rest if that set started it.
- **First time on an exercise** (`13-first-workout`): Last time shows "—" and the current value reads "Add weight" in accent, with reps prefilled from the top of the range. Tapping the ring or the value opens the editor. Note line: "First time here. Pick a weight you could lift {repMax} times with good form."
- **Rest bar** (`04-rest`): it slides up from the bottom (bgRaised, hairline top) and holds:
  - the draining line;
  - the countdown (`timer`);
  - "Next 185 × 6";
  - chips −15 · +15 · **Skip** (Skip in accent).
  At 0 it gives the warning haptic, then the text "Rest's up · 185 × 6" for 3 s, and then it collapses. If the app is backgrounded, a local notification fires: "Rest's up. Bench Press, 185 × 6." Rest length comes from the exercise, and warm-up sets use the warm-up default.
- **Finish:**
  - With every set done, Finish becomes the primary (an accent-filled pill replaces the text button) and the ring area shows "All sets done".
  - With sets left, Finish asks in an alert: "Finish with {n} sets left? Unticked sets won't be saved." Buttons: **Finish** / Keep going.
- **Close with nothing ticked** asks "Discard this workout?" with **Discard** (destructive) / Keep.

### 3.4 Set editor sheet (`05-set-editor`)
- Medium detent and a grabber. The workout stays visible behind a scrim.
- Title "Bench Press, set 3" (`title`) with "Last time 185 × 7" (`secondary`).
- A **lb | kg** segmented control, top-right, sets the unit *for this exercise* (it writes unitOverride; the global default lives in Settings). Switching converts the shown value to the nearest loadable weight in the new unit. It never rewrites saved sets.
- **Weight:** − [**190** lb] +. The steppers are 64 pt circles, each step is the exercise's plate step (default 5 lb / 2.5 kg), and holding repeats at 8 Hz after 0.4 s. The number has *the bar* under it. Tapping the number opens a decimal keypad (no dials, ever).
- Plate line under it: "45 bar, then 45 + 25 + 2.5 a side". For dumbbell or machine equipment it hides. If the weight isn't loadable, it reads "Closest you can load: 187.5".
- "Working set ▾" menu, right of the Weight label: Warm-up / Working / Drop / Failure.
- **Reps:** − [**7**] +, steps of 1.
- Primary: **Log set** logs, ticks and starts rest in one go. Dismissing by swipe keeps the edited value without logging it.

### 3.5 PR banner (`06-pr-banner`)
- A new best is checked on every tick, against working sets only. There are four kinds, and the banner shows the single strongest in this order: **Heaviest** > **Estimated max** (Epley, reps ≤ 12) > **Most reps at this weight or heavier** > **Biggest set** (weight × reps).
- Banner (bgRaised, radius 18, 12 pt side insets, under the nav), with `role=status` and VoiceOver announcement:
  - "New best" (accent, semibold 15)
  - "Bench Press, *205 × 5*" (`title`, the bar under the numbers)
  - one line of why, in `secondary`. Copy by kind:
    - Heaviest: "Heaviest yet, up {Δ} from {old}. Estimated max is now {e1RM}."
    - Estimated max: "Your estimated max is now {e1RM}, up {Δ}."
    - Reps: "{reps} reps at {w}, {Δ} more than ever."
    - Biggest set: "Your biggest set of {exercise}, {volume}."
- Motion and haptic: `springBanner` and success haptic. It stays 4 s, a swipe up dismisses it, and a tap opens exercise detail. When two bests land within 4 s, the second replaces the first in place, with no stacking.
- The set row keeps the accent ring and a "Best" tag for the rest of the workout.
- **Quiet baseline:** an exercise's first session never shows a banner. Finish says: "First {Routine} logged. These are your numbers to beat."
- A unit switch can't fake a best: all comparisons run in kg internally, at full precision.

### 3.6 Finish summary (`07-finish`, `14-health-error`)
- Eyebrow "Thursday · 54 min · 19 sets". Hero "{Routine}, done."
- Lede by case:
  - bests: "Two new bests today, and **4% more weight moved** than last Push."
  - no bests: "Solid. **{n} of {m}** sets matched or beat last time."
  - first: "First Push logged. These are your numbers to beat."
- "New bests" rows: "Bench Press, *205 × 5*" (the bar on the top best only) with the why line. The section is hidden when there are none.
- "Against last Push" rows: "{volume} moved / Up from {old} on {weekday}" (or "Down from…", neutral, never red), then "{Next} is next / {done} of {target} this week".
- Health line:
  - "✓ Saved to Apple Health" (success);
  - first time: a "Save workouts to Apple Health" button that opens the system prompt, with "Not now" beside it;
  - error: "Couldn't save to Apple Health. Your workout is safe in Lift." plus Try again;
  - denied: "Apple Health is off for Lift. Turn it on in Settings." (opens Settings).
- **Routine changed** (`20-finish-changed`): when a routine workout differs from its routine (exercise added, swapped, removed or reordered, or a set count changed), show one switch row above the buttons:
  - Label: "Update {Routine} routine with today's changes". **Off by default.**
  - Secondary line: a plain-language diff of at most 2 lines, e.g. "Machine Chest Press instead of Incline Dumbbell Press. Dips removed."; past that, "…and 2 more changes".
  - Turning it on rewrites the routine when you tap Done. Weights and reps are never written into the routine, only exercises, order, set counts, rep ranges and rest.
  - No changes, no row.
- **Blank workout** (`21-finish-blank`): hero "Workout, done.", lede "{n} exercises, **{volume}** moved. Your rotation still has **{Next}** next.", and a list of exercises with sets and the top set. There's no update switch. The secondary text button **Save as routine** asks for a name (alert with a text field, default "Workout {date}") and saves the exercises, order and set counts.
- Primary **Done** → Today (the rotation advances per §3.2). Secondary "Add a note" (or "Save as routine" for a blank workout; "Add a note" then moves into the "•••" menu).

### 3.7 Routines (`09-routines`)
- Hero "Routines". Lede: "Push, Pull, Legs, then round again. **{n} days a week.**"
- One row per routine: name (`exercise`) with an accent "Next" tag on the next one, and the exercise list as one secondary sentence. Tap to edit the routine.
- Routine edit uses the §3.1 build screen (with **Save** as primary): drag to reorder, add from the library or create a custom exercise (no cap), and inline sets and rep range per exercise, with a rest default per day. Plate step and per-exercise rest live in exercise settings (§3.8).
- "Change days a week" opens the 3/4/5/6 tiles from setup.
- **No routines are seeded.** Push, Pull and Legs start empty. The exercise library (names, equipment, default rep range, plate step and aliases) is only a pick list.
- **Empty** (`23-routines-empty`):
  - Lede: "Push, Pull, Legs, then round again. **{n} days a week.** Add exercises to each whenever you like."
  - Each routine row shows its name (with the "Next" tag where it applies), "No exercises yet", and an accent text button **Add exercises** (44 pt).
  - The screen has no filled primary.
  - With some days filled, filled rows show their exercise sentence as in `09-routines`, and empty rows show "No exercises yet · Add exercises".

### 3.8 Exercise detail (`08-exercise`, `16-exercise-empty`)
- Hero is the exercise name, with eyebrow "{equipment} · {unit}".
- Lede: "Your estimated max is **239 lb**, up 21 since September." When it's flat for 3+ sessions: "Holding at 239 lb for 3 sessions." (The Stuck? nudge is phase 2.)
- Range: 1M · 3M · 1Y · All (default 3M).
- **e1RM chart** (Swift Charts `LineMark`):
  - one 2.5 pt textPrimary line;
  - no gridlines and no y-axis, only a hairline baseline;
  - the first value labelled at the start, and the latest point as an accent dot with an 18% halo;
  - x labels at the start month and "Today".
  - Scrubbing shows a lollipop with "{date} · {e1RM} from {w × r}" and selection haptics.
  - It plots the best e1RM per session (sets ≤ 12 reps).
- "Bests" rows: Heaviest, Estimated max, Most reps at {top working weight}, Biggest set, each with its value and date.
- Below: Note (editable, the same sticky note shown in the workout), then History (the last 10 sessions: date + sets as "185×8, 185×8, 185×7"), then Settings for this exercise (rep range, rest, plate step, unit: "Use default (lb)" / lb / kg).
- **Empty** (one session): "You've logged this once. Next time, you'll have a number to beat." The chart shows one dot. Bests text: "Bests appear after your second session, so day one never counts as a fake record."
- **Never logged:** "Not logged yet. It's in {Routine}."

### 3.9 History (`10-history`, `12-history-empty`)
- Grouped by week (Mon–Sun), with section label "This week · 3 of 6" and "Last week · 6 of 6".
- Rows: the routine name, then "{Thu 26 Nov} · {54 min}", then a trailing accent "{n} best(s)" when there are any. Tap for the workout detail, where you can edit sets after the fact (bests recompute).
- "+" in the nav back-logs a workout: pick the routine and date, then log as usual with no rest timer.
- Empty: "Your workouts land here once you finish one. Every set, every best, kept on this iPhone and backed up to iCloud." Text button "Go to Today".

### 3.10 Settings (`11-settings`; native inset-grouped list)
- **Units:** "Weights in" lb | kg; "Show the other unit too" toggle (adds a secondary line, e.g. "100 kg · 220 lb"). Footer: "Each set keeps the unit you logged it in, so switching never changes a record."
- **Bar and plates:**
  - Bar 45 lb (20 kg).
  - lb plates 45, 35, 25, 10, 5, 2.5.
  - kg plates 25, 20, 15, 10, 5, 2.5, 1.25.
  - Each is editable as a toggle list plus "Add plate".
- **Rest:** "Start rest after each set" toggle (on), "Working sets" default 2:00, and "Warm-up sets" 1:00.
- **Celebrate new bests:** banner and haptic toggles.
- **Data:**
  - Apple Health (On / Off / Not set up).
  - iCloud backup, showing the last backup time, or "Off: workouts stay on this iPhone only".
  - "Export as CSV", which opens the share sheet.
- About / version.

### 3.12 Exercise picker (`18-exercise-picker`)
- Large-detent sheet, titled "Add exercise" or "Swap {Exercise}".
  - Swap subtitle: "Keeps {n} sets of {range}. Today only."
  - Add subtitle: "Added to today only."
- The search field is focused when the sheet opens, matches as you type (prefix and contains, case and diacritic insensitive), and searches names and aliases ("RDL" → Romanian Deadlift, "OHP" → Overhead Press).
- Sections:
  - **Recent**: the last 8 exercises you logged, most recent first, each with "Last {w × r} · {date}".
  - **All exercises**: the exercise library plus your custom ones, A–Z, with "Not logged yet" when there's no history.
  - When the query has no exact match, the last row is an accent "Create “{query}”" with "A custom exercise, yours to name and set up". It opens a short form (name, equipment, unit default, rep range, rest) with **Add** as primary, and adds the exercise to today.
- Rows are 56 pt. Tapping a row adds or swaps immediately and closes the sheet. Add mode can add several at once: tapping a row shows a check and the primary becomes "Add {n}".
- **Swap** keeps the slot's set count, rep range, rest and position. Prefill comes from the *new* exercise's own last session ("Add weight" if it has none). Any ticked sets on the old exercise stay logged to the old exercise, and only the unticked ones move.
- **History and bests belong to the exercise**, never the routine slot. Bench Press done in a blank workout or in Push counts the same. "Last time" means the last time you did *that exercise*, in any workout.

### 3.13 Edit today (`19-reorder`)
- Opened from "•••" → Edit today, or a long-press on an exercise header.
- A native `List` in `EditMode.active`:
  - nav: **Add** (opens the picker) · title "Edit today" with "{Routine} · {elapsed}" · **Done** (semibold);
  - helper text: "Drag to reorder. Changes are for today only.";
  - rows of 60 pt: a red remove control (24 pt glyph, 44 pt target) · name with "{n} sets · {status}" ("done", "1 done", "swapped in") · drag handle (44 pt target).
- While dragging, the row lifts (scale 1.02, raised shadow, `springTick`) and there's a `.selection` haptic at each slot.
- Swipe-to-delete works here too. Every remove shows the undo toast.
- Done returns to the workout with the current set unchanged.

### 3.11 Loading (`15-restoring`)
Local-first, so normal launches show no spinner. Only a restore on a new iPhone shows a loading state:
- Hero "Bringing your workouts over".
- Lede "Restoring from iCloud. You can start a workout now; anything you log is kept."
- A thin indeterminate accent line under the lede (SwiftData + CloudKit only reports start and finish, so no count). The lede already says "Restoring from iCloud", so there is no second caption. Line and lede disappear when the import finishes.
- Skeleton lines for the lifts list.
Start stays available throughout. If the restore fails: "Couldn't reach iCloud. Your workouts will come over when you're back online." with Try again.

## 4. States checklist
| Screen | Empty / first run | Loading | Error | Success |
|---|---|---|---|---|
| Setup | each day empty → Add exercises; skip allowed | — | duplicate custom name: "You already have {name}." | Finish setup → Today |
| Today | suggested day empty → Add exercises to {Day} (`22`); first-ever lede; week dots all rings | iCloud restore (§3.11) | restore failed copy | target hit lede |
| Workout | first-time exercise row | — (local) | save failure: "Couldn't save that set. Try again." with the ring reverting | tick, PR banner |
| Set editor | "Add weight", keypad open | — | non-loadable weight copy | Log set |
| Finish | first-session lede | Health saving: "Saving to Apple Health…" | Health error / denied | saved |
| Exercise | once / never | chart skeleton line if >300 ms | — | new best dot |
| History | empty copy | — | — | — |
| Settings | Health "Not set up" | — | iCloud off copy | backup time |
| Choose workout | only one routine: the list still shows Blank | — | — | starts immediately |
| Exercise picker | no recents: the section is hidden; no results: only the Create row, with "No match in your library" above it | — | create failed (duplicate name): "You already have {name}." | sheet closes, exercise appears with a 0.2 s highlight |
| Edit today | one exercise: the remove control stays, and removing the last one leaves "Add your first exercise" | — | — | undo toast |
| Finish | no changes: no switch; blank: Save as routine | — | routine update failed: "Couldn't update Push. Today's workout is saved." | "Push routine updated" toast on Today |

## 5. Accessibility
- Dynamic Type to AX5. At accessibility sizes the set row stacks: the value is on line 1 with the ring trailing, and last time is on line 2. The steppers keep 64 pt, and the number scales via `@ScaledMetric`.
- VoiceOver labels:
  - Set row: "Set 3, last time 185 by 7, today 185 pounds by 7. Not done." The ring's action: "Log set".
  - Steppers: "Weight, 190 pounds. Adjustable".
- Every target is ≥44 pt. Text contrast is ≥4.5:1 and controls ≥3:1 (DESIGN.md). Done, best and errors are never shown by colour alone.
- Reduce Motion uses crossfades, and the rest line steps once per second instead of animating.

## 6. Acceptance criteria
1. Logging a set that matches its prefilled value takes exactly **one tap**, and that tap saves it, starts rest and runs the PR check.
2. A typical planned Push (6 exercises, 19 sets, all matched) takes **21 taps** from launch to Today again: Start + 19 ticks + Done, plus 1 for Finish if it isn't auto-promoted. No other screens appear.
3. Every set is prefilled from the same set number in the last session of that routine. On an exercise's first time, the row shows "Add weight" and reps at the top of the range.
4. "Last time" shows beside every set, and Today shows last time's top set for every lift.
5. Each screen has one primary action, as listed in §1.3. Ember fill appears on nothing else.
6. *The bar* appears at most once per screen, only on Today, the set editor, the PR banner and Finish. It draws in with `barDraw`.
7. The rest timer starts on tick, shows the draining line, and offers −15/+15/Skip (each ≥44 pt). At zero it gives a haptic, and a local notification if backgrounded. Warm-up sets use the warm-up rest.
8. The set editor has −/+ steppers at the plate step and a keypad on tap, with no picker wheels or dials anywhere. The plate line is correct for the configured bar and plates.
9. The lb|kg switch in the editor sets the per-exercise unit. Settings sets the global unit. Saved sets keep their entered value and unit. A unit change never creates or removes a best (unit test: log 100 kg, switch to lb, log 220 lb → no PR).
10. PR detection covers Heaviest, Estimated max (Epley, reps ≤12), Most reps at ≥ weight, and Biggest set, on working sets only. An exercise's first session sets baselines with no banner.
11. The PR banner matches §3.5 in copy, order, timing (4 s), haptic, swipe-to-dismiss and tap-to-detail. The set keeps a "Best" tag and an accent ring. VoiceOver announces "New best, Bench Press, 205 by 5".
12. Finish shows bests, volume against the last same routine, and the next routine with week progress. Health is asked for here, contextually, the first time only.
13. A workout is never lost. Each tick writes immediately with a UUID; Close minimises; force-quit mid-workout resumes on Today as "Resume Push".
14. Exercise detail shows the e1RM line chart as specified (no gridlines, accent latest dot, scrubbing), the four bests with dates, the note, history and per-exercise settings.
15. History groups by week with "{done} of {target}", and back-logging is possible.
16. Settings covers the global unit, the other-unit toggle, bar and plates for lb and kg, rest defaults, celebrations, Health, iCloud status and CSV export.
17. Every state in §4 is implemented with the exact copy in this spec, with no placeholder text or fake data.
18. Light and dark both use only the `DESIGN.md` assets, and the contrast pairs listed there hold.
19. Type uses SF Pro text styles only (single family), with `.monospacedDigit()` on every number. Hierarchy comes from weight, colour and space. There are no uppercase labels, stat strips or card grids.
20. Every tap target is ≥44 × 44 pt. Dynamic Type works to AX5 with the stacked set row, and nothing is truncated at the default size on a 375-pt-wide device.
21. Motion uses the DESIGN.md springs, and with Reduce Motion it's crossfade only. Haptics are as listed.
22. The set row, rest bar and PR banner are standalone views fed by a view model, with no phone-only layout assumptions, so phase 2 Watch and Live Activity can reuse the logic. No Watch or friends UI ships in phase 1.
23. The app icon is icon A (`icon/icon-a-ember.svg`, resolved by Ben at 6:47am) in all builds.
24. Visual QA: the developer sends simulator screenshots of all 27 frames in light and dark (iPhone 16, default text size) and the set row at AX3, and CDO signs off before Ben sees a TestFlight request.

### Flexibility (Ben, 6:48am 26 Nov: "The app shouldn't be too restricting I should be able to select whatever exercises I'm doing for that day. I might switch things up etc")
25. Today keeps exactly one filled primary (Start {suggested}). "Other routine" and "Blank workout" are unfilled accent text buttons, each ≥44 pt. Any routine or a blank workout starts in ≤2 taps from Today.
26. The rotation follows what was done: finishing X suggests the routine after X. A blank workout doesn't change the suggestion but does count toward the weekly target.
27. During a workout you can add, swap, reorder and remove exercises, and add or remove sets, through the "•••" menu, swipe, Add exercise and Edit today. All of it applies to that workout only, and the routine stays unchanged unless AC 30 is used.
28. The picker opens with search focused, shows Recent (last 8 with their last set) and All exercises, matches aliases, and offers Create “{query}” when nothing matches exactly. Tapping a row adds or swaps in one tap.
29. Swap keeps the set count, rep range, rest and position. It prefills from the new exercise's own history. Ticked sets stay with the old exercise.
30. At Finish, a changed routine workout shows one switch, "Update {Routine} routine with today's changes", **off by default**, with a plain diff. It never writes weights or reps. There's no switch when nothing changed, and blank workouts show "Save as routine" instead.
31. Removing an exercise or a set happens without a confirm dialog and shows an undo toast for 5 s. Undo restores the item in place with its ticked sets intact.
32. Edit today uses a native List edit mode with remove controls and drag handles (each ≥44 pt), lift-on-drag motion and selection haptics.
33. History, "Last time", prefill and bests are keyed to the exercise, not the routine slot. The same exercise in Push, in another routine or in a blank workout shares one history and one set of records (unit test: Bench in a blank workout beats the Push best → banner, and Push's next prefill uses it).

### Own exercises and quick setup (Ben, 6:47am 26 Nov, relayed by Grok Bot)
34. No routine is seeded. Push, Pull and Legs are created empty, and the library is only a pick list. No exercise appears in a routine unless Ben added it.
35. Setup is Welcome → Days → Build Push → Build Pull → Build Legs → Today. Each screen has exactly one filled primary. On Days the tile tap is the primary, and it advances after 0.25 s with no Continue button.
36. Units default to lb, with an inline "Change" on Days. The lb plates are 45, 35, 25, 10, 5, 2.5 on a 45 lb bar, and the dumbbell plate step is 5 lb.
37. Each build day uses the §3.12 picker in multi-select mode: Recent (hidden when empty), Common on {Day}, search, All exercises, and Create “{query}”. The primary reads Add {n} and is disabled at 0.
38. Each added exercise shows inline a sets stepper (1–10, default 3) and a rep-range menu (preset ranges plus Custom), each ≥44 pt. There's one rest default per day (2:00), and exercises can be dragged to reorder and swiped to remove with undo.
39. Any build day can be skipped (nav Skip, or "Skip {Day} for now"). Setup always finishes on Today, and skipped days stay empty with no nags or badges.
40. Today with an empty suggested day shows the lede in §3.2, the primary **Add exercises to {Day}**, and Other routine · Blank workout under it. After saving, the primary becomes Start {Day} with no relaunch.
41. Routines with empty days show "No exercises yet" and an Add exercises text button per routine, with no filled primary on the screen.
42. Ben's typical setup (3 days × ~5 exercises, default sets, reps and rest) takes ≤ 30 taps from first launch to Today.
43. A missed day slides: the suggestion is always the routine after the last one finished, whatever the calendar says. No day is ever auto-skipped, including empty days.

## 7. Decisions (resolved)
Ben, 6:47am 26 Nov, relayed by Grok Bot:
- **RESOLVED: Accent is Ember** (#C2410C light / #FF8A3D dark).
- **RESOLVED: Icon A** (Ember background, cream barbell): `icon/icon-a-ember.svg`. Use it in all builds; icon B is dropped.
- **RESOLVED: Rotation follows PPL order, and a missed day slides** to the next session. Nothing is skipped and there are no fixed weekdays.
- **RESOLVED: lb plates** (45 bar; 45, 35, 25, 10, 5, 2.5), and **dumbbells in 5 lb steps**.
- **RESOLVED: Ben's own exercises and reps, not seeded.** The quick setup is in §3.1.

Still open: nothing for Ben in phase 1.
