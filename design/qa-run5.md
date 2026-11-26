Hi, CDO here with visual QA on run5-main (72 stills, green macOS CI) and transitions-run1 (12 recordings). Drafts only, as usual.

The bones are in very good shape. Colour tokens match DESIGN.md on the samples I took (`bgCanvas` #FFFFFF / #0B0B0C, `accent` #C2410C / #FF8A3D, `accentSoft` #FCEDE5 exactly), primaries are 56 pt, *the bar* is 4 pt Ember, day tiles are 64 pt, and the media header is a true 3:2. Typography is quiet, there are no card grids or uppercase labels, tabs are SF Symbols, there are no confirm alerts and no Edit button on exercise detail, and the AX3 set row stacks the value and last time without truncating the numbers.

I haven't re-flagged toast chrome on 14/26, or 26 still showing the workout after Discard — noted as already fixed on the transitions branch. Your known gaps (flow 2 swipe-back, flow 3's second PR) are still missing from this tape; I haven't filed them as new Musts. I did update AC 57 and spec §8.3 for the phase 1 mini-bar slide-in (settle with `springZoom`, no bounce; title and elapsed crossfade into the bar text; bar appears as the cover finishes, never before, no empty-Today flash; Resume is the reverse cover, or an iOS 18 zoom if the bar is a `matchedTransitionSource`).

Annotated crops are in `/workspace/lift/design/qa-run5/`.

## Must fix

1. **`01-today-light/dark`** (also 14, 17). Lede reads “Session 3 of 6 this week.” Dots read “2 of 6 this week.” Spec §3.2 is “Your {ordinal} session this week.” plus “{done} of {target} this week.” Don’t put two different n-of-6 counts on the same screen — use the spec lede (“Your third session this week”) and keep the dots at `{done}`. Crop: `qa-run5/01-lede-vs-dots.png`.

2. **`07-finish-light/dark` and `20-finish-changed-light/dark`.** “3 of 6 this week” is clipped by the pinned 56 pt Done button. Scroll the finish content above the button, or give the pinned bar a safe top inset. Crop: `qa-run5/20-finish-clipped-and-missing-switch.png`.

3. **`20-finish-changed-light/dark`.** The “Update Push routine with today’s changes” switch is not on screen (AC 30). It should sit above Done, **off by default**, with a ≤2-line plain diff. Right now frame 20 is visually the same as 07 plus a set-count change.

4. **`02e-build-filled-light/dark`.** The “Default rest for new exercises  2:00” row is missing above Next: Pull (AC 48, and the mock). Crop: `qa-run5/02e-missing-default-rest.png`.

5. **`05-set-editor-light/dark`.** The sheet is missing the title “Barbell Bench Press, set 3” (`title`) and the **lb | kg** segmented control, top-right (§3.4). “Last time 180 × 7” has taken the title slot and sits tight under the grabber. The weight, *the bar*, plate line, rest row and Log set are all fine. Crop: `qa-run5/05-missing-title-and-units.png`.

6. **`18-exercise-picker-light`.** The official shot includes the iOS Keyboard QuickPath “Continue” coaching overlay, which covers the list and the Add {n} primary. Recapture; `18-exercise-picker-dark` (plain keyboard) is the right take. Crop: `qa-run5/18-keyboard-coaching-overlay.png`.

7. **`24c-media-reduce-motion-light/dark`.** The files are byte-identical to `24b-media-stills` (Start/End pill, Start selected). AC 52: End still, 44 pt “▶ Play” pill, no autoplay. Recapture under Reduce Motion. Crop: `qa-run5/24c-identical-to-24b.png`.

## Should fix

8. **`06-pr-banner-light/dark`.** The banner is the right shape (`bgRaised`, under the nav, *the bar* on “205 × 5”, Best tag and accent ring on the set) but it covers the exercise header. Keep the name and meta visible below it, as in the mock. Crop: `qa-run5/06-banner-covers-header.png`.

9. **Media header inset, `16`, `24a`–`24d`.** Aspect is 3:2 (measured 1.50) and radius looks like 16, but the side inset is **36 pt**, not `space5` 20 pt. Width is ~321 pt on a 393 pt screen; it should be 353 pt (390−2×20, or 393−2×20). Height scales with the 3:2.

10. **Flow 1 minimise, `flow1-today-to-workout-*-light` (e.g. slow ~67.6 s).** The slide-in itself is acceptable for phase 1: the bar arrives as the cover finishes, Today is not empty, and I don’t see a bounce. Two misses against the updated AC 57: (a) mid-dismiss, Today briefly shows the large **Resume Push** primary before the mini bar replaces it — title and elapsed don’t visibly crossfade into “Push · 0:13 · Resume”; (b) the Today lede says “0 min in” while the bar reads 0:13. Use the same clock. Crops: `qa-run5/flow1-mini-bar-mid-dismiss.png`, `qa-run5/flow1-mini-bar-strip.png`.

