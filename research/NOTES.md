# Lift exercise media research

Checked 26 Nov 2026, Bermuda time, from official licence or terms pages, not guesswork. No sign-ups, no spend.

The catalog the iOS Developer should use is:

`/workspace/lift/research/exercises.json`

1,250 exercises. Schema: `id`, `name`, `primaryMuscles[]`, `secondaryMuscles[]`, `equipment`, `variant`, `aliases[]`, `mediaRef`, `source`.

## Ranked recommendation

**Best for v1:** this catalog, with media only from two CC0 sources.

- Use [free-exercise-db](https://github.com/yuhonas/free-exercise-db) for the wide exercise list (names, muscles, equipment). Its JSON is Unlicense / public domain. **Do not use its photos.**
- Use [open-exercise-illustrations](https://github.com/hitmanrepo/open-exercise-illustrations) for consistent start/end stills (CC0). Crossfade start → end in the UI. These are AI mannequin drawings, checked by eye, not by a coach.
- Use [workout-free-videos](https://github.com/namnq/workout-free-videos) (v2.0.0) for 57 looping 720p MP4s (CC0). Prefer the video when both exist.
- Fill obvious gaps ourselves (pull-up variants, sled pull, more medicine-ball work, trap-bar shrug/jump/carry) with original metadata and no media yet.

That gives 1,250 exercises and **442 with media that is clearly safe to bundle** (385 OEI stills, 57 videos). The other 808 have no `mediaRef` on purpose.

**Backup, if Ben later wants a demo for almost every lift:**

1. [RepDB free tier](https://github.com/RepDB/exercise-dataset) — 708 consistent 512px stills, free for in-app commercial use if the app shows a visible “Exercise data by RepDB (repdb.co)” credit. **Do not copy it into this repo or republish it as a dataset** (their licence forbids that). Download the official zip and keep it inside the app only. Animations are **not** in the free set; [Standard is $499 once](https://repdb.co/pricing/) for 551 looping clips (no attribution). Paid preview clips in `premium-samples/` must not ship.
2. [Everkinetic](https://github.com/everkinetic/data) line art — CC BY-SA 4.0, commercial use OK with attribution, ShareAlike on modified images only (not the whole app). Last commit 20 Feb 2022. Some files sit in `src/images-png-unknown`; skip that folder. The old `img.everkinetic.com` CDN looks unmaintained.
3. [wger](https://wger.de/api/v2/) for extra names and translations, item by item (mostly CC BY-SA 4.0 / 3.0, a little CC0). Not a good media source: 979 exercises but only 288 have images, styles are mixed, and at least one image is credited to Athlean-X. wger’s equipment list has no general machine, sled, medicine ball or trap bar.

**Avoid**

- **free-exercise-db photographs**, and the copies in [Cawlumm/open-exercise-db](https://github.com/Cawlumm/open-exercise-db). The Unlicense covers the data. The maintainer has said he does not know where the photos came from and that use is at your own risk ([issue 2](https://github.com/yuhonas/free-exercise-db/issues/2), [issue 13](https://github.com/yuhonas/free-exercise-db/issues/13), still open). Others have said some look like ExRx.net images. Rights are unclear — do not bundle them.
- **ExerciseDB / AscendAPI** free V1 ([docs](https://oss.exercisedb.dev/docs)): 1,500 GIFs at 180p, **non-commercial**, attribution required, rate-limited. The GitHub repo’s AGPL tag does not give you the media. Paid RapidAPI / download plans exist; we did not sign up or spend.
- **MuscleWiki API** ([terms, 8 Oct 2026](https://api.musclewiki.com/api-terms)): streaming only. No downloading, bundling or long-term cache (thumbnails 24 hours, video memory-only). Free key is playground-only; direct access starts paid. Required credit and their on-video branding must stay. Do not scrape the site.
- **hasaneyldrm/exercises-dataset GIFs** and anything from **Gym visual**. [NOTICE.md](https://github.com/hasaneyldrm/exercises-dataset/blob/main/NOTICE.md) and [Gym visual terms](https://gymvisual.com/content/3-terms-and-conditions-of-use): the MIT licence is for the text only. Media is © Gym visual. Cloning the repo is not a licence. 180×180 only, with required credit. A paid Gym visual licence would be needed to ship them.
- **flow-exercise-dataset** artwork: claims CC0, but the author says provenance is incomplete and third-party rights are not cleared. Too messy to ship.
- **Free LottieFiles packs**: the [Lottie Simple License](https://lottiefiles.com/page/license/) allows commercial use of public files, but there is no complete “how to do each lift” library — just a handful of decorative clips. [Vector Fitness Exercises](https://vectorfitexercises.com/licenses) is a real animation library (1,600+ Lottie files) but costs $1.60 each, or $699 / $1,299 for a variation or the full library. Fine later, not free.
- **Mixamo** is not a ready exercise library. Adobe’s [FAQ](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) allows royalty-free use of characters and animations in commercial apps and games. You must not redistribute the raw files as an asset pack. [Additional Terms](https://wwwimages2.adobe.com/content/dam/cc/en/legal/servicetou/Mixamo-Addl-Terms-en_US-20210623.pdf) ban using the service to train AI. It needs an Adobe ID (we did not sign up) and someone to pose, render and export every lift.

Do not mix photos, line art, AI mannequins and live video in the same list if you can help it. One illustration style (OEI) plus a small set of real videos is already a visible inconsistency; live with that for v1, or show video only on the exercise detail screen.

## How to ship v1

1. **Bundle**, don’t hot-link. Copy the CC0 stills and MP4s into the app. OEI is about 24 MB (796 WebP). WFV is about 28 MB (57 MP4s). `mediaRef` currently points at GitHub / jsDelivr URLs so you can fetch once, then vendor.
2. **Map** by `id` (stable slug) and `aliases`. When Ben adds or swaps an exercise, fuzzy-match the name against `name` + `aliases`.
3. **OEI motion:** hold `start.webp` (~0.9s), fade to `end.webp` (swap `start` / `hold` in the URL). The README explains this. Frames share a camera, dark background.
4. **No media:** show the exercise name, equipment and muscles. Don’t fetch random web GIFs.
5. **User-created exercises** stay `mediaRef: null` until someone adds a clip.
6. If the demos still feel thin, the clean paid upgrade is RepDB Standard or VFE, after Ben says yes to the spend. Filming Ben (and friends) for the lifts they actually use is the other high-quality path. Mixamo + a 3D render is a longer custom job, not a v1 shortcut.

## Sources used in exercises.json

| Source | Count in file | Licence | Attribution | Media bundled? |
|---|---:|---|---|---|
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | 876 | Unlicense on the **data**. Photos: rights unknown, not used. | None required for the data | No |
| [open-exercise-illustrations](https://github.com/hitmanrepo/open-exercise-illustrations) | 324 unique (plus media attached to matches) | [CC0 1.0](https://github.com/hitmanrepo/open-exercise-illustrations/blob/main/LICENSE) | None required; a link is appreciated | Yes — stills only |
| [workout-free-videos](https://github.com/namnq/workout-free-videos) v2.0.0 | 25 unique (57 videos attached in total) | [CC0 1.0](https://github.com/namnq/workout-free-videos/blob/main/LICENSE) | None required. CC0 does not clear publicity rights of people in the clips. | Yes — 720p MP4 |
| lift (original gap-fills) | 25 | Original metadata for Lift | None | No |

`source` is the record’s text origin. If `mediaRef` is set, the media is always OEI or WFV, even when `source` is free-exercise-db.

## Coverage (primary muscle × equipment)

Full table: `coverage-matrix.md`.

Catalog totals: barbell 198, dumbbell 165, bodyweight 214, cable 107, machine 83, kettlebell 67, band 43, smith 26, medicine ball 24, ez-bar 14, sled 14, plate 12, trap bar 4, other 279 (stretches, strongman, balls, bags, backpacks, rings, and so on).

Ben asked for every muscle, with barbell / dumbbell / machine alternatives, plus medicine ball, sled, and every kind of pull-up. This file goes a long way on **names**. It does not have a demo for every variation.

**Pull-ups / chin-ups in the file:** Pull-Up, Chin-Up, Wide-Grip Pull-Up, Wide-Grip Chin-Up, Close-Grip Pull-Up, Close-Grip Chin-Up, Neutral-Grip / V-Bar, Weighted Pull-Up, Weighted Chin-Up, Band-Assisted, Machine-Assisted, Negative, Scapular, One-Arm Chin-Up, Commando, Side-to-Side Chin-Up, Mixed-Grip, Chest-to-Bar, L-Sit, Towel, Typewriter, Jumping, Archer, Ring, Sternum (Gironda), plus inverted / Australian rows. Media exists only for some of these (standard pull-up, chin-up, wide, neutral, negative, assisted, inverted row).

**Sled:** Push, Pull, Backward Pull, Lateral Drag, Harness Drag, Row, Reverse Flye, Overhead Backward Walk, Overhead Triceps Extension, Bear-Crawl Drag, Prowler Sprint, plus a couple of older “drag” names. No media.

**Medicine ball:** 24 entries, including slam, one-arm slam, chest pass, wall ball, rotational throw, squat-to-press, Russian twist, woodchop, overhead slam. Media for chest pass and slam only.

**Thin spots, even as names:** trap-bar work is still only deadlift, shrug, jump and carry. Side and rear delts, adductors, abductors, neck and lower chest have few alternatives on some equipment (no dumbbell adductor entry, almost no bodyweight side-delt entry, little machine rear-delt). Many compounds are tagged as quads or mid-chest first, so the matrix under-counts glutes / upper chest as a primary. Nine mobility / tibialis / fascia entries have no allowed primary muscle.

**Does combining catalogs get you “everything” with consistent visuals?** No. free-exercise-db + wger is a nice **text** merge (one 2026 snapshot got to about 1,433 after deduping), but wger adds almost no sled / medicine-ball / machine coverage and very little safe, consistent media. Stacking OEI stills, Everkinetic line art, wger community photos and WFV video would cover more tiles and look like four different apps. The honest v1 is: one wide text catalog, one illustration style where we have rights, videos where we have rights, and empty slots otherwise.

## What I checked and did not put in the JSON

- wger public API, 26 Nov 2026: 979 exercises, 395 images (301 CC BY-SA 4, 88 CC BY-SA 3, 6 CC0) covering 288 exercises, 78 videos mostly CC BY-SA 4. Equipment types: barbell, bench, cable, dumbbell, mat, incline bench, kettlebell, pull-up bar, band, EZ-bar, Swiss ball, bodyweight. One sled-named exercise. App code is AGPL; data is per item.
- MuscleWiki: 1,900+ exercises, 7,700+ videos, commercial streamed API. Not bundleable.
- ExerciseDB V1 free: 1,500 × 180p GIFs, non-commercial.
- RepDB: 708 exercises, 1,231 stills, licence allows in-app use with credit, forbids republishing as a dataset — so it is not in `exercises.json`.
- Everkinetic: 293 exercises, CC BY-SA 4.0 confirmed from [LICENSE.md](https://raw.githubusercontent.com/everkinetic/data/main/LICENSE.md) and [maintainer comment](https://github.com/everkinetic/data/issues/7).
