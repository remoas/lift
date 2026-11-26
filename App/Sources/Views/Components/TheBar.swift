import SwiftUI

/// "The bar": a 4 pt rounded Ember underline, 3 pt below the baseline, under the
/// one number or word that matters on a screen. Draws left to right on appear.
struct TheBar: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                Capsule(style: .continuous)
                    .fill(Theme.Colors.accent)
                    .frame(height: Theme.Size.bar)
                    .scaleEffect(x: drawn || reduceMotion ? 1 : 0, anchor: .leading)
                    .opacity(reduceMotion && !drawn ? 0 : 1)
                    .offset(y: 3 + Theme.Size.bar)
                    .accessibilityHidden(true)
            }
            .onAppear {
                withAnimation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.barDraw) { drawn = true }
            }
    }
}

extension View {
    func theBar() -> some View { modifier(TheBar()) }
}
