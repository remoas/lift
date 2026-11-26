# Lift · phase 1 design spec (iPhone, lifting only)

**Status:** CDO draft, 26 Nov 2026. Drafts only. Nothing is built for TestFlight, submitted or published without Ben's own yes.
**Approval to start:** Ben, 6:38am Bermuda time, 26 Nov (relayed by Grok Bot): "Yes, CDO and the iOS Developer can start building Lift".
**Plan:** https://cursor.com/canvas/store-4a287fb7-f67e-49e6-9d24-b3adafe89952/f7f4236a-cf74-48f6-88a4-2ef8558ceaa7
**Stack (from the iOS Developer):** native SwiftUI, iPhone, **iOS 17** deployment, SwiftData local-first, CloudKit private backup, HealthKit write. Zoom transitions are gated for iOS 18+; the target stays 17 (spec §8).
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
Tab bar with three tabs: **Today**, **History**, **Routines**. Settings is a gear (44 pt) top-right on Today, presented as a sheet. The active workout is a full-screen cover over the tabs. "Close" minimises it to a bar above the tab bar ("Push · 18:42 · Resume"), so a workout is never lost. Exercise detail is pushed from any exercise name (Today, Workout header long-press/tap on name, Finish, History, Routines). Shared element transitions (spec §8) apply to Start/Resume, exercise push and the PR banner. Close and an interactive drag-down on the workout minimise; they never dismiss or discard the workout (AC 13).

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
     - Then "Add exercise" (text button), then the row **"Default rest for new exercises  2:00 ▾"** (1:00–5:00 in 15 s steps).
     - **Rest belongs to the exercise.** This default only fills exercises that have no rest yet: new picks and custom exercises. It never overwrites an exercise's existing rest. Changing it shows no prompt and changes nothing already set.
     - An exercise's rest is edited from the workout "•••" menu → Rest, from the set editor's "Rest for {Exercise}" row, or in exercise settings (§3.8). Every route writes the same `Exercise.restSec`.
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
- Primary: **Start {Routine}**, pinned above the tab bar. The suggestion is only a suggestion. On iOS 18, Start and Resume zoom from the Today workout source into the cover (spec §8). There is no new card chrome.
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
- Nav: Close (minimise) · title "Push" with elapsed time below (`caption`, monospaced digits) · **"•••"** workout menu (44 pt, textSecondary) · **Finish** (semibold accent text).
- The workout "•••" menu holds Add exercise · Edit today · **Discard workout** (destructive, red, last, after a divider).
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
- **Exercise menu "•••"** (44 pt, trailing the exercise name, textSecondary) holds: Swap exercise · Add set · Rest ({m:ss}) · Edit today (reorder) · Remove exercise (destructive). Swipe left on the exercise header also removes it.
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
  - With sets left, Finish goes **straight to the summary**, with no alert (`25-finish-sets-left`). See §3.6.
- **No confirm alerts anywhere in Lift.** Ben's rule is undo toasts, not confirm popups.
- **Discard workout** (from the workout "•••" menu) has no alert. It closes the workout and returns to Today, with the toast "{Routine} discarded · **Undo**" for 5 s (`26-discard-toast`). Undo reopens the workout exactly as it was: ticked sets, current set, elapsed time and rest. After 5 s, or on the next action, the workout and its sets are deleted, nothing reaches Health, and the rotation doesn't move.
- **Close** always minimises and never asks anything, even with nothing ticked. An interactive drag-down, pinch or edge-swipe on the workout does the same (spec §8). None of these dismiss or discard the workout.

