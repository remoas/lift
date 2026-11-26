import SwiftUI

/// Skeleton line (no spinners anywhere).
struct SkeletonLine: View {
    var widthFraction: CGFloat = 0.7
    var height: CGFloat = 14
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Capsule(style: .continuous)
                .fill(Theme.Colors.bgSunken)
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true }
        }
        .accessibilityHidden(true)
    }
}

/// Thin indeterminate accent line for the iCloud restore (§3.11).
struct IndeterminateLine: View {
    @State private var phase: CGFloat = -0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.bgSunken)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: geo.size.width * phase)
                    .opacity(reduceMotion ? 0.6 : 1)
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
        .onAppear {
            guard !reduceMotion else { phase = 0.3; return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .accessibilityLabel("Restoring from iCloud")
    }
}
