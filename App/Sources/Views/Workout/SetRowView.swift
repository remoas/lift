import SwiftUI
import LiftCore

/// One set row, driven only by `SetRowModel` (no phone layout assumptions
/// beyond stacking at accessibility sizes).
struct SetRowView: View {
    let model: SetRowModel
    var onValue: () -> Void
    var onTick: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Stacked: value + ring on line 1, last time on line 2.
                VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                    HStack(spacing: Theme.Spacing.s3) {
                        number
                        value
                        Spacer(minLength: 0)
                        ring
                    }
                    if model.lastTime != nil { lastTime.padding(.leading, Theme.Spacing.s7) }
                }
            } else {
                HStack(spacing: Theme.Spacing.s3) {
                    number.frame(width: 24, alignment: .leading)
                    if model.lastTime != nil { lastTime.frame(width: 92, alignment: .leading) }
                    value
                    Spacer(minLength: 0)
                    ring
                }
            }
        }
        .frame(minHeight: Theme.Size.setRow)
        .padding(.horizontal, Theme.Spacing.s3)
        .background {
            if model.state == .current {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).fill(Theme.Colors.accentSoft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAction(named: model.isDone ? "Undo" : "Log set", onTick)
        .accessibilityAction(named: "Edit", onValue)
        .accessibilityIdentifier(model.state == .current ? "current-set" : "set-row")
    }

    private var number: some View {
        Text(model.kind == .working ? "\(model.number)" : model.kind.shortLabel)
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    private var lastTime: some View {
        Text(model.lastTime ?? "—")
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
    }

    private var value: some View {
        Button(action: onValue) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s1) {
                    if model.weightText == nil {
                        Text("Add weight").font(.body.weight(.semibold))
                            .foregroundStyle(model.state == .current ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        Text("× \(model.reps)").font(Theme.Fonts.setValue)
                    } else if model.loadKind != .loaded {
                        // "Bodyweight × 12" or "BW + 25 lb × 8", never "0 lb × 12".
                        Text(LoadText.pair(weight: model.weight, unit: model.unit, reps: model.reps, kind: model.loadKind))
                            .font(Theme.Fonts.setValue)
                    } else if let w = model.weightText {
                        Text(w).font(Theme.Fonts.setValue)
                        Text(model.unit.symbol).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                        Text("× \(model.reps)").font(Theme.Fonts.setValue)
                    }
                    if model.state == .best {
                        Text("Best")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.leading, Theme.Spacing.s1)
                    }
                }
                .foregroundStyle(model.state == .upcoming ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .fontWeight(model.state == .upcoming ? .medium : .semibold)
                // One line at AX sizes: shrink rather than split "180" across lines.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Anchors for the PR banner morph (§8.5): the banner starts here.
                // Where the PR banner lifts from and lands back on (§8.5, QA run 2 #10).
                // A geometry callback, not matchedGeometryEffect: List cells are reused,
                // and a reused cell's match source pointed the ghost at the wrong set.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { SetValueFrames.shared.frames[model.id] = $0 }
                if let secondary = model.secondary {
                    Text(secondary).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(minHeight: Theme.Size.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ring: some View {
        TickRing(state: model.state, action: onTick)
    }
}
