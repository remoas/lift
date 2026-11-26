Hi, CDO here with a motion delta for Lift. Drafts only, as usual: nothing to TestFlight or the store without Ben's own yes, and I'm not opening a branch or PR.

Ben, via Grok Bot at 9:56am Bermuda time on 26 Nov, wants shared element transitions. The reference is Expo's post (https://x.com/expo/status/2125720045276029297), which quotes a Reanimated "postcard" demo: a trip card's photo, title and duration badge morph into a detail hero, the rest crossfades, and a drag or swipe follows the finger back to the list. That's Expo / React Native. This is the native SwiftUI translation.

Updated files, all in /workspace/lift/design/:
- spec.md §8 (the three moments, IDs, dismiss, Reduce Motion) and AC 55 to 61
- DESIGN.md: new tokens `springZoom` and `fadeReduced`; `springBanner` is also the spring for the filter-chip-to-sheet morph

**Target stays iOS 17.** Gate the zoom with `if #available(iOS 18, *)`. iOS 18+ uses `.navigationTransition(.zoom(sourceID:in:))` plus `matchedTransitionSource` for the workout cover and the exercise push. iOS 17 gets the standard full-screen cover and the standard push (system edge swipe included). `matchedGeometryEffect` for the PR banner and the minimised workout bar already works on 17, so it is not gated. Don't bump the target in this work. (For Ben later, not a recommendation: an iOS 18 target would drop the gate.)

One `@Namespace` on the ancestor that presents the cover, and these IDs:

```swift
enum LiftTransitionID: Hashable {
    case workout(UUID)       // Workout.id — reserve it before presenting
    case workoutMini(UUID)   // same id, minimised bar
    case exercise(UUID)      // Exercise.id
    case prBanner(UUID)      // SetEntry.id, banner container
    case prValue(UUID)       // SetEntry.id, the shared number
}
```

Springs (DESIGN.md): large surfaces use `springZoom` — `.spring(response: 0.48, dampingFraction: 1.0)`, equivalently `.smooth(duration: 0.42)` — critically damped, no bounce. Small in-place morphs use `springBanner` — `.spring(response: 0.42, dampingFraction: 0.82)`. Please put that same spring on the filter chip that grows into a sheet, so those morphs feel like one system. Reduce Motion is `fadeReduced` (`.easeInOut(duration: 0.15)`), crossfade only, no translation or scale, on all of the below. Gestures follow the finger, are interruptible, and settle with the spring; released early, the surface returns with no bounce. No `.snappy` and no bounce greater than 0 on the large surfaces. Zooms add no haptic of their own. *The bar* and Ember stay as they are.

**1. Today workout source → active workout** (iOS 18 zoom; iOS 17 standard cover)

There is no new card chrome and no card grid. The source is the typographic block from the hero ("Next up, *Push*") through "Today's lifts", tagged `workout(id)`. Clip at `radiusButton` (14) during the zoom only, morphing to the edge-to-edge cover.

- Morphs: the name "Push" (Today hero → workout nav title); the source bounds and mid-flight radius.
- Crossfades out: lede, week dots, row meta, Start / Other routine / Blank workout, tab bar, settings, and *the bar* under the Today name. The bar does not travel — the workout title has no bar.
- Crossfades in: Close, elapsed, Finish, •••, set rows, notes, rest.
- Other routine zooms from the chosen sheet row; Blank workout from the Blank control (title "Workout" fades in). Resume from Today uses the same source; Resume from the mini bar uses the workoutMini morph in the next paragraph.
- Reserve the `Workout.id` before presenting so both sides share one UUID.

Close, an interactive drag-down, a pinch, and an edge-swipe on the workout all **minimise**, the same as Close. They follow the finger and never dismiss or discard the workout (AC 13). Use `matchedGeometryEffect` on `workoutMini(id)` (iOS 17+) between the nav title plus elapsed time and the bar above the tab bar ("Push · 18:42 · Resume"). Resume from that bar is the reverse. Discard is the path that actually ends the workout; it may reverse-zoom back to Today (iOS 18) and then show the existing undo toast.

**2. Exercise row → exercise detail** (iOS 18 zoom; iOS 17 standard push)

Source: the tapped row (Today, workout header, Finish, History or Routines), tagged `exercise(id)`.

- Morphs: the name, row (`exercise`) → detail hero.
- Crossfades: row meta → eyebrow and lede; chart, bests, notes and settings fade in and do not move; source chrome fades out.
- Media header, when there is media, fades in already at its final geometry: **3:2, inset 20, radius 16**. Do not add a thumbnail to the rows. Video does not autoplay until the transition has finished; play/pause or the Start/End pill fades in after the settle. No media: the header stays collapsed, as now.
- Dismiss: edge swipe-back, the zoom's interactive pinch or drag-down close, and the back button all reverse the zoom to that row. Gestures follow the finger; the back button plays the reverse with `springZoom` and no bounce.

**3. PR banner, appear and dismiss** (`matchedGeometryEffect`, iOS 17+; same pattern as the filter chip → sheet)

The set row stays put. The ring fills and the "Best" tag appear with `springTick`, as already specified; the ring does not fly into the banner.

- Morphs: a matched copy of the today's number (`prValue`) lifts into the banner's "{w} × {r}"; the container (`prBanner`) expands from the value's bounds (radius 14) to the banner (radius 18, 12 pt side insets, under the nav), with `springBanner`.
- Crossfades: "New best" and the why line, once the number has landed. *The bar* then draws under the banner number with `barDraw`. It is not a shared element and must not also sit under the set row.
- Dismiss (4 s auto, or swipe up) reverses the morph back toward the set; the Best tag and accent ring stay. The swipe follows the finger. A second best within 4 s replaces in place, no stack. A tap still opens exercise detail, using transition 2 from the banner.
- Haptic: success when the banner starts to appear, not on dismiss.

**Acceptance criteria:** spec.md §6, AC 55 to 61, on top of AC 1 to 54. Please build this after the first free GitHub / macOS CI run, and include the recordings in that same AC 24 screenshot pass:

- iPhone 16, default text size
- Normal speed, light and dark, plus Simulator Slow Animations in light, plus one Reduce Motion pass in light at normal speed
- (1) Start {Routine}: Today → workout, Close to the mini bar, Resume from the bar
- (2) An exercise row with a media header → detail, then swipe-back, and once with the back button
- (3) A PR appear from a logged set, a swipe-up dismiss, and a 4 s auto-dismiss

I'll do visual QA on those with the AC 24 screenshots. Nothing goes to Ben as a TestFlight request without his own yes.

**Open questions:** none for Ben in phase 1.
