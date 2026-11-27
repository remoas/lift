# Watch / Live Activity branch — progress (not committed)

Updated 26 Nov 2026, 11:08pm Bermuda time. Remote branch = origin/watch-main (origin/watch is the stale pre-rebase branch; local watch now tracks watch-main).

## Done (on origin/watch-main, rebased on main bcdce1a)
- Watch run 2 Musts 2, 3, 4, 7 + Shoulds (hero 56/64, Last weights, Ember Target hit, 40mm "On this Watch only.")
- Live Activity: AC111 word-boundary names, smooth rings, Skip contrast unchanged, phone-winner-only fallback + tests, DEBUG behaviour harness + log/video
- Library: 'T-Bar Lever Row' alias removed from Pendulum Row; tests updated
- Phone search re-QA 2 (AX3 stacked rows, ~60pt rows, opaque Recents header, 18a3, caption nit)
- Flow 3 PR banner holds while editing; last PR swaps in place
- testflight.yml: widget checks + Lift Internal step (scripts/asc_add_to_group.py)
- Run 45909244573 (76b6d5d) GREEN. Review found: Finish via LiftStore.finish left the phone fallback notification (fixed bea3e47);
  watch page dots overlaid Log set and 40mm Last truncated mid-number (fixed 67b4e42).

## CI
- 45909244573 (76b6d5d) green; review fixes since: bea3e47 (Finish cancels fallback), 67b4e42 (watch dots under button, 40mm Last full weights), 366de5e (search detail word boundaries)
- 45916200257 cancelled (superseded); 45916310862 (366de5e) cancelled: LA behaviour step hung >19 min (normally 4.5)
- 81a6759: bounded simctl calls + 10 min step timeout + job 130 min
- 45920754358 (81a6759) GREEN, all steps. Shots copied to watch-qa2/, liveactivity/, search-qa2/, quicklog-run4/ (10:15pm). But LA behaviour log missing: simctl launch hit the 60 s alarm (continue-on-error hid it).
- 8ab6000: launch no longer blocks; waits on the log
- 45926849768 cancelled (superseded)
- 8124050: Crown-focused value scrolls into view (w19 40mm focus ring was below the fold after Last wrapped)
- 45926937814 cancelled (superseded)
- acdb179: search AX detail keeps '200 × 8' together (18c AX3 split it)
- 45927087834 — ios.yml on acdb179 — GREEN. Shots refreshed (watch-qa2/, liveactivity/, liveactivity/behaviour/ incl. full log + mp4, search-qa2/). w19-40mm still shows the focused prefill below the fold (scroll-into-view didn't take in the fixture) — note for CDO
- main fast-forwarded bcdce1a → acdb179 (10:55pm)
- 45931693625 — testflight.yml build 3 upload=true on main acdb179 (the ONE upload) — GREEN. Build 3 PROCESSING_STATE=VALID (11:07pm), ADDED to 'Lift Internal'. DONE.
- 45927130589 — testflight.yml DRY RUN (build 3, upload=false) on acdb179 — GREEN: archive + export OK; watch com.benspink.lift.watchkitapp 1.0 (3), widgets com.benspink.lift.widgets (3), NSSupportsLiveActivities OK (IDs registered via automatic signing)

## Left
1. 45916200257 green → refresh watch-qa2/, liveactivity/(+behaviour/), search-qa2/, quicklog-run4/
2. Fast-forward main to watch-main
3. testflight.yml build 3 upload=false (registers watch + widget IDs)
4. testflight.yml build 3 upload=true (ONE upload) → Lift Internal
5. Report build number + processing state + paths

---
# watch-fixes-4 (CDO watch QA run 3) — branch off main acdb179. NO merge, NO testflight (build 4 waits for Ben).
Updated 27 Nov 2026, 2:40am Bermuda time.
## Done
- fca0aec: LiftCore lastOneLine (185×8, 7, 6 / 185×8, 175×7… cut at entries) + tests; design/live-activity.md (CDO's accepted-deviation note) committed
- a9becb8: watch fit ladder (one-line Last 40/41 always, 45/49 with a status line; hint/title/Last step down until the value + Crown ring fit; scroll only past that), tap + VoiceOver full Last; watchTitle(lines:) so 40mm counting title is really one line; count frame 42 pt on small; Finish hides an entry while Done's edge would cut it + 10 pt bottom inset; shots on 40 / 42 (41-class) / 46 (45-class) / 49 mm; w09 waits 30 s
## CI
- 45934142781 cancelled: watch-screenshots.sh died in 3 s (pick() failed under pipefail for a missing 45mm sim) — fixed
- 45934637833 (8b0b48b) GREEN, shots in watch-qa3/ (40/42/46/49 mm). Review: one-line Last + 49mm status inset work; but the fit ladder and Finish whole-entry never stepped (preference read outside the ScrollView; reset re-emitted the same value)
- 591582f: fixed both; 40mm count frame 40, 'of 9 · Crown to correct' one line
- 45938121439 cancelled (superseded)
- 4029dd7: SE 3 for 40 mm, w09 relaunched warm
- 45938189179 (4029dd7) GREEN; watch-qa3/ refreshed: w09-40mm now the Add screen (SE 3), 40mm counting keeps bar + 'of 9 · Crown to correct'. Still open: ladder/Finish edge never stepped (preferences don't fire on watchOS)
- e56d25b: ladder + Finish edge now computed from text metrics (WatchFit), no preferences
- 45942783345 (e56d25b) GREEN; watch-qa3/ refreshed. Ladder works now (value + ring on screen at 40/42/46/49). Review fixes: c932bca hint drops before 45/49 Last folds; 0105646 toast replaces Log set on 45/49 too (w13 value was hidden); e7944af w18 scripted scroll shows the list; 4d2a625 name opens Last / VO reads it when Last has no room
- 45947157087 (4d2a625) GREEN (iOS tests on). watch-qa3/ = 80 stills, 20 frames × 40 / 42 (41-class) / 46 (45-class) / 49 mm. DONE, pending CDO. Open nit: 40mm w05 first-time caption truncates ('Log what y…') at ladder step 5.
## Left
- CI green → screenshots-review/watch-qa3/, review vs qa-watch-run3.md
- Report (no merge, no testflight)

## CDO watch QA run 4 (on 4d2a625) — fixes on watch-fixes-4 (2:30am)
- c021df6/next: 40/41 mm Health status "Health is off." (VO reads the full line) — Must 1
- first-time captions fall back to "First time." / "10 reps", no mid-word ellipsis — Must 2
- eeef9dc: name-as-Last 44 pt hit target via contentShape, same look — Must 3
- 6487b45: one-line Last drops the day before any set ("Last · 185×8, 7, 6") + test — Should 3
- "Double tap to log." always on a 45/49 mm first-time page — Should 2
- Should 1 → brief Should 3 (keep Last on 40 mm w04/w12): not done — no shorter status frees the ~15 pt Last needs ("On this Watch only." is already one line; w04's "Counting off." is content)
- CI: 45951056264 green on 5597fce. 80 shots in screenshots-review/watch-qa4/. NO merge, NO testflight.

## CDO watch QA run 5 (on 5597fce) — design approved for build 4 (3:10am)
- w04 / w12 40 mm: option (c), Last stays hidden (name tap + VoiceOver reach it).
- ab4e4aa (watch-fixes-4): 40/41 mm "Double tap to log." once on first use. @AppStorage("watch.doubleTapHintSeen"); claimed by the first current first-time page and marked seen at once, so it shows for that view only and goes on the first logged set. Ladder tries with the hint first, then without. Fixtures read but never write the flag.
- build-4 = origin/main acdb179 + watch-fixes-4 (ab4e4aa) + media-vendor @ 37f1a3a. Both merges clean (no overlapping files). Seed version 7 (was 3). 161 clips in ExerciseMedia/video (104 new from media-vendor + 57 earlier); manifest 133 rows (104 pass, 29 reuse); every video:key resolves.
- NO main, NO testflight.yml: build 4 needs Ben's own yes.
- 4:55am: CI 45956468072 (21ce838) green but w05-40mm had no hint (42/46/49 had it). 463bff4: no margin → CI 45961005506 green (after one rerun of a flaky 50 ms search-timing test) but still no hint on 40 mm. 01cf288: 6 pt slack → CI 45966976594 running. Shots: screenshots-review/watch-qa5/.
- media-vendor moved to fd1da9b (Settings 24a fixture, no clips) after the merge; build-4 has 37f1a3a.
