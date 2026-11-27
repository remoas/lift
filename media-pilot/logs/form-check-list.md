# Form-check list (internal, media-pilot)

Check every frame (2 fps plus first/last) against CDO's clip-standard, plus these failure modes. Reject the clip if any are present.

## Always
- Neutral spine; knees track over mid-foot / toes; joints stacked
- Correct camera family (true side-on for presses, rows, squats, hinges, curls, dips, pull-ups, unless a later brief overrides; three-quarter only for raises, flys, face pulls)
- Real matching equipment; same athlete and the house-gym reference frame (see Same-gym check)
- 2–3 complete full-ROM reps in 8 s; first and last frames match the start pose
- No text, logos, music, cuts, zooms, grade, or extra person
- Feet planted where the lift requires it; no hyperextension at lockout


## Same-gym check (required on every start still and every clip, added 2026-11-26 ~9:11pm Atlantic/Bermuda after CDO Round 8)

The house-gym reference is `refs/house-gym.jpg` (a copy of the CDO-final `starts/dumbbell-romanian-deadlift-start.jpg`). Anchor every future start still and prompt to that frame so the same skyline and machines carry across clips.

House-gym tells:
- Golden-hour penthouse, wood floor, black rubber centre mats, floor-to-ceiling windows with dark frames
- The usual pointed / ornate-crown tower in the skyline — not a tall glass needle / obelisk tower
- Typical side-on background machines: a seated / preacher-style machine on a small mat at the left, a flat bench on a small mat at the right
- Bench-family three-quarter shots may include a squat rack in the foreground and crop the pointed tower (as on the CDO-final `one-arm-dumbbell-bench-press` and `decline-dumbbell-bench-press`). That accepted bench-family frame is OK if the city, light and floor still match. A different city skyline or a swapped machine set is not.

**Reject any new start still whose background drifts** (needle tower, a different skyline cluster, or clearly different background machines). Do not use a drifted still as a ref. Do not generate a video from a drifted start.

On an already-encoded clip, flag the drift, keep the passing clip if CDO has already passed it, and queue a regen that is locked to `refs/house-gym.jpg`. CDO Round 8 treated the drift on `chest-supported-dumbbell-row` as a Should, not a FAIL, and left the drifted official in place until a house-gym regen passed CDO. CDO Round 9 accepted that regen; at ~9:54pm Atlantic/Bermuda the official `video/chest-supported-dumbbell-row.mp4` was swapped to the house-gym clip, and the reuse `dumbbell-incline-row` now points to the clean official. The gym-drift Should is retired.

Audit of clips made since the Round 8 batch was sent (first frames vs `refs/house-gym.jpg` and the accepted bench-family frame), ~9:11pm Atlantic/Bermuda:
- No needle-tower drift on `floor-press`, `barbell-split-squat`, `hammer-grip-incline-db-bench-press`, `single-leg-romanian-deadlift`, `cable-curl-regen`, `inverted-row` a2, or `dumbbell-flyes` a2.
- `barbell-split-squat`, `hammer-grip-incline-db-bench-press`, `single-leg-romanian-deadlift`, and `dumbbell-flyes` a2 match the usual pointed tower and left/right background machines.
- `floor-press` uses the accepted bench-family three-quarter + rack frame (same as CDO-final `one-arm-dumbbell-bench-press` / `decline-dumbbell-bench-press`), not the needle-tower gym.
- `inverted-row` a2 and `cable-curl-regen` keep the usual skyline; the extra rack or cable stack is the working equipment.

## Added after CDO QA of the P1 pilots (2026-11-26)
- **Implement must not pass through the body.** A barbell, dumbbell, cable or pad cannot travel through a limb, torso or the other plate. On conventional deadlifts the bar stays in front of *both* shins for the whole lift, over mid-foot, with the hands outside the knees — never behind the far shin or between the legs.
- **Machines must have their real structure.** A shin pad, roller or handle cannot float. A leg-extension must be a real seated machine whose shin pad is fixed to a visible pivoting lever arm (and typically a weight stack or plate horn), not a flat or adjustable bench with a disconnected roller.
- **Dumbbells must read as dumbbells, not as a barbell.** Use fixed hex or fixed round-head commercial dumbbells. Do not use plate-loaded dumbbells with oversized Olympic plates that look like a short barbell in profile.


## Must failure modes added after CDO QA Round 4 (2026-11-26, about 6:20pm Atlantic/Bermuda)

Reject the clip if this is present. This is a FAIL, not a Should.

- **Every cable or band attaches to exactly one handle in every frame.** Each D-handle, rope end or band end has its own cable or strand; two cables must not converge on one handle while the other handle hangs with no cable. This is a FAIL (CDO Round 4 on alternating-cable-shoulder-press: in the left-arm-up poses at 0.00s, 4.00s and 7.83s, both low-pulley cables attached to the raised left handle and the right handle had no cable).

## Shoulds added after CDO QA part 2 (2026-11-26)

These are form targets to prompt for and to check. Per CDO's honesty rule, a mild case that is only obvious in 1:1 crops, or that does not break the lift, is a Should (note it) — do not FAIL the clip on that alone. Still prompt for the correct version on every new clip, including regenerations and P2.

- **Neutral, stacked wrists on presses.** Wrists stay in line with the forearms, stacked over the elbows, not excessively extended (bent back) or flexed. Applies to barbell and dumbbell bench, incline, overhead and military presses. Mild wrist extension at the bottom of a bench press was a Should, not a FAIL, on the accepted bench-press clip.
- **Firm hands and grip throughout.** Fingers and thumbs stay visibly wrapped on the bar, handle, rope or dumbbell. Hands must not morph, melt, or fuse into the implement. Compression softness that is only visible in 1:1 6fps crops, and not at normal viewing size, is a Should, not a FAIL (as on triceps-pushdown).
- **Face-pull finish: rope at nose or eye level, not the hair.** At peak contraction the rope should split in front of the face at nose or eye level, with high elbows. A slightly high forehead / rope-on-hair finish is a Should, not a FAIL, if the rope is on the hair and not through the skull (as on the accepted face-pull clip). Prompt new face-pulls for the nose/eye finish.

## Shoulds added after CDO QA Round 2 (2026-11-26, about 5:20pm Atlantic/Bermuda)

Prompt for these on every new clip. Per CDO's honesty rule, a mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement. Still try to hit the target.

