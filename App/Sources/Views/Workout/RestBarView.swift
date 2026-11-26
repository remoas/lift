import SwiftUI
import LiftCore

/// Rest bar: draining Ember line, countdown, "Next …", −15 · +15 · Skip.
struct RestBarView: View {
    let countdown: RestCountdown?
    let nextText: String?
    let doneText: String?
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
                            }
                            Spacer(minLength: 0)
                            Button("−15") { onAdjust(-15) }.buttonStyle(ChipStyle())
                                .accessibilityLabel("Rest 15 seconds less")
                            Button("+15") { onAdjust(15) }.buttonStyle(ChipStyle())
                                .accessibilityLabel("Rest 15 seconds more")
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
