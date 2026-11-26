import SwiftUI
import Observation

/// Undo toasts replace confirmation popups: the action happens immediately and
/// can be reversed for a few seconds.
@Observable
@MainActor
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undo: (() -> Void)?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, undo: (() -> Void)? = nil) {
        current = Toast(message: message, undo: undo)
        dismissTask?.cancel()
        let id = current?.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.current = nil
        }
    }

    func performUndo() {
        current?.undo?()
        current = nil
    }

    func dismiss() { current = nil }
}

struct ToastOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                HStack(spacing: Theme.Spacing.s3) {
                    Text(toast.message)
                        .font(Theme.Fonts.bodyNumber)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if toast.undo != nil {
                        Button("Undo") { toasts.performUndo() }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .padding(.horizontal, Theme.Spacing.s4)
                .padding(.vertical, Theme.Spacing.s3)
                .frame(minHeight: Theme.Size.hit)
                .background(Theme.Colors.bgRaised, in: .continuous(Theme.Radius.banner))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 0.5))
                .shadow(color: Theme.Colors.scrim.opacity(0.5), radius: 12, y: 4)
                .padding(.horizontal, Theme.Spacing.s3)
                .padding(.bottom, 96)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .gesture(DragGesture().onEnded { if $0.translation.height > 20 { toasts.dismiss() } })
            }
        }
        .animation(.snappy, value: toasts.current)
    }
}
