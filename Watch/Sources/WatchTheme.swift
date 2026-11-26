import SwiftUI

/// DESIGN.md dark tokens on the watch (true black canvas; watch.md).
enum WatchTheme {
    static let ember = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x3D / 255)
    static let onAccent = Color(red: 0x1A / 255, green: 0x0B / 255, blue: 0x02 / 255)
    static let raised = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x21 / 255)
    static let sunken = Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x18 / 255)
    static let textPrimary = Color(red: 0xF5 / 255, green: 0xF4 / 255, blue: 0xF1 / 255)
    static let textSecondary = Color(red: 0xA6 / 255, green: 0xA3 / 255, blue: 0x9E / 255)
    static let textTertiary = Color(red: 0x8E / 255, green: 0x8B / 255, blue: 0x86 / 255)
    static let separator = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x30 / 255)

    /// Room under the ••• / Finish row so the exercise name never sits behind it.
    static var toolbarClearance: CGFloat { isLarge ? 28 : 18 }
    static let inset: CGFloat = 10
    static var primaryHeight: CGFloat { isLarge ? 44 : 40 }
    static let buttonRadius: CGFloat = 14

    /// 45 / 49 mm get the larger step (watch.md §3).
    static var isLarge: Bool { WKInterfaceDeviceWidth.value >= 198 }

    static func hero(_ size: CGFloat) -> Font { .system(size: isLarge ? size * 1.15 : size, weight: .semibold, design: .rounded).monospacedDigit() }
}

import WatchKit
enum WKInterfaceDeviceWidth {
    static let value = WKInterfaceDevice.current().screenBounds.width
}

/// Signature 1, "the bar": 4 pt Ember, 2 pt radius, 3 pt below the baseline.
struct TheBar: ViewModifier {
    var on = true
    var dimmed = false
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomLeading) {
            if on {
                RoundedRectangle(cornerRadius: 2)
                    .fill(WatchTheme.ember.opacity(dimmed ? 0.5 : 1))
                    .frame(height: 4)
                    .offset(y: 7)
            }
        }
        .padding(.bottom, on ? 7 : 0)
    }
}

extension View {
    func theBar(_ on: Bool = true, dimmed: Bool = false) -> some View { modifier(TheBar(on: on, dimmed: dimmed)) }
}

/// Edge-to-edge 44 pt Ember primary (the screen's one fill).
struct WatchPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: WatchTheme.primaryHeight)
            .foregroundStyle(WatchTheme.onAccent)
            .background(WatchTheme.ember.opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.45)),
                        in: RoundedRectangle(cornerRadius: WatchTheme.buttonRadius, style: .continuous))
    }
}

/// 44 pt chip: sunken fill; `accent` = Ember text (Skip).
struct WatchChipStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium).monospacedDigit())
            .foregroundStyle(accent ? WatchTheme.ember : WatchTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: WatchTheme.primaryHeight)
            .background(WatchTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
