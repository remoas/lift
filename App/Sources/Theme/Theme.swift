import SwiftUI

/// The single style layer (CDO DESIGN.md, draft). Views use these tokens only.
/// Colours live in Assets.xcassets/Colors with Any + Dark appearances.
enum Theme {
    enum Colors {
        static let bgCanvas = Color("bgCanvas")
        static let bgSunken = Color("bgSunken")
        static let bgRaised = Color("bgRaised")
        static let separator = Color("separator")
        static let textPrimary = Color("textPrimary")
        static let textSecondary = Color("textSecondary")
        static let textTertiary = Color("textTertiary")
        static let accent = Color("accent")
        static let accentPressed = Color("accentPressed")
        static let onAccent = Color("onAccent")
        static let accentSoft = Color("accentSoft")
        static let controlStroke = Color("controlStroke")
        static let success = Color("success")
        static let danger = Color("danger")
        static let scrim = Color("scrim")
    }

    /// SF Pro text styles only; every numeral is monospaced-digit.
    enum Fonts {
        static let display = Font.largeTitle.weight(.bold)
        static let timer = Font.largeTitle.weight(.bold).monospacedDigit()
        static let title = Font.title2.weight(.bold)
        static let exercise = Font.title3.weight(.semibold)
        static let setValue = Font.title3.weight(.semibold).monospacedDigit()
        static let body = Font.body
        static let bodyNumber = Font.body.monospacedDigit()
        static let bodyEmphasis = Font.body.weight(.semibold).monospacedDigit()
        static let secondary = Font.subheadline.monospacedDigit()
        static let caption = Font.footnote.monospacedDigit()
        static let label = Font.subheadline.weight(.semibold)
        static func numeralHero(_ size: CGFloat) -> Font { .system(size: size, weight: .bold).monospacedDigit() }
    }

    /// Placeholder glyphs for exercises without cleared media (one per body region).
    enum Symbols {
        static func region(_ region: String?) -> String {
            switch region {
            case "Chest": return "figure.strengthtraining.traditional"
            case "Shoulders": return "figure.arms.open"
            case "Back": return "figure.rower"
            case "Arms": return "dumbbell.fill"
            case "Legs": return "figure.step.training"
            case "Core": return "figure.core.training"
            case "Neck": return "figure.mind.and.body"
            default: return "figure.flexibility"
            }
        }
    }

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20   // screen margin
        static let s6: CGFloat = 24
        static let s7: CGFloat = 32
        static let s8: CGFloat = 48
        static let section: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 10
        static let chip: CGFloat = 12
        static let button: CGFloat = 14
        static let banner: CGFloat = 18
        static let media: CGFloat = 16
    }

    enum Size {
        static let primaryButton: CGFloat = 56
        static let setRow: CGFloat = 56
        static let groupedRow: CGFloat = 48
        static let thumb: CGFloat = 44
        /// Exercise media header (§3.8): 3:2, never taller than 4:3.
        static let mediaAspect: CGFloat = 3.0 / 2.0
        static let mediaMinAspect: CGFloat = 4.0 / 3.0
        static let mediaLoadTimeout: Double = 8
        static let hit: CGFloat = 44
        static let ring: CGFloat = 30
        static let ringCurrent: CGFloat = 34
        static let ringStroke: CGFloat = 2.5
        static let stepper: CGFloat = 64
        static let chipWidth: CGFloat = 56
        static let bar: CGFloat = 4
        static let restLine: CGFloat = 3
    }

    enum Motion {
        static let springTick = Animation.spring(response: 0.28, dampingFraction: 0.72)
        static let springBanner = Animation.spring(response: 0.42, dampingFraction: 0.82)
        static let barDraw = Animation.easeOut(duration: 0.28).delay(0.12)
        static let crossfade = Animation.easeInOut(duration: 0.2)
        /// Large surfaces (Today → workout, row → detail): critically damped, no bounce.
        static let springZoom = Animation.spring(response: 0.48, dampingFraction: 1.0)
        /// Reduce Motion fallback for every shared transition: crossfade only.
        static let fadeReduced = Animation.easeInOut(duration: 0.15)
    }
}

extension RoundedRectangle {
    /// Continuous corners, for explicit use (e.g. `RoundedRectangle.smooth(14)`).
    static func smooth(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension Shape where Self == RoundedRectangle {
    /// Continuous corners everywhere.
    static func continuous(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// 56 pt full-width primary button (the screen's one Ember fill).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButton)
            .foregroundStyle(Theme.Colors.onAccent)
            .background(configuration.isPressed ? Theme.Colors.accentPressed : Theme.Colors.accent, in: .continuous(Theme.Radius.button))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Quiet text action in accent, ≥44 pt tall.
struct TextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Theme.Colors.accent)
            .frame(minHeight: Theme.Size.hit)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Rest chips: −15 · +15 · Skip.
struct ChipStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium).monospacedDigit())
            .foregroundStyle(accent ? Theme.Colors.accent : Theme.Colors.textPrimary)
            .frame(minWidth: Theme.Size.chipWidth, minHeight: Theme.Size.hit)
            .padding(.horizontal, Theme.Spacing.s2)
            .background(Theme.Colors.bgSunken, in: .continuous(Theme.Radius.chip))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Screen margins from DESIGN.md.
    func screenMargins() -> some View { padding(.horizontal, Theme.Spacing.s5) }

    /// Sentence-case section label ("Today's lifts").
    func sectionLabel() -> some View {
        font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
    }
}