### 3.4 Set editor sheet (`05-set-editor`)
- Medium detent and a grabber. The workout stays visible behind a scrim.
- Title "Bench Press, set 3" (`title`) with "Last time 185 × 7" (`secondary`).
- A **lb | kg** segmented control, top-right, sets the unit *for this exercise* (it writes unitOverride; the global default lives in Settings). Switching converts the shown value to the nearest loadable weight in the new unit. It never rewrites saved sets.
- **Weight:** − [**190** lb] +. The steppers are 64 pt circles, each step is the exercise's plate step (default 5 lb / 2.5 kg), and holding repeats at 8 Hz after 0.4 s. The number has *the bar* under it. Tapping the number opens a decimal keypad (no dials, ever).
- Plate line under it: "45 bar, then 45 + 25 + 2.5 a side". For dumbbell or machine equipment it hides. If the weight isn't loadable, it reads "Closest you can load: 187.5".
- "Working set ▾" menu, right of the Weight label: Warm-up / Working / Drop / Failure.
- Row "Rest for {Exercise}  {m:ss} ▾" (48 pt) under Reps edits the exercise's rest (`Exercise.restSec`), and it applies from this set on.
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
- Motion and haptic: the banner uses `matchedGeometryEffect` from the just-logged set's number (spec §8), `springBanner` and a success haptic when it appears (not on dismiss). It stays 4 s, a swipe up dismisses it back toward the set, and a tap opens exercise detail. When two bests land within 4 s, the second replaces the first in place, with no stacking.
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
  - before Done: "Saves to Apple Health when you tap Done" (or the first-time ask). The save runs at Done.
  - error (after Done): a 5 s toast on Today, "Couldn't save to Apple Health. Your workout is safe in Lift." No inline Try again. `14-health-error` is that toast on Today (iOS Developer, c6b43e1, agreed by CDO 26 Nov);
  - denied: "Apple Health is off for Lift. Turn it on in Settings." (opens Settings).
- **Sets left** (`25-finish-sets-left`), with no alert:
  - Lede: "**{n} sets not logged**, so they won't be saved. Everything you ticked is." (singular: "1 set not logged, so it won't be saved.")
  - Directly under it is an accent text button, **Back to workout** (44 pt). It reopens the workout with the unlogged sets intact, the elapsed time still running, and the summary discarded.
  - On Done, the unlogged sets are dropped, and volume and comparisons count logged sets only.
- **Routine changed** (`20-finish-changed`): when a routine workout differs from its routine (exercise added, swapped, removed or reordered, or a set count changed), show one switch row above the buttons:
  - Label: "Update {Routine} routine with today's changes". **Off by default.**
  - Secondary line: a plain-language diff of at most 2 lines, e.g. "Machine Chest Press instead of Incline Dumbbell Press. Dips removed."; past that, "…and 2 more changes".
  - Turning it on rewrites the routine when you tap Done. Weights and reps are never written into the routine, only exercises, order, set counts, rep ranges and rest.
  - No changes, no row.
- **Blank workout** (`21-finish-blank`): hero "Workout, done.", lede "{n} exercises, **{volume}** moved. Your rotation still has **{Next}** next.", and a list of exercises with sets and the top set. Instead of the update switch, there's one switch row, **"Save as routine"**, off by default, with "Keeps these {n} exercises, their order and sets."
- Turning it on (`27-finish-save-routine`) shows an inline text field directly under the switch: label "Routine name", prefilled "**{Weekday} workout**" (e.g. "Saturday workout"), focused with the text **selected**, so typing replaces it. Helper: "Leave it empty to keep “{Weekday} workout”."
  - An empty field falls back to the prefill.
  - A name already in use gets " 2" appended. No alert; the helper reads "Saved as “Saturday workout 2”."
  - Return or Done saves. There's no separate Save button and no alert.
  - The field scrolls above the keyboard, and Done stays reachable above it.
- Primary **Done** → Today (the rotation advances per §3.2). Secondary "Add a note".

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