- **Every rep must reach a full lockout (or the equivalent end range).** Each of the 2–3 reps should finish the ROM: a tall hip-and-knee lockout on a deadlift, a soft elbow lockout on a press, handles to the hip on a row, chin clearly over the bar on a pull-up. On the accepted deadlift, rep 1 locked out tall at 2.33–2.67s, but rep 2 peaked hinged at mid-thigh at 6.33s. That short second rep is a Should, not a FAIL. If a later clip has one complete locked-out rep and a cheap incomplete second rep, prefer trimming to a clean 1-rep loop that finishes at full lockout (still 8.000s / 192 frames, first/last locked) rather than shipping a short second rep.
- **The leg-extension pivot should line up with the knee.** The cam or lever pivot should be roughly coaxial with the knee joint so the pad tracks the lower leg. A pivot a little forward of the knee is a Should, not a FAIL, if the pad stays on the lever and the movement is still a real leg extension (as on the accepted leg-extension clip).
- **The incline bench should sit at 30–45°.** An incline press is performed on a back pad between about 30 and 45 degrees from horizontal. A clearly inclined bench that measures a little shallow (about 25° on the accepted incline-dumbbell-press) is a Should, not a FAIL, if the movement is still an incline press and the dumbbells travel to the upper chest. A flat or steeply upright bench is the wrong setup.

## Shoulds added after CDO QA Round 3 (2026-11-26, about 5:50pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **Aim for exactly 2 clean, complete reps.** Do not add a cheap partial extra rep at the end of the loop. On the accepted chin-up, a short incomplete third pull runs from about 6.25s to 7.3s and never gets the chin clearly over the bar. That is a Should, not a FAIL. In any regeneration, and on new clips, time two full reps so the second descent is complete and the clip returns to the start pose without a third pull.
- **A pendulum / lever row must be chest-supported.** The machine must include the prominent inclined chest pad from the reference photo, and the athlete's chest must stay on that pad through the set, with a neutral spine, while the handles are rowed to the lower ribs. A free hip-hinge on a foot platform with no chest pad is the wrong setup and is a FAIL (CDO Round 3 on the first pendulum-row clip).


## Shoulds added after CDO QA Round 5 (2026-11-26, about 6:51pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **For archer-pull-up: the head tilts back with the chin chasing the bar at both peaks, and a slight bend in the right arm at 5.50s.** On the accepted left-side archer-pull-up clip, the chin-over is a bit tight because the head tilts back, and the right (trailing) arm has a slight residual bend at the second peak (5.50s). Those are Shoulds, not FAILs, if both peaks still read as archers (one arm bent, the other nearly straight and wide, torso shifted to the pulling side). Prompt new archer clips for a clear chin-over (bar below the chin with visible air) and a nearly straight trailing arm at both peaks.

## Shoulds added after CDO QA Round 6 (2026-11-26, about 7:17pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **For close-grip-pull-up: the hands widen slightly at the peaks, but stay narrower than a regular pull-up.** On the accepted close-grip-pull-up clip, the hang keeps a tight close overhand grip, and at both peaks the hands drift a little wider (narrow-to-shoulder-width) while remaining narrower than the accepted `pullups` clip. That is a Should, not a FAIL, if the lift still reads as a close-grip pull-up. Prompt new close-grip clips to keep the tighter hang spacing all the way to the top.


## New-phase Shoulds (pending CDO, 2026-11-26)

- **For trap-bar-deadlift: encoded first/last MAE is 4.76, above the usual 2.2–3.8 band.** The last start is a slightly tighter hip position than the first; both are legal floor starts inside the hex bar, and the loop is still usable. Treat as a Should, not a FAIL, unless CDO judges the loop break too large.
- **For glute-bridge: the camera is a high three-quarter rather than true side-on.** Accepted on start v4 (last still under the 4-still cap) once the hips were finally down on the mat. Treat the camera angle as a Should if the two hip-to-peak reps are otherwise clean.
- **For pec-deck: the weight stack and cam are not clearly visible.** The seat, back pad and arm pads are fixed to a real machine frame, so this was not failed as “machine missing real structure.” CDO can decide whether the missing stack is a Should or a retry.

- **For hanging-leg-raise: a slight knee bend at both peaks.** The legs reach about parallel (or slightly above) with the arms remaining long. Treat a modest knee bend as a Should if the clip still reads as a hanging leg raise rather than a hanging knee raise.

- **For decline-dumbbell-bench-press: slight left-right depth asymmetry at the bottoms.** Both reps still reach the lower chest with two separate hex dumbbells on a clear decline. Treat the uneven depth as a Should, not a FAIL, if the clip still reads as a decline dumbbell bench press.
- **For chest-supported-dumbbell-row (retired, CDO Round 9):** the earlier gym-drift Should applied to the pre-regen official. That file is archived; the official is now the house-gym regen. See the Round 8/9 notes and the official Should: far elbow more open.


## Shoulds added after CDO QA Round 7A (2026-11-26, about 8:36pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **For cable-curl (retired, CDO Round 9):** the old official had a high-pulley cable clipped to the same handle in every frame. CDO Round 9 accepted the low-cable-only regen; that clip is now the official `video/cable-curl.mp4` (old file in `rejected/video/cable-curl.pre-regen.mp4`). The double-cable Should is retired. The current official Should is under Round 9: the pulley shifts.
- **For pendlay-row: the torso is about 40°, not parallel.** On the accepted pendlay-row clip, the torso sits around 40 degrees from horizontal rather than near parallel. That is a Should, not a FAIL, if the bar still starts and returns on the floor each rep and the lift still reads as a Pendlay row. Prompt new Pendlay clips for a torso closer to parallel.
- **For trap-bar-deadlift: hips are tighter on the second start.** It is fine at viewing size. Combined with the earlier encoded first/last MAE of 4.76, treat the slightly tighter second-start hip position as a Should, not a FAIL, unless a later CDO pass asks for a retry.
- **For barbell-glute-bridge: the camera is a high three-quarter rather than true side-on.** This matches the accepted bodyweight glute-bridge camera. Treat as a Should if the two hips-down-to-lockout reps are otherwise clean, with the barbell staying on the hip crease.


## Shoulds added after CDO QA Round 7B (2026-11-26, about 8:41pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **For incline-dumbbell-fly: the elbows bend more at the top, so the finish reads as a fly-to-press.** On the accepted incline-dumbbell-fly clip, both open positions are still a fly stretch, and CDO passed it, but elbow flexion increases at the top. Prompt new fly clips to keep a slight, even elbow bend throughout, including at the top — do not let the top turn into a press. This is a Should on the current clip, not a FAIL.
- **standing-biceps-cable-curl now points to the CDO Round 9 official cable-curl.** The double-cable Should is retired. The alias inherits the official Should: the pulley shifts.

- **For inverted-row (CDO Round 9 official Shoulds):** feet lift to about bench height at the peaks; the bar lands on the upper chest. Both peaks reach the bar, which fixes the Round 7B forehead-only ROM fail.
- **For dumbbell-flyes (CDO Round 9 official Should):** near arm slightly tucked. Both arms are fly stretches, which fixes the Round 7B press-bottom-vs-fly fail.

- cable-curl official is now the CDO Round 9 accepted low-cable regen (see Round 9 Shoulds). Old official archived in rejected/video/cable-curl.pre-regen.mp4.

