import SwiftUI
import Observation
import LiftCore

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
    private var window = UndoWindow<UUID>()
    /// Deferred commits (e.g. deleting a discarded workout), run when the
    /// window ends, a newer toast replaces it, or the toast is swiped away.
    private var commits: [UUID: () -> Void] = [:]
    private var dismissTask: Task<Void, Never>?

    /// - Parameters:
    ///   - undo: restores the previous state inside the 5 s window.
    ///   - onCommit: makes the action final once it can no longer be undone.
    func show(_ message: String, undo: (() -> Void)? = nil, onCommit: (() -> Void)? = nil) {
        let toast = Toast(message: message, undo: undo)
        if let previous = window.begin(toast.id, at: Date()) { commit(previous) }
        if let onCommit { commits[toast.id] = onCommit }
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(UndoWindow<UUID>.defaultDuration) + .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            if let id = self.window.expire(at: Date()) { self.commit(id) }
            if self.current?.id == toast.id { self.current = nil }
        }
    }

    func performUndo() {
        guard let toast = current else { return }
        if window.undo(toast.id, at: Date()) {
            commits[toast.id] = nil
            toast.undo?()
        }
        current = nil
    }

    func dismiss() {
        if let id = window.flush() { commit(id) }
        current = nil
    }

    /// Call when the app goes to the background so nothing stays half-done.
    func flush() { dismiss() }

    private func commit(_ id: UUID) {
        commits.removeValue(forKey: id)?()
    }
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