### 3.8 Exercise detail (`08-exercise`, `16-exercise-empty`, media header `24a`–`24e`)
- **Media header** (optional; only when the exercise has media). It's inset 20 pt each side, radius 16, at **3:2** (350 × 233 pt on a 390 pt screen), and never taller than 4:3. It sits under the nav, above the name. The background is `bgSunken`, and media is aspect-fill, centred. Opening the screen from a row uses the zoom in spec §8. The header fades in at this final size; list rows do not grow a thumbnail.
  - **Video** (`24a-media-video`): a muted loop that autoplays only when Reduce Motion is off and Low Power Mode is off.
    - There's **no audio, ever**: the audio track is stripped or the player is muted, and it never takes over the audio session, so Ben's music keeps playing.
    - Play/pause is a 44 pt glass circle (20 pt glyph, `.ultraThinMaterial`), bottom-left at 10 pt inset. Tapping the media also toggles. VoiceOver: "Pause demonstration" / "Play demonstration".
    - It pauses when scrolled off-screen or when the app backgrounds.
  - **Stills** (`24b-media-stills`): a Start / End pair. A glass segmented pill sits bottom-centre ("Start" | "End", 44 pt tall, each segment ≥ 64 pt). Tapping the image toggles, and a horizontal drag crossfades between the two (scrub; it snaps at release). Selection haptic on change. Default: Start.
  - **Reduce Motion** (`24c-media-reduce-motion`): no autoplay. It shows the **End** still with a glass "▶ Play" pill (44 pt), bottom-left. Tapping plays the loop once, through a crossfade only, then rests on the End still. With stills only, it shows the pair as above, with crossfades.
  - **Loading** (`24d-media-loading`): a `bgSunken` box at the final 3:2 size, so the layout never jumps. A soft shimmer runs for at most 1.2 s per cycle, and under Reduce Motion it's static. After 8 s with no media, the header collapses as if there were none.
  - **No media** (`24e-media-none`): the header **collapses entirely**. No placeholder box, no icon, no "Add media". The screen is identical to `08-exercise`.
  - The **e1RM chart stays above the fold** on iPhone 16 (390 × 844) at default text size. With the header, the range control moves under the chart, and the chart's bottom edge sits at ≤ 780 pt.
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
| Exercise | once / never; no media: header collapses (`24e`) | media skeleton (`24d`); chart skeleton line if >300 ms | — | new best dot |
| History | empty copy | — | — | — |
| Settings | Health "Not set up" | — | iCloud off copy | backup time |
| Choose workout | only one routine: the list still shows Blank | — | — | starts immediately |
| Exercise picker | no recents: the section is hidden; no results: only the Create row, with "No match in your library" above it | — | create failed (duplicate name): "You already have {name}." | sheet closes, exercise appears with a 0.2 s highlight |
| Edit today | one exercise: the remove control stays, and removing the last one leaves "Add your first exercise" | — | — | undo toast |
| Finish | no changes: no switch; blank: Save as routine switch + inline name (`27`); sets left: "{n} sets not logged" + Back to workout (`25`) | — | routine update failed: "Couldn't update Push. Today's workout is saved." | "Push routine updated" toast on Today |

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
24. Visual QA: the developer sends simulator screenshots of all 35 frames in light and dark (iPhone 16, default text size) and the set row at AX3, and CDO signs off before Ben sees a TestFlight request.

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

