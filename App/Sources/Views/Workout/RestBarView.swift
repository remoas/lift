import SwiftUI
import LiftCore

/// Rest bar: draining Ember line, countdown, "Next …", +30s · Skip (watch.md §3.8).
/// +30s lengthens only this break; Skip has a 5 s Undo (the caller's toast).
struct RestBarView: View {
    let countdown: RestCountdown?
    let nextText: String?
    let doneText: String?
    /// One-time line when notifications are off (watch.md §3.9).
    var caption: String? = nil
    var onAdjust: (Int) -> Void
    var onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let countdown {
                TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.1)) { ctx in
                    let remaining = countdown.remaining(at: ctx.date)
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.Colors.accent)
                                .frame(width: geo.size.width * countdown.progress(at: ctx.date), height: Theme.Size.restLine)
                        }
                        .frame(height: Theme.Size.restLine)
                        HStack(spacing: Theme.Spacing.s2) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(RestCountdown.format(remaining))
                                    .font(Theme.Fonts.timer)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .accessibilityLabel("Rest, \(Int(remaining.rounded(.up))) seconds left")
                                if let nextText {
                                    Text("Next \(nextText)")
                                        .font(Theme.Fonts.secondary)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                if let caption {
                                    Text(caption)
                                        .font(Theme.Fonts.secondary)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                            Button("+30s") { onAdjust(30) }.buttonStyle(ChipStyle())
                                .accessibilityLabel("Rest 30 seconds more, this break only")
                            Button("Skip", action: onSkip).buttonStyle(ChipStyle(accent: true))
                        }
                        .padding(.horizontal, Theme.Spacing.s5)
                        .padding(.vertical, Theme.Spacing.s3)
                    }
                }
            } else if let doneText {
                Text(doneText)
                    .font(Theme.Fonts.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.primaryButton)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .background(Theme.Colors.bgRaised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }
}
