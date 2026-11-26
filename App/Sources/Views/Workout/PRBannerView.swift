import SwiftUI
import LiftCore

/// "New best" banner: one at a time, the strongest kind only.
struct PRBannerView: View {
    let content: PRBannerContent
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                Text("New best")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                HStack(spacing: 0) {
                    Text("\(content.exercise), ")
                    Text(content.headline).theBar()
                }
                .font(Theme.Fonts.title.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.bottom, Theme.Spacing.s2)
                Text(content.why)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.s4)
            .background(Theme.Colors.bgRaised, in: .continuous(Theme.Radius.banner))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 0.5))
            .shadow(color: Theme.Colors.scrim.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.s3)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < -10 { onDismiss() } })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.accessibility)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            AccessibilityNotification.Announcement(content.accessibility).post()
        }
        .id(content.headline + content.exercise)
    }
}