### No alerts, rest on the exercise, media header (decisions sent to the iOS Developer, 7:14am 26 Nov, against remoas/lift @282f09f)
44. There are no confirm alerts or popups anywhere in the app. Every destructive or lossy action is immediate with a 5 s undo toast, or reversible in place (`Back to workout`).
45. Finish with unlogged sets goes straight to the summary. The lede reads "{n} sets not logged, so they won't be saved. Everything you ticked is." and a 44 pt **Back to workout** text button reopens the workout intact. On Done, unlogged sets are dropped and never reach Health or the comparisons.
46. **Discard workout** is the last, destructive item in the workout "•••" menu. With no alert, it returns to Today with "{Routine} discarded · Undo" for 5 s. Undo fully restores the workout. Otherwise it's deleted, the rotation doesn't move, and nothing reaches Health. Close only minimises.
47. Save as routine (blank workouts) is a switch, off by default. On, it shows an inline field prefilled "{Weekday} workout", focused with the text selected. Empty falls back to the prefill, a duplicate gets " 2", and there's no alert or extra Save button.
48. Rest is stored on the exercise (`Exercise.restSec`). The setup and build "Default rest for new exercises" fills only exercises without a rest and never overwrites. Rest is editable from the exercise "•••" → Rest, the set editor's "Rest for {Exercise}" row, and exercise settings, and all three edit the same value.
49. The exercise media header is inset 20 pt, radius 16, 3:2, never taller than 4:3, and shown only when media exists.
50. Video is a muted loop with no audio track or session, never interrupts other audio, and has a 44 pt play/pause plus tap-to-toggle. It pauses off-screen and in the background.
51. Stills show as a Start/End pair with a 44 pt segmented pill, tap-to-toggle, and drag-to-scrub crossfade.
52. Under Reduce Motion, nothing autoplays: it shows the End still with a 44 pt "Play" pill. The loading skeleton is static under Reduce Motion and shimmers otherwise, at the final size with no layout jump.
53. With no media, the header collapses completely (no placeholder), and the screen matches `08-exercise`.
54. With a media header, the e1RM chart is fully visible without scrolling on iPhone 16 (390 × 844) at the default text size.

