# Lift · DESIGN.md (phase 1 tokens, SwiftUI)

Draft by CDO, 26 Nov 2026. Drafts only. Ben approves the look before anything ships.
Mock: `mock.html` · renders: `shots/` · full spec: `spec.md`.

## Character
Quiet, warm and physical. One typeface (SF Pro), hierarchy from weight, colour and space. One warm accent, **Ember**, used only for: the next action, a new best, and *the bar*.

**Signature 1, "the bar":** a 4 pt rounded Ember underline (2 pt corner radius, 3 pt below the baseline) under the single number or word that matters on a screen: the next workout on Today, the weight in the set editor, the new best in the PR banner and on Finish. Never more than one per screen. It draws left to right when it first appears.
**Signature 2, the draining rest line:** a 3 pt Ember line across the top of the rest bar that shrinks linearly to zero as rest runs out. No ring, no big countdown circle.

## Colour (Asset catalog: `Colors/<name>`, Any + Dark appearances)
| Asset name | Role | Light | Dark |
|---|---|---|---|
| `bgCanvas` | Screen background | #FFFFFF | #0B0B0C |
| `bgSunken` | Grouped list background, stepper/chip fills, segmented track | #F4F3F1 | #161618 |
| `bgRaised` | Sheets, PR banner, rest bar, grouped rows | #FFFFFF | #1E1E21 |
| `separator` | Hairlines (0.5 pt) | #E6E4E0 | #2C2C30 |
| `textPrimary` | Titles, values | #141413 | #F5F4F1 |
| `textSecondary` | Supporting lines, last time | #5E5B57 | #A6A39E |
| `textTertiary` | Set numbers, chevrons, axis | #6F6C67 | #8E8B86 |
| `accent` | Ember: primary button, current tick, PR, the bar, links | #C2410C | #FF8A3D |
| `accentPressed` | Pressed primary | #9A3412 | #FFA766 |
| `onAccent` | Text on accent fill | #FFFFFF | #1A0B02 |
| `accentSoft` | Current-set row tint, next-day halo | #FCEDE5 | #3A1E0E |
| `controlStroke` | Unticked ring (non-text, ≥3:1) | #8C8984 | #6E6B67 |
| `success` | Saved / synced text, toggles | #15803D | #4ADE80 |
| `danger` | Errors, destructive | #B91C1C | #F87171 |
| `scrim` | Behind sheets | #141413 @ 28% | #000000 @ 55% |

Measured contrast (WCAG 2.x): textPrimary ≥13.9:1 on every surface. textSecondary ≥5.9:1. textTertiary ≥4.5:1 on every surface (4.51 lowest, dark on accentSoft). accent text 5.18:1 on white and 4.53:1 on accentSoft (light); ≥6.5:1 (dark). onAccent 5.18:1 (light), 8.2:1 (dark). controlStroke 3.1–3.7:1 against canvas/sunken/raised. **Don't** put `success` text on `accentSoft` (4.39:1), and don't put `controlStroke` on dark `accentSoft`. The current-set ring is `accent`, so this doesn't come up.
Never colour alone: PRs also carry the word "Best"; done sets carry a check glyph; errors carry words.

## Type (SF Pro via text styles; all scale with Dynamic Type)
All numerals use `.monospacedDigit()` (tabular SF Pro, not a mono font).
| Token | SwiftUI | Use |
|---|---|---|
| `display` | `.largeTitle.weight(.bold)` (34) | Screen hero: "Next up, Push", "Push, done." |
| `numeralHero` | `.system(size: 56, weight: .bold)` + `@ScaledMetric(relativeTo: .largeTitle)` + `.monospacedDigit()` | Weight and reps in the set editor |
| `timer` | `.largeTitle.weight(.bold).monospacedDigit()` | Rest countdown |
| `title` | `.title2.weight(.bold)` (22) | Sheet title, PR banner line |
| `exercise` | `.title3.weight(.semibold)` (20) | Exercise name in workout and routines |
| `setValue` | `.title3.weight(.semibold).monospacedDigit()` (20); unit in `.subheadline` textSecondary | "185 lb × 8" |
| `body` | `.body` (17) | Lede prose, rows |
| `bodyEmphasis` | `.body.weight(.semibold)` | Inline numbers in prose |
| `secondary` | `.subheadline` (15) textSecondary | Meta lines, "Last time" |
| `caption` | `.footnote` (13) textSecondary | Axis labels, grouped-list footers, column heads |
Sentence case everywhere. No uppercase labels. Letter-spacing: system default.

## Spacing (pt, 4-pt grid)
`space1` 4 · `space2` 8 · `space3` 12 · `space4` 16 · `space5` 20 (screen margin) · `space6` 24 · `space7` 32 · `space8` 48.
Section gap 28 (`space6` + 4) between a lede and the next list. Set row min height 56. Grouped row min height 48 (≥44).

## Radii
`radiusControl` 10 (segmented) · `radiusChip` 12 (rest −15/+15/Skip) · `radiusButton` 14 (primary 56-pt button, current-set row tint, day picker) · `radiusBanner` 18 · sheet = system (`.presentationCornerRadius` default) · ticks and steppers = Circle.

## Sizes
Primary button height 56, full width minus 2 × 20. Tick: 44 × 44 hit area; ring 30 pt (current set 34 pt, 2.5 pt stroke). Steppers 64 pt circles. Rest chips 44 pt tall, ≥56 wide.

## Motion (respect Reduce Motion → crossfade 0.2 s, no translation/scale)
| Token | Value | Use |
|---|---|---|
| `springTick` | `.spring(response: 0.28, dampingFraction: 0.72)` | Ring fills from centre, check strokes in (0.18 s) |
| `springBanner` | `.spring(response: 0.42, dampingFraction: 0.82)` | PR banner drops 16 pt + fades in; auto-dismiss after 4 s, swipe up to dismiss |
| `barDraw` | `.easeOut(duration: 0.28)` after a 0.12 s delay | The bar draws left→right |
| `restDrain` | `.linear` over the rest duration | Rest line |
| `sheet` | system | Set editor sheet |
Haptics: tick = `.impact(.light)`; new best = `.notification(.success)`; rest at zero = `.notification(.warning)` + local notification if backgrounded; stepper = `.selection`.

## App icon: RESOLVED, icon A (Ben, 6:47am 26 Nov)
`icon/icon-a-ember.svg`: Ember background with a cream loaded barbell, with a 1024 PNG beside it. Preview: `shots/icon-draft.png`. Ship it as the single 1024 asset in all builds. CDO will supply dark and tinted variants next. Icon B is dropped and stays in the folder for reference only.

Accent: **RESOLVED, Ember** (Ben, 6:47am 26 Nov).