- **For floor-press (CDO Round 9 official Should):** plate angle drifts.

- **For split-squat (CDO Round 9 official Should):** rear heel lifts high at 4.0s.

- **For SL-RDL (CDO Round 9 official Should):** free leg bent high.

## Shoulds added after CDO QA Round 8 (2026-11-26, about 9:07pm Atlantic/Bermuda)

Prompt for these on every new clip. A mild miss is a Should (note it) — do not FAIL the clip on that alone if the lift is still clearly the named movement.

- **For decline-dumbbell-bench-press: depth is slightly uneven left to right at the bottoms.** At both bottoms the dumbbell toward the hips sits a little higher / less deep than the dumbbell at the shoulder. Both still reach the lower chest, and CDO passed the clip. Prompt new decline-DB presses for even depth.
- **For chest-supported-dumbbell-row (retired, CDO Round 9):** the old official had drifted to a different skyline with a needle tower, plus different machines (side-by-side: `design/media/pilot-qa/chest-supported-dumbbell-row/stills/compare-skyline-vs-rdl.jpg`). CDO Round 8 treated that as a Should. CDO Round 9 accepted the house-gym regen; that clip is now the official `video/chest-supported-dumbbell-row.mp4` (old file in `rejected/video/chest-supported-dumbbell-row.pre-regen.mp4`). The gym-drift Should is retired. The reuse `dumbbell-incline-row` now points to the clean official. The current official Should is under Round 9: far elbow more open.


- chest-supported-dumbbell-row official is now the CDO Round 9 accepted house-gym regen (see Round 9 Shoulds). Old official archived in rejected/video/chest-supported-dumbbell-row.pre-regen.mp4.

- overhead-squat: two complete stand-to-parallel overhead squats, house gym locked, bar stays locked out overhead. Should: the grip is about shoulder-width rather than a very wide snatch grip.

- zercher-squat: two complete stand-to-parallel Zercher squats, house gym locked, far plate sharp (a1 was not encoded because of a ghosted far plate). Should: the bar sits a bit high on the upper chest rather than deep in the elbow crease. Reuse: zercher-squats.

- split-squat-with-dumbbells: two complete in-place split squats, house gym locked, feet stay planted, two hex DBs at the sides. Should: the start/stand already has a softly bent front knee, and the rear heel stays up on the toes.

- v-bar-pulldown: two complete stretch-to-upper-chest V-bar pulldowns, house gym locked, exactly one high cable to the V-handle in every reviewed frame. Should: the camera is more front-on than a slight 3/4, and the usual left background machine is hidden by the pulldown station.

- dumbbell-hip-thrust: two complete bench-edge hip thrusts, house gym locked, one hex DB on the hip crease. Should: the start is already mid-height rather than hips near the floor, the lockout is slightly short of a perfectly straight shoulder-to-knee line, and the DB is held with the near hand.

- landmine-press: two complete one-arm landmine presses, house gym locked, bar stays in the floor sleeve. Should: the stance is more parallel than staggered, and the bar is unloaded.


## Shoulds added after CDO QA Round 9 (2026-11-26, about 9:53pm Atlantic/Bermuda)

CDO passed all 8 items and confirmed they match the house gym. Official Shoulds on the current passing clips:

- **inverted-row:** feet lift to about bench height at the peaks; the bar lands on the upper chest.
- **dumbbell-flyes:** near arm slightly tucked.
- **cable-curl:** the pulley shifts.
- **floor-press:** plate angle drifts.
- **split-squat:** rear heel lifts high at 4.0s.
- **SL-RDL:** free leg bent high.
- **chest-supported row:** far elbow more open.

The `tricep-pushdowns` alias was verified. The `barbell-floor-press` alias of `floor-press` was verified. The official `cable-curl.mp4` and `chest-supported-dumbbell-row.mp4` were swapped to the accepted regens at ~9:54pm Atlantic/Bermuda; `standing-biceps-cable-curl` and `dumbbell-incline-row` now point to those clean official clips.

- hip-thrust-machine: two complete seated-to-lockout machine hip thrusts, house gym locked, feet stay planted (a1 was not encoded because both feet lifted at ~4.0s). Should: no obvious lap pad, and the feet are on the floor rather than a footplate; the 4.0s between-rep is already early in the second ascent (the seated between-rep is closer to 3.0-3.5s).
- bodyweight-hip-thrust: two complete unweighted bench-edge hip thrusts, house gym locked, no implement, feet planted, hands empty. Should: the start is already mid-height rather than hips near the floor, the lockout is slightly short of a perfectly straight shoulder-to-knee line, and the 4.0s between-rep stays fairly high (modest dip).

- landmine-romanian-deadlift: two complete stand-to-hinge landmine RDLs, house gym locked, sleeve stays on the floor, both hands on the free end. Should: the bar is unloaded, and the torso at both bottoms is about 40-50 degrees rather than nearly horizontal.

- reverse-triceps-bench-press: two complete lockout-to-mid-chest reverse-grip bench presses, accepted bench-family gym locked, underhand grip holds in the reviewed frames. Should: the bar sits a bit high on the upper chest at both bottoms.
- landmine-squat: two complete stand-to-parallel landmine squats, house gym locked, sleeve stays on the floor, both hands on the free end. Should: the hold is a bit high, at the chin / upper chest rather than mid-sternum.
- romanian-deadlift-from-deficit: two complete stand-to-hinge deficit RDLs, house gym locked, feet stay on the platform. Should: torso at both bottoms is not fully horizontal; the near and far bar plates do not match (solid vs cutout).
- barbell-squat-to-a-bench: two complete stand-to-bench-touch-to-stand high-bar back squats, house gym locked, glutes sit on the working bench at both bottoms. Should: the working bench is slightly offset to the rear-right.
- narrow-stance-squats: two complete stand-to-parallel-to-stand high-bar back squats with a clearly narrow stance, house gym locked. Should: bottoms are about parallel / a hair high.

## Shoulds added after CDO QA Round 10 (2026-11-26, about 10:25pm Atlantic/Bermuda)

CDO passed 8 unique clips and verified the `zercher-squats` alias. The Round 9 official regen swaps (`cable-curl.mp4`, `chest-supported-dumbbell-row.mp4`) were verified as the files now in `video/`. Official Shoulds on the current passing clips:

- **overhead-squat:** the grip is about shoulder-width rather than a very wide snatch grip.
- **zercher-squat:** the bar sits a bit high on the upper chest rather than deep in the elbow crease. Reuse `zercher-squats` verified.
- **split-squat-with-dumbbells:** the stand already has a softly bent front knee, and the rear heel stays up on the toes.
- **v-bar-pulldown:** the camera is more front-on than a slight 3/4, and the usual left background machine is hidden by the pulldown station.
- **landmine-press:** the stance is more parallel than staggered, and the bar is unloaded.
- **bodyweight-hip-thrust:** the start is already mid-height rather than hips near the floor; the lockout is slightly short of a perfectly straight shoulder-to-knee line; the 4.0s between-rep stays fairly high (a modest dip).
- **landmine-romanian-deadlift:** the bar is unloaded, and the torso at both bottoms is about 40-50 degrees rather than nearly horizontal.
- **reverse-triceps-bench-press:** the bar sits a bit high on the upper chest at both bottoms.

CDO Round 10 FAILs, queued for regen (old official files kept until a passing regen is swapped in):

- **dumbbell-hip-thrust:** the hips never reach a full lockout with the torso parallel to the floor; the torso stays clearly diagonal at 2.0s and 5.5s. Regen must start from the hips near the floor and get both reps to a full lockout with the torso parallel to the floor.
- **hip-thrust-machine:** there is no lap or hip pad at the start or at either peak, so the machine is not recognisable as a hip-thrust machine (same class of miss as a pendulum row without a chest pad). Regen must use a padded lever across the hips. If two tries do not produce a pad, park as needs-manual.

The earlier internal Should on hip-thrust-machine ("no obvious lap pad") is retired; CDO treated the missing pad as a FAIL.
- front-barbell-squat-to-a-bench: two complete stand-to-bench-touch-to-stand front squats, house gym locked, front rack held, glutes sit on the working bench at both bottoms. Should: the working bench is slightly offset to the rear-right.
- kneeling-squat: two complete tall-kneeling-to-sit-back-to-tall-kneeling reps, house gym locked, both knees stay on the mat (a1 was not encoded because the knees left the floor). Should: the sit-back is modest, not a full sit-to-heels.
- olympic-squat: two complete stand-to-ATG-to-stand high-bar back squats, house gym locked. Should: the torso leans forward more than a textbook upright Olympic squat.
- hip-thrust-machine official is now the CDO Round 10 FAIL regen (swapped ~10:40pm Atlantic/Bermuda). Old official archived in rejected/video/hip-thrust-machine.pre-regen.mp4. Shoulds on the regen: the torso is not fully parallel to the floor at the peaks; the 4.0s between-rep is not fully seated; the pad reads more as a held roller than a clearly pivoted lever arm.
- dumbbell-hip-thrust CDO Round 10 FAIL regen parked after 4 start stills failed to put the hips near the floor. Accepted lockout peak kept at starts/dumbbell-hip-thrust-peak-regen.jpg.
- weighted-sissy-squat parked after 4 mid stills (v1-v4 all regular parallel back squats with heels down). Accepted start kept at starts/weighted-sissy-squat-start.jpg.
- one-leg-barbell-squat: two complete tall-to-parallel-to-tall barbell Bulgarian / one-leg squats, house gym locked, rear foot stays on the working bench. Should: the front knee on the tall start has a slight soft bend.
- stiff-legged-dumbbell-deadlift: two complete stand-to-hinge-to-stand stiff-legged hinges, house gym locked, two hex DBs stay in the hands. Should: the knees have more than a soft bend; the torso at both bottoms is not fully horizontal; the far dumbbell is mostly hidden behind the near one at the start.
- t-bar-row-with-handle: reuse of t-bar-row (accepted clip is already a T-bar platform with a close handle).
- bodyweight-mid-row: reuse of inverted-row (same horizontal bodyweight row from a bar).
- close-grip-front-lat-pulldown and full-range-of-motion-lat-pulldown: skipped as close-grip / full-range lat-pulldown variants.
- dumbbell-squat-to-a-bench: two complete stand-to-bench-touch-to-stand squats, house gym locked, two hex DBs stay at the sides, glutes sit on the working bench at both bottoms. Should: the far dumbbell is mostly hidden behind the near one at the start.
- wide-stance-barbell-squat: two complete wide-stance high-bar back squats to about parallel, stance held, bar stays on the upper traps, house gym locked. Should: the far foot is a bit further forward than the near foot.
- cable-deadlifts: two complete cable hinges, straight-bar handle and exactly one low cable stay in every sampled frame, house gym locked. Shoulds: compact floor pulley rather than a full cable tower; bar around the knees rather than mid-shin; torso not fully horizontal at the bottoms.
- leverage-deadlift: two complete leverage-machine deadlifts, hips stay higher than the knees at both bottoms, machine structure and plates stay coherent, house gym locked. Shoulds: handles read more as a horizontal cross-bar than two clearly separate vertical neutral grips; machine finish is silver rather than the usual black house-gym equipment.
- chair-squat: parked needs-retry-or-manual after 4/4 starts. v1 house gym and Smith were good but the feet were only barely in front of the rods, so it read as a regular Smith squat. v2 stood the athlete on a raised bench and dropped both usual background machines. v3 was already a parallel squat and was missing the left seated machine. v4 stood tall and kept the left machine but dropped the usual right bench and still had only a shallow forward foot position. No start kept.
- lying-machine-squat: two complete reps from a 90-degree loaded start to a nearly extended top and back, feet stay on the platform, machine structure holds, house gym locked. Shoulds: usual left seated machine is not visible on its background mat; loop starts at about 90° rather than slightly below parallel; the between-rep bottom arrives a little early so 4.0s is already mid-extension.

## Shoulds added after CDO QA Round 11 (2026-11-26, about 11:13pm Atlantic/Bermuda)

CDO passed 7 unique clips. Official Shoulds match the library notes already logged, which CDO confirmed:

- **landmine-squat:** the hold sits a bit high at the chin / upper chest rather than mid-sternum.
- **romanian-deadlift-from-deficit:** the torso at both bottoms is not fully horizontal, and the near and far bar plates do not match (solid vs cutout).
- **barbell-squat-to-a-bench:** the working bench is slightly offset to the rear-right.
- **narrow-stance-squats:** the bottoms are about parallel / a hair high.
- **front-barbell-squat-to-a-bench:** the working bench is slightly offset to the rear-right.
- **olympic-squat:** the torso leans forward more than a textbook upright Olympic squat.
- **one-leg-barbell-squat:** the front knee already has a slight soft bend at the tall start.

CDO Round 11 FAILs, queued for regen (old official files kept until a passing regen is swapped in):

- **kneeling-squat:** the sit-back is only a shallow pulse. At both bottoms a large gap remains between the glutes and the heels; the hips do not hinge back to the heels. Regen must sit the hips back to, or near, the heels on both reps, with both knees staying on the mat.
- **stiff-legged-dumbbell-deadlift:** at both bottoms the knees are clearly bent about 30–40°, so the clip reads as a regular Romanian deadlift. Regen must keep the knees near straight throughout. Accept a lower bottom rather than more knee bend.
- **hip-thrust-machine:** regen a1 (now official) has a padded roller across the hips, but the pad is a loose held roller, not attached to a lever or frame, and at both peaks the hips do not reach close to lockout. One more try: the pad must be fixed to a pivoting machine arm, and the lockout must be near-parallel. If that try fails, park as needs-manual. Leave the current official CDO-fail out of vendoring.