### Shared element transitions (26 Nov, drafts only; iOS 17 target stays)
55. The deployment target stays **iOS 17**. Zoom presentations are wrapped in `if #available(iOS 18, *)` and use `.navigationTransition(.zoom(sourceID:in:))` plus `matchedTransitionSource`. On iOS 17, Start/Resume uses the standard full-screen cover and exercise detail uses the standard push (including the system edge swipe). `matchedGeometryEffect` for the PR banner and the minimised workout bar works on 17 and is not gated. Do not bump the target in this work.
56. **Today → workout** (iOS 18): the Today workout source (the hero through “Today’s lifts”, no new card chrome and no card grid) is tagged `LiftTransitionID.workout(id)` and zooms into the full-screen workout cover under `springZoom`. “Push” morphs from the Today hero to the workout nav title; *the bar* under the Today name fades out and does not travel (the workout title has no bar). Exercise names in the list fade to the workout headers. The lede, week dots, Start / Other routine / Blank workout, tab bar and settings gear fade out; Close, elapsed time, Finish, •••, set rows, notes and rest fade in. Other routine zooms from the chosen sheet row; Blank workout from the Blank control; Resume from the same Today source, or from the mini bar when that’s what’s showing. The source and destination share one stable UUID (reserve the `Workout.id` before presenting).
57. Close, an interactive drag-down, a pinch, and an edge-swipe on the active workout **minimise** it, the same as Close. They follow the finger, are interruptible, and settle with `springZoom` (no bounce). Released early, the workout snaps back. They never dismiss or discard the workout and never write to Health or move the rotation. The mini bar cannot morph out of a `fullScreenCover`, so for phase 1 it **slides in** rather than using `matchedGeometryEffect`: it settles with `springZoom` and no bounce; the workout title and elapsed time crossfade into the bar text (“Push · 18:42 · Resume”); the bar appears as the cover finishes dismissing, never before, and Today must not flash empty underneath. Resume is the reverse: a standard cover presentation, or the iOS 18 zoom from the bar if the bar is tagged as a `matchedTransitionSource`. Discard (and only Discard) may use the reverse zoom back to Today, because the workout is actually ending.
58. **Exercise row → detail** (iOS 18): the tapped row is tagged `LiftTransitionID.exercise(exerciseId)` and zooms into the pushed detail under `springZoom`. The name morphs from the row (`exercise`) to the detail hero. Meta (“4 sets · last 185 × 8”, or the workout header meta) crossfades to the eyebrow and lede. The media header, when there is media, **fades in at its final geometry** (3:2, inset 20, radius 16) — rows do not gain a thumbnail. Video does not autoplay until the transition has finished; play/pause or the Start/End pill fades in after it settles. The chart, bests, notes and settings fade in and do not move. The source chrome (tab bar, or the workout nav and rest bar) fades. Swipe-back from the edge, the interactive pinch or drag-down close, and the back button all reverse the zoom: the gestures follow the finger and are interruptible; the back button plays the reverse with `springZoom` and no bounce. On iOS 17 this is a standard push. The same IDs are used from Today, the workout, Finish, History and Routines, including the no-media empty state.
59. **PR banner** (iOS 17+, `matchedGeometryEffect`, same pattern as the filter chip that grows into a sheet): the set row **stays put**. The ring fills and the “Best” tag appear with `springTick` as already specified. A matched copy of the today’s number (`LiftTransitionID.prValue(setId)`) lifts into the banner’s “{w} × {r}”; the banner container (`LiftTransitionID.prBanner(setId)`) expands from that value’s bounds (row radius 14) to the banner (radius 18, 12 pt side insets, under the nav) with `springBanner`. “New best” and the why line fade in once the number has landed; *the bar* then draws under the banner number with `barDraw` and never appears on the set row as well. The success haptic fires when the banner starts to appear, not on dismiss. Auto-dismiss at 4 s, or a swipe up, reverses the morph back toward the set (the Best tag and accent ring stay). The swipe follows the finger. A second best within 4 s replaces the first in place: copy crossfades, the number morphs if it changed, no stack. A tap still opens exercise detail (§3.5). Put `springBanner` on the existing filter-chip-to-sheet morph as well, so in-place shared elements share one spring.
60. Under **Reduce Motion**, all three moments (and minimise / Resume) are a `fadeReduced` crossfade only (0.15 s, `.easeInOut`), with no translation, scale or matched morph, and no bounce. Interactive dismiss is allowed but does not scale or drag the surface; it crossfades on commit. Media still follows AC 52 (no autoplay).
61. Visual QA for this delta ships in the **same pass as AC 24**, after the first free GitHub / macOS CI run: screen recordings on iPhone 16, default text size, at normal speed (light and dark) and at Simulator Slow Animations (light), plus one Reduce Motion pass (light, normal speed). Record: (1) Start {Routine} Today → workout, Close to the mini bar, Resume from the bar; (2) an exercise row with a media header → detail, then swipe-back, and once with the back button; (3) a PR appear from a logged set, a swipe-up dismiss, and a 4 s auto-dismiss. CDO reviews the recordings with the AC 24 screenshots. Nothing goes to Ben as a TestFlight request without his own yes.