11. **`03-workout` nav (and 04, 06, 13, 26).** The workout ••• is a circled Ember control. Spec §3.3: 44 pt, `textSecondary`, like the quieter per-exercise •••. Ember stays on Close, Finish, the current ring and Skip.

12. **Exercise picker names, `02d-setup-picker`, `18-exercise-picker`.** Raw aliases are leaking into titles: “Incline Dumbbell Press · incline”, “Romanian Deadlift · romanian”. Keep aliases for search only.

13. **`13-first-workout-light/dark`.** “Add weight” in `accent` is right on the **current** set. Upcoming first-time sets should be `textSecondary`, not Ember on every row.

14. **`08-exercise`, `24a`–`24e` chart.** The latest accent dot and start value are good, but the x-axis is missing “Today” (spec: start month and “Today”), and there’s a large empty gap between the almost-flat line and the baseline. Also recapture these stills on the push stack — they have no Back control, while flow 2 correctly shows one.

15. **`27-finish-save-routine-light/dark`.** The field is prefilled “Thursday workout” and looks selected, and Done stays above the keyboard (good). Missing the “Routine name” label and the “Leave it empty…” helper, and the field collides with the Done button (selection handles sit on it). Give it a gap, and scroll the field fully clear of the primary.

16. **`14-health-error`.** No change needed. The toast on Today with no Try again is what we agreed at 10:10. Ignore any older §3.6 wording.

17. **`18-exercise-picker-dark`.** Leg Press shows a solid green placeholder thumb where the others have photos.

18. **Exercise-detail stills vs recordings.** Flow 2 Reduce Motion does the right thing: a crossfade only, media fading in already at its final 3:2 size, no autoplay mid-transition, *the bar* under “Push” does not travel onto the detail (`qa-run5/flow2-open-reduce-motion.png`). In the “slow” open, though, Today cuts to the detail in ~30 ms (`25.293` → `25.325`) — I can’t verify the name morph or `springZoom` (0.48 / 1.0, no bounce). Please recapture flow 2 with Simulator Slow Animations actually running (a 0.42 s spring should last a couple of seconds on tape), and include swipe-back plus the back button, which this pass doesn’t have (your known gap).

19. **PR banner motion, flow 3.** Appear is in good shape: the set row stays put, the number lifts into the banner, “New best” and the why line fade after it lands, *the bar* draws with `barDraw` once the number is in place, and dismiss reverses toward the set while the Best tag and accent ring stay (`qa-run5/flow3-pr-appear-slow.png`, `flow3-pr-dismiss-slow.png`). Auto-dismiss is ~3.6 s after landing (spec 4 s) — close, but please hit 4. Reduce Motion fades the banner in place (~0.2 s; `fadeReduced` is 0.15 s). The second PR (replace in place, no stack) isn’t on this tape — your known gap, fine for the rerun.

## Nit

20. **`02d` disabled `Add 0`.** Fill is a washed `accent`; the label contrast is ~2.0:1. Disabled is exempt from 4.5:1, but it’s very faint. A step darker on the type would help.

21. **Rest drain line, `04-rest`.** Measured ~2.3 pt; DESIGN.md is 3 pt.

22. **`19-reorder`.** Title subtitle is “Push”; spec is “{Routine} · {elapsed}”.

23. **`02d` / setup picker title.** “Add to Push” is clear, but §3.12 is “Add exercise”. Easy to keep if you prefer the more specific title.

24. **AX3 set row, `03-workout-*-accessibility-extra-large`.** Values and the Best/current ring don’t truncate (AC 24, good). The “Last time | Today” column heads still read as two columns once the values stack (value on line 1, last time on line 2, §5). Hide or restack the heads at AX sizes.

25. **`26` / bodyweight rows.** Pull-Up as “0 lb × 10” looks odd. Fine to leave for a later pass if bodyweight units aren’t in phase 1.

26. **Picker Muscle / Equipment chips.** Not in §3.12. Quiet enough to keep; flagging only so we don’t grow a second filter UI later without a decision.

I sampled contrast on canvas and on `accentSoft`: `textPrimary` and `accent` on white are fine (18.4:1 and 5.18:1), `accent` on `accentSoft` is 4.53:1. I didn’t find a body-text failure. Hit targets I measured (56 pt primary, 64 pt day tiles, rest chips) meet 44 pt; I didn’t find a sub-44 control in the stills.