The earlier internal Shoulds on kneeling-squat ("sit-back is modest, not a full sit-to-heels") and stiff-legged-dumbbell-deadlift ("knees have more than a soft bend") are retired as the reasons for these FAILs. The earlier regen Should that the hip-thrust-machine pad "reads more as a held roller than a clearly pivoted lever arm" is now a FAIL, together with the short lockout.
- stiff-legged-dumbbell-deadlift official is now the CDO Round 11 FAIL regen (swapped ~11:30pm Atlantic/Bermuda). Old official archived in rejected/video/stiff-legged-dumbbell-deadlift.pre-regen.mp4. Two complete stiff-legged hinges, knees stay nearly straight with only a slight soft unlock, house gym locked, two hex DBs. Shoulds: the torso at both bottoms is not fully horizontal; the far dumbbell is mostly hidden behind the near one at the start.
- hip-thrust-machine official is now the CDO Round 11 second regen (swapped ~11:30pm Atlantic/Bermuda). R11 FAIL official archived in rejected/video/hip-thrust-machine.r11-fail.mp4; earlier r10 official remains in rejected/video/hip-thrust-machine.pre-regen.mp4. Padded roller stays fixed to a pivoting lever arm, two complete seated-to-near-parallel-lockout reps, feet stay planted, house gym locked. Shoulds: the torso is a touch short of perfectly parallel at the peaks; machine finish is silver rather than the usual black house-gym equipment. CDO Round 12: PASS (final); this clip is now included in vendoring.
- kneeling-squat CDO Round 11 FAIL regen parked as needs-retry-or-manual after 5 regen bottoms. regen-v1 and v3 stood up into regular squats; regen-v2, v4 and v5 stayed kneeling but left a large gap between the glutes and the heels (the same shallow-pulse miss CDO failed). Official CDO-fail clip left in place. Accepted tall-kneeling start kept at starts/kneeling-squat-start.jpg.
- narrow-stance-hack-squats: parked needs-retry-or-manual after 4/4 starts. v1 had a real 45-degree hack in the house gym but the back and hips were off the pad. v2 put the back on the pad with a narrow stance but was missing the shoulder pads. v3 and v4 still did not show clearly hooked-over shoulder pads (they read as the top of the back pad); v3 also had a hip gap, and v4 was already a bent-knee mid and was missing the usual left seated machine. No start kept.
- barbell-side-split-squat: two complete stand-to-side-lunge-to-stand reps, house gym locked, bar stays on the upper traps, black sneakers. Should: the trail leg sits a bit behind a perfectly left-right line, so the split has a slight forward-lunge component.

- bent-over-one-arm-long-bar-row: two complete stretch-to-waist-row-to-stretch one-arm long-bar / landmine rows, house gym locked, only the near hand on the loaded sleeve, landmine end stays in the floor pivot. Shoulds: the landmine is a square block rather than the circular sleeve used in the other house-gym landmine clips; the stretched hang sits a little high, around mid-thigh rather than mid-shin; the elbow is a bit high and flared at both peaks. Official encode 409,544 bytes, MAE 2.19.
- one-arm-long-bar-row: reuse of bent-over-one-arm-long-bar-row (same one-arm landmine / long-bar row).

- bent-over-two-arm-long-bar-row: two complete stretch-to-waist-row-to-stretch two-arm long-bar / landmine rows, house gym locked, both hands stay on the loaded end, landmine end stays in the floor pivot, no T-bar platform or chest pad. Shoulds: the landmine is a square block rather than the circular sleeve used in the other house-gym landmine clips; the stretched hang sits a little high, around mid-thigh; the hands read more as holding the plate than the sleeve past the collar. Official encode 447,192 bytes, MAE 2.96.

- feet-elevated-inverted-row: two complete hang-to-chest-to-hang feet-elevated inverted rows, both sneakers stay on the bench, house gym locked, bar stays in the squat rack. Shoulds: the left seated machine is hidden behind the squat rack (same as the inverted-row family in this gym); at both peaks there is still a modest gap between the chest and the bar. Official encode 524,763 bytes, MAE 2.47.

- kettlebell-deadlift: two complete stand-to-floor-to-stand two-hand kettlebell deadlifts, one black kettlebell held with both hands on the handle, hip-width stance, house gym locked. Shoulds: at both bottoms the bell sits just above the mat rather than fully resting on it; the upper back is a little rounded and the head looks down at the bottoms. Official encode 550,005 bytes, MAE 2.63.

- kettlebell-one-legged-deadlift: two complete stand-to-hinge-to-stand one-legged kettlebell deadlifts, one black kettlebell held with both hands on the handle, trail foot stays off the floor, house gym locked. Shoulds: at both bottoms the torso is a touch short of perfectly horizontal. Official encode 578,451 bytes, MAE 2.81.

- kettlebell-romanian-deadlift: two complete stand-to-mid-shin-hinge-to-stand two-hand kettlebell Romanian deadlifts, the bell stays off the floor, hip-width stance, house gym locked. Shoulds: at both bottoms the torso is well short of horizontal; the knees have more than a soft unlock. Official encode 504,409 bytes, MAE 2.51.

- kettlebell-sumo-deadlift: two complete stand-to-floor-to-stand kettlebell sumo deadlifts, one black kettlebell held with both hands on the handle, a clearly wide toes-out stance held throughout, house gym locked. Shoulds: the camera is a three-quarter view rather than the usual side-on hinge camera. Official encode 532,407 bytes, MAE 2.62.

- lying-cambered-barbell-row: parked needs-retry-or-manual after 4/4 starts. v1 was an incline chest-supported row; v2 was face-up on a flat bench (bench-press setup). v3 and v4 were face-down on a flat bench in the house gym with a cambered/EZ bar underneath, but only the near hand was on the bar. No start kept.

- meadows-row: two complete stretch-to-hip-row-to-stretch one-arm landmine Meadows rows, compact stance, only one hand on the sleeve past the plate, landmine end stays in the floor pivot, house gym locked. Shoulds: the landmine is a square block rather than the circular sleeve used in the other house-gym landmine clips; the stance is only a little more compact and less staggered than bent-over-one-arm-long-bar-row, so the perpendicular Meadows stance is subtle; the elbow is a bit high and flared at both peaks. Official encode 465,419 bytes, MAE 2.37.

- reverse-grip-barbell-row: parked needs-retry-or-manual after 4/4 starts. v1 and v2 had a mid-shin hang in the house gym but the grip was not clearly underhand (v2 crop showed knuckles on top). v3 was still grip-ambiguous. v4 kept the house gym but the bar was unloaded (no plates) and the underhand grip was still not unmistakable. No start kept.