## 7. Decisions (resolved)
Ben, 6:47am 26 Nov, relayed by Grok Bot:
- **RESOLVED: Accent is Ember** (#C2410C light / #FF8A3D dark).
- **RESOLVED: Icon A** (Ember background, cream barbell): `icon/icon-a-ember.svg`. Use it in all builds; icon B is dropped.
- **RESOLVED: Rotation follows PPL order, and a missed day slides** to the next session. Nothing is skipped and there are no fixed weekdays.
- **RESOLVED: lb plates** (45 bar; 45, 35, 25, 10, 5, 2.5), and **dumbbells in 5 lb steps**.
- **RESOLVED: Ben's own exercises and reps, not seeded.** The quick setup is in §3.1.

Still open: nothing for Ben in phase 1. (Optional later, not a recommendation and not needed for this delta: bumping the deployment target to iOS 18 would drop the zoom gate. Phase 1 stays on iOS 17.)

## 8. Shared element transitions

Draft delta, 26 Nov 2026, 9:56am Bermuda time. Ben, via Grok Bot, asked for shared element transitions in Lift, pointing at [Expo’s post](https://x.com/expo/status/2125720045276029297) (it quotes a Reanimated “postcard” demo: a trip card’s photo, title and duration badge morph into a detail hero, the rest of the screen crossfades, and a drag or swipe follows the finger back to the list). That demo is Expo / React Native. This section is the native SwiftUI translation. Drafts only.

The idea we keep: one or two elements really move, everything else crossfades, large surfaces do not bounce, and a gesture is always interruptible. We do not import polaroid chrome, card grids or horizontal paging between workouts (AC 19 still holds). *The bar* and the Ember rules in DESIGN.md stay as they are.

### 8.1 API and deployment

The target stays **iOS 17**. Do not raise it for this work.

```swift
enum LiftTransitionID: Hashable {
    case workout(UUID)       // Workout.id — reserve it before presenting
    case workoutMini(UUID)   // same Workout.id, minimised bar
    case exercise(UUID)      // Exercise.id
    case prBanner(UUID)      // SetEntry.id, banner container
    case prValue(UUID)       // SetEntry.id, the shared number
}

// One @Namespace on the ancestor that presents the cover / push, e.g. the Today root.
@Namespace private var liftNS
```

| OS | Push and full-screen cover | In-place (PR banner, mini bar) |
|---|---|---|
| iOS 18+ | `.navigationTransition(.zoom(sourceID:in:))` on the destination, `.matchedTransitionSource(id:in:)` on the source, animated with `springZoom` | `matchedGeometryEffect` (below) |
| iOS 17 | Standard `fullScreenCover` and standard `NavigationLink` push, including the system edge swipe. No homemade zoom. | `matchedGeometryEffect` — already available, not gated |

`navigationTransition(.zoom)` is supported on NavigationStack destinations, sheets and full-screen covers, so the workout can stay a cover over the tabs as in §2.

Optional, for Ben later and not a recommendation here: bumping the target to iOS 18 would drop the `#available` gate. Phase 1 stays on 17.

### 8.2 Springs, haptics, Reduce Motion

Tokens are in DESIGN.md. In short:

- **`springZoom`** — `.spring(response: 0.48, dampingFraction: 1.0)`, equivalently `.smooth(duration: 0.42)`. Large surfaces. Critically damped, **no bounce**. Used for the zoom and for the settle after a finger-led gesture. Never `.snappy`, and never a bounce greater than 0, on these surfaces.
- **`springBanner`** — `.spring(response: 0.42, dampingFraction: 0.82)`. Small in-place morphs: the PR banner, and the existing **filter chip that grows into a sheet**. Align that chip to this spring so in-place shared elements feel like one system. A slight settle is fine; no visible bounce.
- **`barDraw`** — unchanged. It only runs once the underlined number is in its final place.
- **`fadeReduced`** — `.easeInOut(duration: 0.15)`. Every shared transition under Reduce Motion, including minimise and Resume.

Gestures follow the finger while touched, are interruptible (a second gesture wins; a mid-flight zoom can be pulled back), and settle with the spring above. Released before the commit threshold, the surface returns with the same spring and no bounce.

Haptics: zooms add none of their own. The PR success haptic fires when the banner starts to appear, not when it dismisses. Tick, rest and steppers are unchanged.

### 8.3 Today workout source → active workout

Not a new card. The source is the typographic block from the hero (“Next up, *Push*”) through the “Today’s lifts” list. No extra fill, no extra stroke, no card grid. A 14 pt (`radiusButton`) clip is allowed *during the zoom only*, morphing to the full-screen cover (edge-to-edge, no corner radius at rest).

**Source.** The block tagged `LiftTransitionID.workout(id)` with `matchedTransitionSource`. Create or reserve the `Workout.id` before presenting so both sides share one UUID. Resume of an in-progress workout uses that workout’s existing id.

**Destination.** The full-screen workout cover, with `.navigationTransition(.zoom(sourceID: .workout(id), in: liftNS))`.

**What morphs**

- The routine name “Push”: Today hero (`display`, with *the bar* under it) → workout nav title (`body` / semibold title, no bar). The type size may crossfade if a live interpolation looks mushy.
- The source block’s bounds and, mid-flight only, its corner radius, expand to the cover.

**What crossfades**

- Out: the weekday eyebrow, the lede, week dots, “Today’s lifts” heading, each row’s “{n} sets · last {w × r}”, the Start (or Resume) button, Other routine, Blank workout, the tab bar, the settings gear, and *the bar* under the Today name. The bar does not travel onto the workout title (the workout screen has no bar; AC 6 still holds).
- In: Close, elapsed time, Finish, the workout •••, per-exercise meta, notes, set rows, column heads and the rest bar (if rest is already running, e.g. Resume).

**What stays put / does not animate**

- Status bar.
- Exercise names in the Today list may fade rather than try to track into the workout headers, whose positions differ; do not tween them across a messy path.
- On iOS 17, nothing zooms; the standard cover presentation is used.

**Other entry points**

- Other routine: the chosen row in the “Choose a workout” sheet is the source, same `workout(id)`.
- Blank workout: the Blank workout control (Today or the sheet’s last row) is the source. The destination title “Workout” fades in; there is no name to morph and no lifts list.
- Empty suggested day: there is no Start, so this zoom is not used until a Start or Resume exists.

**Dismiss and Close**

- **Close**, an **interactive drag-down**, a **pinch**, and an **edge-swipe** on the workout all **minimise**, the same as Close. They follow the finger. They never dismiss the cover in a way that would lose the workout, and they are not Discard. Released early, the workout snaps back with `springZoom` and no bounce.
- The mini bar cannot morph out of a `fullScreenCover`, so for phase 1 it **slides in** rather than using `matchedGeometryEffect`. It settles with `springZoom` and no bounce. The workout title and elapsed time crossfade into the bar text (“Push · 18:42 · Resume”). The bar appears as the cover finishes dismissing, never before, and Today must not flash empty underneath. Resume from that bar is the reverse: a standard cover presentation, or the iOS 18 zoom from the bar if the bar is tagged as a `matchedTransitionSource`. Resume from Today’s Resume button uses the §8.3 zoom (iOS 18) or the standard cover (iOS 17).
- **Discard** is the path that actually ends the workout. It may reverse-zoom back to the Today source (iOS 18) and then show the existing undo toast. iOS 17: standard dismiss plus the toast.

**Haptic.** None added for Start, Close, Resume or Discard.

**Reduce Motion.** `fadeReduced` only, both ways, including minimise.

### 8.4 Exercise row → exercise detail (media header included)

**Source.** The tapped row — a Today lifts row, a workout exercise header (name, not the set rows), or the matching row on Finish, History or Routines — tagged `LiftTransitionID.exercise(exerciseId)` with `matchedTransitionSource`.

**Destination.** The pushed exercise detail, with `.navigationTransition(.zoom(sourceID: .exercise(id), in: liftNS))`. Same IDs from every entry point, including `16-exercise-empty` and `24e` (no media).

**What morphs**

- The exercise name: row (`exercise`) → detail hero. Type size may crossfade if a live interpolation looks mushy.

**What crossfades**

- Row meta (“4 sets · last 185 × 8”, or “6–8 reps · 2:30 rest”) → the detail eyebrow (“Barbell · lb”) and lede.
- **Media header:** fades in already at its final geometry — **3:2, inset 20 pt, radius 16**, never taller than 4:3, `bgSunken`, aspect-fill. There is **no source thumbnail** and we do not add one to the rows. Video does not autoplay until the transition has finished. The play/pause control, or the Start/End pill, fades in after the settle. Loading still uses the final-size skeleton (AC 52). With no media, the header stays collapsed (AC 53) and only the name plus the rest of the screen participate.
- Chart, range chips, bests, notes, history and settings fade in and do not move.
- Source chrome fades out: the tab bar, or the workout nav, set list and rest bar.

**What does not animate**

- Status bar.
- No invented image flying out of a text row.
- *The bar* is not used on this screen unless a later state introduces one; do not draw one during the transition.
- On iOS 17, standard push only.

**Dismiss**

- Edge swipe-back, the iOS 18 zoom’s interactive pinch or drag-down close, and the back button all reverse the zoom to the same source row.
- Gestures follow the finger and are interruptible. Released early, the detail snaps back with `springZoom` and no bounce.
- The back button plays the reverse non-interactively, same spring, no bounce.
- iOS 17: the system pop, including the edge swipe.

**Haptic.** None added.

**Reduce Motion.** `fadeReduced` only. Media follows AC 52 (End still, no autoplay).

### 8.5 PR banner (appear and dismiss)

This one stays inside the workout view, so `matchedGeometryEffect` is the right tool, and it works on **iOS 17**. Use the same pattern as Ben’s **filter chip that grows into a sheet** (the matchedGeometryEffect you already use), and drive both with `springBanner`.

**Source.** The just-logged set’s today value (“205 lb × 5”). The set row stays in place: the ring fills and the “Best” tag appear with `springTick`, as already specified. The ring does not fly up into the banner.

**Destination.** The PR banner in §3.5 (`bgRaised`, radius 18, 12 pt side insets, under the nav).

**Matched IDs**

- `LiftTransitionID.prValue(setId)` — the number, source today-value to the banner’s “{w} × {r}” (`title`). Use a matched copy so the row’s own number can stay put (or crossfade in place to the Best-tagged value) while the banner number lifts from that origin.
- `LiftTransitionID.prBanner(setId)` — the banner container, expanding from the value’s bounds (current-set row radius 14) to the banner.

**What morphs**

- The number, including tabular figures, from the set value to the banner number.
- The container shape and corner radius, 14 → 18.

**What crossfades**

- “New best” and the why line fade in once the number has landed.
- *The bar* is not a shared element. After the number is in place, it draws under the banner number with `barDraw` (0.12 s delay, then 0.28 s). It must not also sit under the set row at the same time (one bar per screen).

**What stays put / does not animate**

- The set row’s layout, the rest bar, and the workout nav.
- The ring stays in the row and only does its existing fill.
- First sessions stay quiet: no banner, so no morph (§3.5).

**Dismiss**

- Auto at 4 s, or a swipe up, reverses the morph: the container and number contract toward the set, the label and why line fade, *the bar* fades (it does not undraw in reverse). The row keeps the Best tag and the accent ring.
- The swipe follows the finger and is interruptible. Released early, the banner settles back with `springBanner`.
- A second best within 4 s replaces the first in place: no stack, copy crossfades, the number morphs with `prValue` if the figures changed.
- A tap still opens exercise detail, using §8.4 from the banner (the banner’s name + number is a valid source for `exercise(id)`; the banner dismisses as the detail zooms).

**Haptic.** `.notification(.success)` when the banner starts to appear. None on dismiss, none on a mid-flight replacement.

**Reduce Motion.** The banner and its copy fade with `fadeReduced` only, no drop, no scale, no matched morph. The ring may still fill as a crossfade of the check (existing Reduce Motion rule).

### 8.6 Out of scope

No shared transition for the set editor sheet (system sheet), the exercise picker, Settings, Finish → Today, or paging between workouts. The set editor, rest bar and tick motion stay on the tokens they already use.


### Follow-ups agreed with the iOS Developer (26 Nov, against remoas/lift @4f14a06)
- Health saves at Done, and its failure is a Today toast (see §3.6). Frames `07`, `20` and `21` are captured on the summary before Done.
- "Add a note" is an inline field, not an alert.
- Exercise detail (`08`, `16`, `24a`–`24e`) has **no "Edit" button** in its nav bar. It was a mock leftover. The screen is read-only history, and rest, swap and remove live in the workout "•••" menu. Leave the trailing nav item empty.
