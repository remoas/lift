import SwiftUI
import LiftCore

/// The logging control: a ring, never a checkbox. 44 pt hit area.
struct TickRing: View {
    let state: SetRowState
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { state == .current ? Theme.Size.ringCurrent : Theme.Size.ring }
    private var filled: Bool { state == .done || state == .best }
    private var fill: Color { state == .best ? Theme.Colors.accent : Theme.Colors.textPrimary }
    private var stroke: Color {
        switch state {
        case .current: return Theme.Colors.accent
        case .upcoming: return Theme.Colors.controlStroke
        case .done: return Theme.Colors.textPrimary
        case .best: return Theme.Colors.accent
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(stroke, lineWidth: Theme.Size.ringStroke)
                Circle()
                    .fill(fill)
                    .scaleEffect(filled ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(state == .best ? Theme.Colors.onAccent : Theme.Colors.bgCanvas)
                    .opacity(filled ? 1 : 0)
            }
            .frame(width: diameter, height: diameter)
            .frame(width: Theme.Size.hit, height: Theme.Size.hit)
            .contentShape(Rectangle())
            .animation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.springTick, value: state)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: filled)
        .accessibilityLabel(filled ? "Logged" : "Log set")
        .accessibilityHint(filled ? "Double tap to undo" : "")
    }
}