- smith-machine-romanian-deadlift: two complete stand-to-just-below-the-knee-hinge-to-stand Smith Romanian deadlifts, the bar stays mounted on both guide rods and stays off the floor, house gym locked. Shoulds: slight three-quarter camera rather than the usual side-on hinge camera; the usual left seated machine and right bench are hidden by the Smith, as in the official smith-machine-overhead-press start; at both bottoms the torso is short of horizontal and the bar sits just below the knee rather than mid-shin. Official encode 489,956 bytes, MAE 3.00.

- smith-machine-stiff-legged-deadlift: two complete stand-to-mid-shin-hinge-to-stand Smith stiff-legged deadlifts, the knees stay nearly straight with only a slight soft unlock, the bar stays mounted on both guide rods and stays off the floor, house gym locked. Start still is the same standing lockout as smith-machine-romanian-deadlift-start.jpg. Shoulds: slight three-quarter camera rather than the usual side-on hinge camera; the usual left seated machine and right bench are hidden by the Smith, as in the official smith-machine-overhead-press start; at both bottoms the torso is not fully horizontal. Official encode 474,726 bytes, MAE 2.98.

- bent-over-two-dumbbell-row: two complete hang-to-hip-row-to-hang two-hex-dumbbell rows, palms facing the torso, torso stays hinged, house gym locked. Shoulds: the far dumbbell is partly occluded behind the near one; the torso is a bit short of fully parallel; the head looks down. Official encode 551,587 bytes, MAE 2.91.

- bent-over-two-dumbbell-row-with-palms-in: reuse of bent-over-two-dumbbell-row. FEDB wording is palms facing each other versus palms facing the torso; the accepted 195 clip already uses a hanging neutral grip with two hex dumbbells at the sides.

- bodyweight-squat: two complete stand-to-parallel-or-slightly-below-to-stand hands-behind-head bodyweight squats, no implement, house gym locked. Should: at both bottoms the squat posture shows a little more of the chest than the standing start. Official encode 556,465 bytes, MAE 2.91.

- front-squats-with-two-kettlebells: two complete stand-to-parallel-to-stand double-kettlebell front squats, one bell racked at each shoulder, upright torso, house gym locked. Official encode 571,780 bytes, MAE 2.81.

- kettlebell-goblet-squat: reuse of goblet-squat (same kettlebell goblet squat: one bell held by the horns at the chest). Shares video/goblet-squat.mp4. No new generation.

- kettlebell-pistol-squat: two complete stand-to-parallel-to-stand kettlebell pistol squats, one bell held by the horns at the chest, free leg stays off the floor, supporting heel down, house gym locked. Official encode 545,912 bytes, MAE 2.65. Shoulds: the free leg is held quite high near hip height at the standing positions; supporting-leg depth is about parallel rather than a deeper below-parallel pistol bottom; a little more of the chest is visible at both bottoms than in the standing start; the second rep pauses a beat longer at the bottom before standing up into the last frame.

- kettlebell-turkish-get-up-squat-style: two complete floor-to-stand-to-floor squat-style Turkish get-ups, both feet on the mat to stand, no lunge, one kettlebell stays locked out overhead including both descents, house gym locked. Official encode 513,252 bytes (CRF 28), MAE 2.71. Shoulds: slightly elevated three-quarter camera, pulled back so the stand fits; the posting left arm at the floor start sits closer to the hip than a wide 45-degree T-position; the sit-up path is a compact sit-to-squat rather than a forearm post; the squat stance is fairly wide and the bottoms are below parallel; during the final sit-back the lockout is a touch soft as the torso reclines.

- one-arm-overhead-kettlebell-squats: two complete stand-to-parallel-to-stand one-arm overhead kettlebell squats, one bell stays locked out overhead, looking straight ahead, both heels down, house gym locked. Official encode 450,876 bytes, MAE 2.32. Shoulds: a little more of the chest is visible at both bottoms than in the standing start; a slight forward torso lean at the bottoms; the free arm is out for balance; both bottoms hold a brief pause before standing up.

- renegade-row: two complete plank-to-hip-row-to-plank same-arm renegade rows, high plank on two separate hex dumbbells, the far bell stays planted, house gym locked. Official encode 496,149 bytes, MAE 2.44. Shoulds: slightly elevated three-quarter camera pulled back so the full plank fits; the head looks down; the feet are fairly close together rather than a slightly wider support stance; the second peak holds a brief pause before lowering into the last frame.

- seal-row: two complete hang-to-pad-row-to-hang dumbbell seal rows, chest stays on a flat bench elevated on two boxes, feet stay off the floor, house gym locked. Official encode 418,653 bytes, MAE 2.34. Shoulds: the feet visually overlap the left background machine; the head rests on the pad rather than hanging off the end; the far dumbbell is partly occluded at the hangs; the second peak holds a brief pause before lowering into the last frame.

- smith-machine-pistol-squat: two complete stand-to-parallel-to-stand Smith pistol squats, the bar stays mounted on both guide rods and across the back of the shoulders, free leg stays off the floor, house gym locked. Official encode 459,541 bytes (CRF 28), MAE 3.18. Shoulds: slight three-quarter camera so both guide rods are visible; the usual left machine and right bench are hidden by the Smith, as in the official smith-machine-overhead-press start; the free leg is held quite high at the stands and passes in front of the far guide rod rather than staying inside the rack; supporting-leg depth is about parallel; both bottoms hold a brief pause, the second a beat longer before standing up into the last frame.

- smith-machine-squat: two complete stand-to-parallel-to-stand two-leg Smith squats, the bar stays mounted on both guide rods and across the back of the shoulders, both heels stay down, house gym locked. Official encode 463,319 bytes (CRF 28), MAE 2.96. Shoulds: slight three-quarter camera so both guide rods are visible; the usual left machine and right bench are hidden by the Smith, as in the official smith-machine-overhead-press start; the stance is a little narrower than a full shoulder-width squat stance; a little more of the chest is visible at both bottoms than in the standing start; the second bottom holds a brief pause before standing up into the last frame.

- leverage-high-row: two complete stretch-to-torso-row-to-stretch seated plate-loaded leverage high rows, handles start high and in front, athlete stays seated, thigh pad stays on, house gym locked. Official encode 510,976 bytes, MAE 2.67. Shoulds: a seat back is present; at the stretched positions the elbows are slightly bent rather than a fully extended reach; the near and far arms are slightly asymmetric at the peaks; the second peak holds a brief pause before returning into the last frame.

- machine-high-row: reuse of leverage-high-row. The library aliases are iso-lateral high row and plate-loaded high row, and the CC0 stills show the same seated plate-loaded high-handle row with a thigh pad. Shares video/leverage-high-row.mp4. No new generation.

