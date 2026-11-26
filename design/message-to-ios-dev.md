Hi, CDO here with the Lift phase 1 design draft. It's ready for you to build against. It's drafts only: no TestFlight, App Store or any upload without Ben's own yes.

Ben's approval to start (6:38am Bermuda time, 26 Nov, relayed by Grok Bot): "Yes, CDO and the iOS Developer can start building Lift".

**Files** (all in /workspace/lift/design/)
- spec.md: screens, flows, copy, states and 24 acceptance criteria (§6)
- DESIGN.md: colour assets (hex, light/dark, Color asset names), SF Pro text styles, spacing, radii, motion and haptics
- mock.html: 27 iPhone frames in light and dark (00-board.png shows them all)
- shots/: PNG renders `<nn-name>-<light|dark>.png`, plus 00-board.png and icon-draft.png
- icon/: two icon drafts, as SVG and 1024 PNG

**Please swap these native defaults now**
- AccentColor → `accent` (Ember #C2410C / #FF8A3D).
- Add the Color assets from DESIGN.md.
- Put `.monospacedDigit()` on every number.
- Make the 56 pt primary button style.
- Use a tick ring (not a checkbox or row tap) for logging.
Everything else can stay native: List, inset-grouped Settings, sheets, segmented controls, Swift Charts, tab bar.

**The parts that matter most**
1. One-tap logging: the current set's ring logs exactly what's shown, saves immediately with a UUID, runs the PR check and starts rest (AC 1, 3, 13).
2. Rest bar with the draining line and −15/+15/Skip, plus a local notification when backgrounded (AC 7).
3. PR banner: one at a time in priority order, a quiet first session, kg-internal comparisons so a unit switch can't fake a best (AC 9 to 11).
4. "The bar": a 4 pt Ember underline under one number per screen (AC 6).
5. Keep the set row, rest bar and PR banner as reusable views or view models for the phase 2 Watch and Live Activity. Ship no Watch or friends UI now (AC 22).

**Delta: flexibility** (Ben, 6:48am 26 Nov, relayed by Grok Bot then you: "The app shouldn't be too restricting I should be able to select whatever exercises I'm doing for that day. I might switch things up etc")
PPL is now only the suggestion. New specs are spec §3.2 (Today), §3.3 (workout editing), §3.6 (Finish), §3.12 (exercise picker) and §3.13 (Edit today). The new frames are 17 to 21, in light and dark.
- Today: one primary stays (Start {suggested}), with two quiet text buttons under it: **Other routine** (opens a "Choose a workout" sheet with every routine plus Blank) and **Blank workout**. The rotation follows what you actually did, and a blank workout doesn't move it.
- In a workout: "•••" per exercise (Swap, Add set, Edit today, Remove), swipe to remove, and Add exercise at the end of the list. Everything is for today only.
- Exercise picker sheet: search focused, Recent (last 8 with their last set), All A–Z, and Create “{query}”. Swap keeps the set count, rep range, rest and position, and prefills from the new exercise's own history.
- Edit today: a native List in edit mode with red remove controls and drag handles (44 pt each), plus lift-on-drag motion.
- Remove has no confirm dialog. Instead there's a 5 s undo toast ("Dips removed · Undo").
- Finish: when a routine workout changed, one switch, "Update Push routine with today's changes", **off by default**, with a plain diff. It writes exercises, order, sets and rep ranges only, never weights. A blank workout gets "Save as routine" instead.
- Data: history, "Last time", prefill and bests are keyed to the **exercise**, not the routine slot (AC 33). Please model SetEntry → exerciseId as the source of truth, with routineId only on the Workout.
New acceptance criteria are AC 25 to 33.

**Acceptance criteria:** spec.md §6, AC 1 to 43. AC 24 is visual QA. Please send me simulator screenshots of all 27 frames in light and dark (iPhone 16), plus the set row at AX3, before anything goes to Ben as a TestFlight request.

**Delta: own exercises** (Ben's answers, 6:47am 26 Nov, relayed by Grok Bot)
All five earlier questions are resolved (spec §7):
- Ember accent.
- Icon A in all builds (`icon/icon-a-ember.svg`).
- The rotation follows PPL order, and a missed day slides to the next session; nothing is skipped and there are no fixed weekdays.
- lb plates (45 bar; 45, 35, 25, 10, 5, 2.5) and dumbbells in 5 lb steps.
- His own exercises and reps, not templates.

What changes:
- **No routine seeding.** Please remove any seeded Push/Pull/Legs. The three routines are created empty. The exercise library stays as a pick list only: names, equipment, default rep range, plate step and aliases (AC 34).
- **Quick setup replaces first run** (spec §3.1, frames 02a–02e). It runs Welcome → Days → Build Push → Build Pull → Build Legs → Today, with one filled primary per screen.
  - On Days, tapping a tile advances after 0.25 s, with no Continue button. lb is preset there with an inline Change.
  - Each Build day:
    - Empty, it shows **Add exercises**, which opens the §3.12 picker in multi-select mode: Recent (hidden when empty), Common on {Day}, search, All exercises, Create, and the primary **Add {n}**.
    - Filled, each exercise has an inline "− 3 sets +" stepper and a rep-range menu, plus one "Rest between sets 2:00" default per day. The primary is **Next: {day}**, and on Legs **Finish setup**.
  - Skip is always available (nav, plus "Skip {Day} for now").
  - Typical setup takes ≤30 taps (AC 35 to 39, 42).
- **Today, empty suggested day** (frame 22): the lede "{Day} doesn't have any exercises yet…", the primary **Add exercises to {Day}** (opens the build screen as a sheet with Save), and Other routine · Blank workout still under it. The rotation never auto-skips an empty day (AC 40, 43).
- **Routines empty** (frame 23): each routine shows "No exercises yet" with an Add exercises text button, and the screen has no filled primary (AC 41). Routine edit reuses the build screen with Save.
- Removed frame: 02-first-run. New frames: 02a-welcome, 02b-days, 02c-build-empty, 02d-setup-picker, 02e-build-filled, 22-today-day-empty, 23-routines-empty, each in light and dark.
- §3.11: done, as I sent earlier. The indeterminate line only, with no count.

New acceptance criteria are AC 34 to 43.

**Open questions:** none for Ben in phase 1.
