import SwiftUI

/// Filter chips with the @arnab_design chip-morph: tapping a chip grows the
/// options sheet out of that chip; closing folds the selection back into the
/// chip bar (the chip then reads "Lats" or "Lats +2").
struct FilterGroup: Identifiable {
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }
    struct Section: Identifiable {
        let title: String?
        let options: [Option]
        var id: String { title ?? options.first?.id ?? "" }
    }
    let id: String
    let title: String
    let sections: [Section]

    func label(for id: String) -> String? { sections.flatMap(\.options).first { $0.id == id }?.label }
}

struct ChipMorphBar: View {
    let groups: [FilterGroup]
    @Binding var selection: [String: Set<String>]
    @Binding var open: String?
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s2) {
                ForEach(groups) { group in
                    let picked = selection[group.id] ?? []
                    Button {
                        withAnimation(Theme.Motion.springBanner) { open = group.id }
                    } label: {
                        HStack(spacing: Theme.Spacing.s1) {
                            Text(chipText(group, picked))
                                .font(.subheadline.weight(picked.isEmpty ? .regular : .semibold).monospacedDigit())
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(picked.isEmpty ? Theme.Colors.textPrimary : Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.s3)
                        .frame(minHeight: Theme.Size.hit)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(picked.isEmpty ? Theme.Colors.bgSunken : Theme.Colors.accentSoft)
                                .matchedGeometryEffect(id: "chip.\(group.id)", in: namespace, isSource: open != group.id)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(open == group.id ? 0 : 1)
                    .accessibilityLabel("\(group.title) filter, \(picked.isEmpty ? "all" : chipText(group, picked))")
                }
                if selection.values.contains(where: { !$0.isEmpty }) {
                    Button("Clear") { withAnimation(Theme.Motion.springBanner) { selection = [:] } }
                        .buttonStyle(TextActionStyle())
                }
            }
            .screenMargins()
        }
    }

    private func chipText(_ g: FilterGroup, _ picked: Set<String>) -> String {
        guard let first = picked.sorted().first.flatMap(g.label(for:)) else { return g.title }
        return picked.count == 1 ? first : "\(first) +\(picked.count - 1)"
    }
}

/// The expanded options panel. Place it in an overlay over the same container
/// as the bar so the matched geometry can grow out of the chip.
struct ChipMorphPanel: View {
    let group: FilterGroup
    @Binding var selection: [String: Set<String>]
    @Binding var open: String?
    let namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                HStack {
                    Text(group.title).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if !(selection[group.id] ?? []).isEmpty {
                        Button("Clear") { selection[group.id] = [] }.buttonStyle(TextActionStyle())
                    }
                    Button("Done", action: close).buttonStyle(TextActionStyle()).fontWeight(.semibold)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                        ForEach(group.sections) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                                if let title = section.title { Text(title).sectionLabel() }
                                FlowLayout(spacing: Theme.Spacing.s2) {
                                    ForEach(section.options) { option in optionChip(option) }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            .padding(Theme.Spacing.s4)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous)
                    .fill(Theme.Colors.bgRaised)
                    .matchedGeometryEffect(id: "chip.\(group.id)", in: namespace)
                    .shadow(color: Theme.Colors.scrim, radius: 18, y: 8)
            }
            .padding(.horizontal, Theme.Spacing.s3)
            .transition(.opacity)
        }
    }

    private func optionChip(_ option: FilterGroup.Option) -> some View {
        let on = selection[group.id, default: []].contains(option.id)
        return Button {
            Haptics.step()
            if on { selection[group.id, default: []].remove(option.id) } else { selection[group.id, default: []].insert(option.id) }
        } label: {
            HStack(spacing: Theme.Spacing.s1) {
                if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(option.label).font(.subheadline)
            }
            .foregroundStyle(on ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.s3)
            .frame(minHeight: Theme.Size.hit)
            .background(on ? Theme.Colors.accent : Theme.Colors.bgSunken, in: .continuous(Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func close() {
        withAnimation(Theme.Motion.springBanner) { open = nil }
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