- leverage-iso-row: two complete stretch-to-torso-row-to-stretch seated plate-loaded mid rows, handles stay attached to the lever at chest height, athlete stays seated, house gym locked. Official encode 471,540 bytes, MAE 2.76. Shoulds: a seat back is present; the peak is short of the ribs rather than a fully tucked contraction.

- lying-t-bar-row: two complete stretch-to-peak-to-stretch chest-supported T-bar rows, chest stays on the pad, feet stay on the platform, the T-bar stays in the floor pivot with plates on the loaded end, house gym locked. Official encode 436,286 bytes, MAE 2.86. Shoulds: the head looks down; the plates visually overlap the left background machine at the peaks; the second peak holds a brief pause before lowering into the last frame.

- machine-row: parked needs-retry-or-manual after 4/4 starts. v1 had a stack and V-handle but the chest was off a small midsection pad. v2 had a seat back and the stack behind the athlete. v3 left the machine seat and chest pad empty and sat him on a second bench. v4 put a pad on the thighs rather than the chest. No start kept; do not use those stills as refs.

- shotgun-row: parked needs-retry-or-manual after 4/4 mids. Accepted start kept at starts/shotgun-row-start.jpg (house gym locked, low cable, one D-handle, wide-split stance). Mid v1 and v2 were still the stretched start; v3 invented a second handle in the free hand; v4 was still the stretch. Do not use those mids as refs.

- barbell-rear-delt-row: two complete hang-to-chest-to-hang wide-grip barbell rear-delt rows, torso stays hinged, bar stays a barbell, house gym locked. Official encode 542,084 bytes, MAE 2.75. Shoulds: slight three-quarter camera; the torso is short of parallel; the head looks down; the bar stops around the lower chest rather than the upper chest; the elbows are not fully flared into a T.

- single-arm-cable-row: two complete stretch-to-hip-row-to-stretch single-arm cable rows, exactly one D-handle stays on the taut low cable, free hand stays empty on the hip, moderate staggered stance held, house gym locked. Official encode 458,981 bytes, MAE 2.58. Shoulds: the peak is short of the hip, with the handle a little in front of the waist rather than fully tucked; the second peak holds a brief pause before lowering into the last frame.

- upright-cable-row: two complete mid-thigh-hang-to-chin-to-hang upright cable rows, standing tall, a straight bar stays on one low cable, elbows stay high at the peaks, house gym locked. Official encode 495,555 bytes, MAE 2.86. Shoulds: true side-on, so at mid-path the bar is partly end-on and reads shorter; the second peak holds a brief pause before lowering into the last frame.

- cable-upright-row: reuse of upright-cable-row. Cable Upright Row is the same standing low-pulley straight-bar upright row; the OEI stills show that same mid-thigh hang to chin with the elbows high. Shares video/upright-cable-row.mp4. No new generation.

- one-arm-lat-pulldown: two complete stretch-to-chin-to-stretch one-arm lat pulldowns, stays seated, thighs stay under the pad, exactly one D-handle stays on the high cable, free hand stays empty on the hip, house gym locked. Official encode 438,591 bytes, MAE 2.55. Shoulds: slight three-quarter camera; the handle stops around head/chin height rather than lower at the shoulder or chest; the second peak holds a brief pause before raising into the last frame.

- reverse-grip-lat-pulldown: two complete stretch-to-upper-chest-to-stretch reverse-grip lat pulldowns, stays seated, thighs stay under the pad, a straight bar stays on one high cable with a supinated underhand grip, house gym locked. Official encode 491,110 bytes, MAE 2.94. Shoulds: the bar stays a little in front of the upper chest rather than lightly touching it; the second peak holds a longer pause before raising into the last frame.

- underhand-cable-pulldowns: reuse of reverse-grip-lat-pulldown. Underhand Cable Pulldowns is the same seated straight-bar lat pulldown with a supinated underhand grip. Shares video/reverse-grip-lat-pulldown.mp4. No new generation.

- rope-straight-arm-pulldown: two complete stretch-to-thigh-to-stretch rope straight-arm pulldowns, stays standing, arms stay nearly straight, a two-end triceps rope stays on one high cable, house gym locked. Official encode 479,255 bytes, MAE 2.73. Shoulds: the torso is fairly upright, with only a slight hip hinge; the elbows stay softly bent at the finishes rather than fully straight; the hands finish a little in front of the thighs rather than fully at the sides.

- dumbbell-one-arm-upright-row: two complete hang-to-mid-chest-to-hang one-arm dumbbell upright rows, standing tall, a single hex dumbbell stays in the near hand, free hand stays empty, house gym locked. Official encode 445,928 bytes, MAE 2.78. Shoulds: the dumbbell sits a little in front of the torso rather than close to the chest; the elbow is about level with the dumbbell rather than clearly above it.
- dumbbell-upright-row: two complete hang-to-upper-chest-to-hang two-arm dumbbell upright rows, standing tall, two matching hex dumbbells stay visible in both hands, house gym locked. Official encode 559,512 bytes, MAE 2.98. Shoulds: slight 3/4 rather than the one-arm family's side-on (needed so both dumbbells stay visible); the elbows are about level with the dumbbells rather than clearly leading above them; the dumbbells sit a little high, around upper-chest height rather than lower chest; the far elbow is a little more tucked than the near one; mid-path the far dumbbell runs a little ahead of the near one.
- smith-single-leg-split-squat: two complete top-to-bottom-to-top Smith-machine split squats in a long split stance, feet stay planted, the Smith bar stays on the upper traps and slides on the rails, house gym locked. Official encode 476,768 bytes, CRF 28, MAE 3.69. Shoulds: the front knee is already somewhat bent at the start rather than nearly straight; the near upright occludes the rear thigh; the rear knee comes very close to the floor at the bottom; the official first-last MAE is 3.69 after CRF 28, though the end pose is only slightly off the start.
- kettlebell-row: two complete hang-to-hip-to-hang one-arm kettlebell rows, hinged at the hips, a single kettlebell stays in the near hand, free hand stays empty, house gym locked. Official encode 499,369 bytes, MAE 3.08. Shoulds: the free hand leaves the thigh at the peaks and is hidden on the far side; the kettlebell sits a little below a tight hip tuck; at the mid-rep hang the far shoe peeks out behind the kettlebell and can briefly read like a second bell.


## CDO QA Round 12 official Shoulds (about 12:00am Atlantic/Bermuda, 27 Nov 2026)

All eight PASS. Unique CDO-final count is now 90. Aliases `t-bar-row-with-handle` → `t-bar-row` and `bodyweight-mid-row` → `inverted-row` were verified. Parked `kneeling-squat` and `dumbbell-hip-thrust` were not reviewed and stay out of the unique-done and vendoring counts.

