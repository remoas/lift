import SwiftUI
import LiftCore

/// "New best" banner: one at a time, the strongest kind only.
/// Morph (§8.5): the container grows from the set's value (radius 14 → 18)
/// and the number lifts into "{w} × {r}" with `springBanner`; copy fades in
/// once it has landed, then *the bar* draws. Dismiss reverses toward the set.
struct PRBannerView: View {
    let content: PRBannerContent
    var setID: UUID?
    /// false = sitting on the set row's value; true = at the banner's own place.
    var landed: Bool = true
    var onTap: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    private var morphing: Bool { setID != nil && !reduceMotion }
    private var atRow: Bool { morphing && !landed }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                Text("New best")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .opacity(atRow ? 0 : 1)
                HStack(spacing: 0) {
                    Text("\(content.exercise), ").opacity(atRow ? 0 : 1)
                    headline
                }
                .font(Theme.Fonts.title.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.bottom, Theme.Spacing.s2)
                Text(content.why)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(atRow ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.s4)
            .background {
                let r = atRow ? Theme.Radius.button : Theme.Radius.banner
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Theme.Colors.bgRaised)
                    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 0.5))
                    .shadow(color: Theme.Colors.scrim.opacity(atRow ? 0 : 0.35), radius: 14, y: 6)
                    .modifier(MatchIf(id: setID.map(LiftTransitionID.prBanner), active: atRow))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.s3)
        .offset(y: reduceMotion ? 0 : min(drag, 0))
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { drag = $0.translation.height }   // follows the finger
                .onEnded { value in
                    if value.translation.height < -40 || value.predictedEndTranslation.height < -120 {
                        onDismiss()
                    }
                    withAnimation(reduceMotion ? Theme.Motion.fadeReduced : Theme.Motion.springBanner) { drag = 0 }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibility)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("PR banner")
        .onAppear {
            AccessibilityNotification.Announcement(content.accessibility).post()
        }
    }

    @ViewBuilder private var headline: some View {
        let text = Text(content.headline).contentTransition(.numericText())
            .modifier(MatchIf(id: setID.map(LiftTransitionID.prValue), active: atRow, properties: .position))
        // The bar draws only once the number has landed, never on the set row.
        if landed || !morphing { text.theBar().id(content.headline) } else { text }
    }
}

/// Matched to the set row while `active`; otherwise free to lay out.
private struct MatchIf: ViewModifier {
    let id: LiftTransitionID?
    let active: Bool
    var properties: MatchedGeometryProperties = .frame
    func body(content: Content) -> some View {
        if let id {
            content.liftMatched(id, active: active, properties: properties, isSource: false)
        } else {
            content
        }
    }
}
