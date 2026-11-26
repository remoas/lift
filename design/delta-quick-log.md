CDO here. This is the quick-log delta, written after Ben's 12:41pm direction (relayed by you): "All this onboarding is unnecessary. I don't need structure like this. I just need to accurately record what I've done so I know what I need to be aiming for next time". It's a draft, as usual. Your earlier QA items still apply to every screen that survives this change.

## 1. Opening screen = today's workout (replaces 01 / 22)
- On launch the app opens straight into a blank workout. There's no welcome, setup, permission prompt or account.
- Nav: the title is the weekday ("Thursday", `largeTitle`), with a trailing ••• (44 pt, `textSecondary`) holding Reorder and Discard workout.
- Empty state: one line in `textSecondary`, "Log what you lift. Lift remembers it for next time.", and one primary button, **Add exercise** (56 pt, Ember), which opens the picker (18).
- Picker: **Recents first**, sorted by when you last did each one, with "3 days ago" as meta. Recents are where "what did I do last time" lives, so there's no routine. Multi-select is allowed. Search and Custom stay the same.
- Once at least one exercise is added, Add exercise becomes a quiet text button under the last exercise, and **Finish** (Ember, nav trailing, beside •••) becomes the one primary.
- The elapsed time starts at the **first logged set**, not when the app opens. If nothing is logged, nothing is saved and nothing reaches Health.
- Stale workout: if you open the app more than 3 h after the last logged set, that workout finishes on its own. It saves and the Health save runs. A new blank workout opens with the toast "Saved Thursday's workout · View" (5 s).
- Tabs: two, **Log** and **History** (SF Symbols `figure.strengthtraining.traditional` and `clock`). Settings is a gear in the History nav.

## 2. Exercise block in the workout (changes 03 / 13)
Each exercise is a typographic block, not a card:
- **Name** (`headline`) plus ••• (Swap, Add set, Rest, Rep goal, Remove).
- **Last time** line (`subheadline`, `textSecondary`): "Last · Mon · 185×8, 185×7, 185×6". Show every set, separated by commas. If the line wraps, it can take two lines at AX sizes.
- **Target** line (`body`, `textPrimary`): "Beat it · **185 × 9**". *The bar* (4 pt Ember underline) sits under the target number, and this is the one number that matters on this screen. Only the current exercise's target carries the bar. The others show plain `textPrimary`.
- Set rows are **prefilled from last time**. The first unlogged set that could reach the target is prefilled **at the target** and marked with the current ring. As before, one tap logs a set, checks for a PR and starts the rest timer.
- When a set meets or beats the target, give a selection haptic and a quiet ✓ "Target hit" in `accent` on the target line. If it's also an all-time best, the PR banner (06) fires as before. Hitting the target alone never fires the banner.
- **First time** doing an exercise: there's no Last line, and the Target line reads "First time. Log what you do." with no bar. The first tap asks for a weight, as in 13.
- **Target rule** (yours, made visible):
  - The top set is the heaviest weight, and at that weight the most reps.
  - If those reps are below the **rep goal**, the target is the same weight × reps + 1.
  - If they're at or above it, the target is the next weight step × (goal − 2). Steps are 5 lb for barbell (lb plates) and 5 lb for dumbbells, or 2.5 kg.
  - Bodyweight is always reps + 1.
  - The rep goal defaults to **10** and can be changed per exercise from the ••• menu. It's a quiet inline stepper, not a setup screen.
- The target's weight and reps always come from the same rule as the prefill, so they can never disagree (the same lesson as the old lede and dots bug).

## 3. Finish (simplifies 07, 25)
- The lede says "{n} of {m} targets beaten." and lists the beaten ones, with their bests. Under that is the volume compared with the last time you did these same exercises. Health line as agreed. Then **Done**.
- 25 (sets left) and the Back to workout button stay. Drop the "next routine" line, the week count, the "Update routine" switch and Save as routine.

## 4. Frames to drop
02a, 02b, 02c, 02d, 02e (the whole setup flow), 09 and 23 (Routines), 17 (Other routine), 20 (finish changed), 21 (finish blank), 27 (save as routine), 22 (Today, empty day; it's replaced by §1's empty state), the rotation dots and lede in 01, 07's next-routine line, and History's "against the target" week grouping (keep the plain week grouping). In Settings, drop days per week and rotation. Units, plates, rest, Health, iCloud and Export stay. Transition flow 1 (Today → workout) and the mini bar (AC 57) are dropped, because the workout *is* the opening screen. Flows 2 and 3 stay.

## 5. Frames kept and updated
01 becomes `01-log-empty` (the §1 empty state), plus `01b-log-active` (two exercises, one current with the bar on its target). 03, 13 and 07 change per §2–3. 04, 05, 06, 08, 10, 11, 12, 14, 15, 16, 18, 19 (title "Reorder"), 24a–e, 25 and 26 are unchanged apart from your QA items.

## Acceptance criteria (replace AC 1–3, 9–11, 25–31, 42–43, 48, 57)
62. Cold launch shows the Log screen within 1 s, with no setup screens on first run or on any later launch.
63. With nothing logged, leaving the app or Discard saves nothing and writes nothing to Health.
64. Every exercise that has history shows the Last line (all sets, with the day) and a Target line. The target matches the rule in §2, and so does the prefilled set.
65. Only the current exercise's target has *the bar*. There's one Ember primary per state: Add exercise when empty, Finish when active.
66. Hitting the target shows ✓ Target hit with a selection haptic. The PR banner shows only for an all-time best.
67. A workout left for more than 3 h auto-finishes on the next open, with the toast.
68. Screenshots of 01-log-empty, 01b-log-active, 03, 13 and 07 in light and dark, plus 01b at AX3 (the Last line wraps, nothing truncates).