- **dumbbell-squat-to-a-bench:** the far DB is hidden at the start.
- **wide-stance-barbell-squat:** the far foot is a bit forward.
- **cable-deadlifts:** compact floor pulley; the bar bottoms out about at the knees; the torso isn't fully horizontal.
- **leverage-deadlift:** the handles read as a cross-bar; silver finish.
- **lying-machine-squat:** the left seated machine is missing; the loop starts at about 90°; the 4.0s between-rep comes early.
- **barbell-side-split-squat:** the trail leg sits slightly behind the line.
- **stiff-legged-dumbbell-deadlift:** the torso isn't fully horizontal; the far DB is hidden.
- **hip-thrust-machine:** the torso is a touch short of parallel; silver finish.

## CDO QA Round 13 official Shoulds (about 1:09am Atlantic/Bermuda, 27 Nov 2026)

All eight PASS. Unique CDO-final count is now 98. Alias `one-arm-long-bar-row` → `bent-over-one-arm-long-bar-row` was verified. Parked `kneeling-squat`, `dumbbell-hip-thrust` and `lying-cambered-barbell-row` were not reviewed and stay out of the unique-done and vendoring counts. `smith-machine-romanian-deadlift`, `smith-machine-stiff-legged-deadlift`, `bent-over-two-dumbbell-row` and the `bent-over-two-dumbbell-row-with-palms-in` alias were not in this brief and were not reviewed.

- **bent-over-one-arm-long-bar-row:** square block rather than a round sleeve; mid-thigh hang; high flared elbow.
- **bent-over-two-arm-long-bar-row:** square block; mid-thigh hang; the hands read as holding the plate.
- **feet-elevated-inverted-row:** left machine hidden; modest chest-to-bar gap.
- **kettlebell-deadlift:** bell just above the mat; slight upper-back rounding; head down.
- **kettlebell-one-legged-deadlift:** torso a touch short of horizontal.
- **kettlebell-romanian-deadlift:** torso short of horizontal; knees at about 30–40° (still reads as an RDL).
- **kettlebell-sumo-deadlift:** three-quarter camera.
- **meadows-row:** square block; stance only a little more perpendicular; flared elbow.

## CDO QA Round 14 official Shoulds (about 2:33am Atlantic/Bermuda, 27 Nov 2026)

All six unique PASS. Unique CDO-final count is now 104. Aliases `bent-over-two-dumbbell-row-with-palms-in` → `bent-over-two-dumbbell-row` and `kettlebell-goblet-squat` → `goblet-squat` were verified. Parked `kneeling-squat`, `dumbbell-hip-thrust` and `lying-cambered-barbell-row` were not reviewed and stay out of the unique-done and vendoring counts.

- **smith-machine-romanian-deadlift:** 3/4 camera; machines hidden by the Smith; torso short of horizontal; bar stops just below the knee.
- **smith-machine-stiff-legged-deadlift:** 3/4 camera; machines hidden; torso short. It visibly differs from 190 side by side.
- **bent-over-two-dumbbell-row:** far DB occluded; torso short of parallel; head down.
- **bodyweight-squat:** slightly more chest shows at the bottoms.
- **front-squats-with-two-kettlebells:** none.
- **kettlebell-pistol-squat:** free leg high at the stands; depth about parallel; more chest shows; rep 2 pauses at the bottom.

## CDO QA Round 15 official Shoulds (about 5:04am Atlantic/Bermuda, 27 Nov 2026)

All ten unique PASS. Unique CDO-final count is now 114. Alias `machine-high-row` → `leverage-high-row` was verified. Parked `kneeling-squat`, `dumbbell-hip-thrust`, `machine-row` and `shotgun-row` were not reviewed and stay out of the unique-done and vendoring counts. Out-of-scope pending `single-arm-cable-row`, `upright-cable-row` (with the `cable-upright-row` alias) and `one-arm-lat-pulldown` were listed, not QAd.

- **kettlebell-turkish-get-up-squat-style:** elevated 3/4 camera pulled back; posting arm close to the hip rather than a wide T; compact sit-to-squat instead of a forearm post; a briefly ghosted free arm at 1.00s; lockout a touch soft on the final sit-back.
- **one-arm-overhead-kettlebell-squats:** a little more of the chest visible at both bottoms; a slight forward torso lean at the bottoms; the free arm is out for balance; both bottoms hold a brief pause.
- **renegade-row:** elevated 3/4 camera pulled back; the head looks down; the feet are fairly close together; the second peak holds a brief pause.
- **seal-row:** feet overlap the left machine (occluded, not interpenetrating); the head rests on the pad rather than hanging off the end; the far DB is partly occluded at the hangs; the second peak holds a brief pause.
- **smith-machine-pistol-squat:** 3/4 camera; the Smith hides the usual left machine and right bench; the free leg is held quite high at the stands and passes in front of the far rod with no clipping; supporting-leg depth is about parallel; both bottoms pause, the second a beat longer.
- **smith-machine-squat:** 3/4 camera; the Smith hides the usual machines; the stance is a little narrower than shoulder-width; a little more of the chest is visible at both bottoms; the second bottom holds a brief pause.
- **leverage-high-row:** a seat back is present; elbows are slightly bent at the stretch rather than a fully extended reach; the arms are slightly asymmetric at the peaks; the second peak holds a brief pause.
- **leverage-iso-row:** a seat back is present; the peak is short of the ribs rather than a fully tucked contraction.
- **lying-t-bar-row:** the head looks down; plates overlap the left machine at the peaks (occluded, not interpenetrating); the second peak holds a brief pause.
- **barbell-rear-delt-row:** slight 3/4 camera; torso short of parallel; the head looks down; the bar stops at the lower chest rather than the upper chest; the elbows are not fully flared into a T.

## CDO QA Round 16 official Shoulds (about 5:23am Atlantic/Bermuda, 27 Nov 2026)

All four unique PASS. Unique CDO-final count is now 118. Aliases `cable-upright-row` → `upright-cable-row` and `underhand-cable-pulldowns` → `reverse-grip-lat-pulldown` were verified. Parked `kneeling-squat`, `dumbbell-hip-thrust`, `machine-row` and `shotgun-row` were not reviewed and stay out of the unique-done and vendoring counts. Out-of-scope pending `rope-straight-arm-pulldown` was listed, not QAd.

- **single-arm-cable-row:** the peak is short of the hip, with the handle a little in front of the waist rather than fully tucked; the second peak holds a brief pause.
- **upright-cable-row:** true side-on, so at mid-path the bar is partly end-on and reads shorter; the second peak holds a brief pause.
- **one-arm-lat-pulldown:** slight 3/4 camera; the handle stops at the chin rather than lower at the shoulder or chest; the second peak holds a brief pause.
- **reverse-grip-lat-pulldown:** the grip is visibly supinated; the bar stays a little in front of the upper chest rather than lightly touching it; the second peak holds a longer pause.

