# Lift

Ben's private strength-training app. Native SwiftUI, iOS 17+, local-first.

**Status:** phase 1 code complete and not yet compiled with Xcode. The shared logic package is tested on Linux (51 tests passing). The app needs one manual macOS CI run to type-check and screenshot it (see *CI*). The design is CDO's draft until Ben approves it.

## Layout

| Path | What |
|---|---|
| `Packages/LiftKit` | `LiftCore`: pure Swift with no UI. Covers units (kg/lb, store as entered, compare in kg), Epley e1RM, PR detection, the plate calculator, rotation, progression, CSV, session edits (add, swap, reorder, remove with undo), routine diff, the exercise library and its search, and the view models for the set row, rest bar and PR banner. This is reused by the phase 2 Watch app. |
| `Packages/LiftKit/Sources/LiftCore/Resources/exercise-library.json` | Versioned seed: 1,250 exercises with stable string IDs. Built by `tools/build_seed.py` from `research/exercises.json`. |
| `App/Sources` | SwiftUI app: `Theme/` (every colour, font and size token), `Model/` (SwiftData + CloudKit), `Services/` (Health, rest notifications, iCloud monitor, toasts, haptics), `Views/`, and `Debug/` (screenshot fixtures, DEBUG builds only). |
| `App/Resources/Assets.xcassets` | Colour assets from DESIGN.md (light and dark), AccentColor = Ember, AppIcon = icon A. |
| `App/Resources/ExerciseMedia` | 782 vendored CC0 files (50 MB). See `THIRD_PARTY_MEDIA.md`. |
| `design/` | CDO's spec, DESIGN.md, mock and frames (draft). |
| `research/` | Exercise dataset, research notes, and `VALIDATION.md` (latest seed validation report). |

## Rules this code keeps

- No hard-coded colours or fonts in views: tokens live in `Theme.swift` and the asset catalogs. Every number uses `.monospacedDigit()`.
- No demo data in shipped builds. Fixtures exist only under `#if DEBUG` and use an in-memory store.
- The library is a pick list. Rows are created when an exercise is first picked, with deterministic UUIDs, so seed updates merge without touching customs or history.
- Every `SetEntry` has a UUID. History and PRs are keyed by exercise ID and set, so swaps and blank workouts share history.

## Build

```sh
# Package tests (macOS or Linux)
cd Packages/LiftKit && swift test
# App (macOS + Xcode 16)
brew install xcodegen && xcodegen generate
open Lift.xcodeproj   # set your team locally; never commit it
```

Seed and media:

```sh
python3 tools/vendor_media.py   # fetch cleared CC0 media, rewrite THIRD_PARTY_MEDIA.md
python3 tools/build_seed.py     # validate + write the seed; fails on bad rows, never auto-fixes
```

## CI

`.github/workflows/ios.yml` runs on `workflow_dispatch` only. It runs the package tests, generates the project, builds an unsigned build for the iPhone 16 simulator, and captures the 27 frames in light and dark plus the AX3 set row with `scripts/screenshots.sh`. The results are uploaded as the `lift-review` artifact.

Nothing here signs, uploads to TestFlight, or touches App Store Connect.
