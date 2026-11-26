import SwiftUI
import SwiftData
import LiftCore

/// "What's on {Day}?" — used by quick setup, Today's empty day and Routines.
/// Edits a draft; nothing is written to the routine until the primary is tapped.
struct BuildDayView: View {
    enum Context { case setup(step: Int, total: Int, nextDay: String?), sheet }

    let routine: Routine
    let context: Context
    var onDone: () -> Void
    var onSkip: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @State private var items: [DraftItem] = []
    @State private var rest = 120
    @State private var picking = false
    @State private var loaded = false
    @State private var customFor: DraftItem.ID?

    struct DraftItem: Identifiable, Equatable {
        let id = UUID()
        let exercise: Exercise
        var sets: Int
        var repRange: ClosedRange<Int>
        static func == (a: DraftItem, b: DraftItem) -> Bool { a.id == b.id && a.sets == b.sets && a.repRange == b.repRange }
    }

    private var isSetup: Bool { if case .setup = context { return true } else { return false } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                    if case .setup(let step, let total, _) = context {
                        Text("\(step) of \(total) · \(routine.name)").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    HStack(spacing: 0) {
                        Text("What's on ")
                        Text(routine.name).theBar()
                        Text("?")
                    }
                    .font(Theme.Fonts.display)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.bottom, Theme.Spacing.s2)
                    if items.isEmpty {
                        Text("Add the exercises you do on \(routine.name). Sets and reps go right next to each one.")
                            .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .listRowSeparator(.hidden)
            }
            if !items.isEmpty {
                Section {
                    ForEach($items) { $item in
                        row($item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Remove", role: .destructive) { remove(item) }
                            }
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                        Haptics.step()
                    }
                    Button("Add exercise") { picking = true }
                        .buttonStyle(TextActionStyle())
                    restRow
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bgCanvas)
        .environment(\.editMode, .constant(items.isEmpty ? .inactive : .active))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.s1) {
                if items.isEmpty {
                    Button("Add exercises") { picking = true }.buttonStyle(PrimaryButtonStyle())
                    if isSetup, onSkip != nil {
                        Button("Skip \(routine.name) for now") { onSkip?() }.buttonStyle(TextActionStyle())
                    }
                } else {
                    Button(primaryTitle) { commit(); onDone() }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .screenMargins()
            .padding(.bottom, Theme.Spacing.s2)
            .background(Theme.Colors.bgCanvas)
        }
        .toolbar {
            if isSetup, let onSkip {
                ToolbarItem(placement: .topBarTrailing) { Button("Skip", action: onSkip) }
            } else if !isSetup {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
            }
        }
        .sheet(isPresented: $picking) {
            ExercisePicker(mode: .setup(day: routine.name)) { picked in
                for ex in picked where !items.contains(where: { $0.exercise === ex }) {
                    items.append(DraftItem(exercise: ex, sets: 3, repRange: ex.repRange))
                }
            }
        }
        .onAppear {
            load()
            #if DEBUG
            if Fixtures.requested == "02d-setup-picker" { picking = true }
            #endif
        }
    }

    private var primaryTitle: String {
        switch context {
        case .setup(_, _, let next): return next.map { "Next: \($0)" } ?? "Finish setup"
        case .sheet: return "Save"
        }
    }

    private func row(_ item: Binding<DraftItem>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
            Text(item.wrappedValue.exercise.name).font(.body.weight(.semibold)).foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.s3) {
                HStack(spacing: 0) {
                    Button { item.wrappedValue.sets = max(1, item.wrappedValue.sets - 1); Haptics.step() } label: {
                        Image(systemName: "minus").frame(width: Theme.Size.hit, height: Theme.Size.hit)
                    }
                    .accessibilityLabel("Fewer sets")
                    Text("\(item.wrappedValue.sets) sets").font(Theme.Fonts.bodyNumber).frame(minWidth: 56)
                    Button { item.wrappedValue.sets = min(10, item.wrappedValue.sets + 1); Haptics.step() } label: {
                        Image(systemName: "plus").frame(width: Theme.Size.hit, height: Theme.Size.hit)
                    }
                    .accessibilityLabel("More sets")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.textPrimary)
                .background(Theme.Colors.bgSunken, in: .continuous(Theme.Radius.chip))

                Menu {
                    ForEach(Defaults.repRangePresets, id: \.self) { r in
                        Button("\(r.lowerBound)–\(r.upperBound)") { item.wrappedValue.repRange = r }
                    }
                    Button("Custom…") { customFor = item.wrappedValue.id }
                } label: {
                    Text("\(item.wrappedValue.repRange.lowerBound)–\(item.wrappedValue.repRange.upperBound) reps ▾")
                        .font(Theme.Fonts.bodyNumber)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.s3)
                        .frame(minHeight: Theme.Size.hit)
                        .background(Theme.Colors.bgSunken, in: .continuous(Theme.Radius.chip))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s1)
        .popover(isPresented: Binding(get: { customFor == item.wrappedValue.id }, set: { if !$0 { customFor = nil } })) {
            CustomRangeForm(range: item.repRange).presentationCompactAdaptation(.popover)
        }
    }

    private var restRow: some View {
        Menu {
            ForEach(Array(stride(from: 60, through: 300, by: 15)), id: \.self) { s in
                Button(RestCountdown.format(TimeInterval(s))) { rest = s }
            }
        } label: {
            HStack {
                Text("Rest between sets").foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(RestCountdown.format(TimeInterval(rest))) ▾").font(Theme.Fonts.bodyNumber).foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(minHeight: Theme.Size.groupedRow)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        rest = routine.restSeconds
        items = routine.sortedItems.compactMap { i in i.exercise.map { DraftItem(exercise: $0, sets: i.targetSets, repRange: i.repRange) } }
    }

    private func remove(_ item: DraftItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        toasts.show("\(item.exercise.name) removed") {
            items.insert(item, at: min(index, items.count))
        }
    }

    private func commit() {
        for old in routine.items ?? [] { modelContext.delete(old) }
        for (i, d) in items.enumerated() {
            let ri = RoutineItem(order: i, targetSets: d.sets, repRange: d.repRange, exercise: d.exercise)
            modelContext.insert(ri)
            ri.routine = routine
        }
        routine.restSeconds = rest
        _ = LiftStore.save(modelContext)
    }
}

struct CustomRangeForm: View {
    @Binding var range: ClosedRange<Int>
    @State private var low = 8
    @State private var high = 12

    var body: some View {
        VStack(spacing: Theme.Spacing.s3) {
            Stepper("From \(low)", value: $low, in: 1...50).monospacedDigit()
            Stepper("To \(high)", value: $high, in: low...60).monospacedDigit()
            Button("Use \(low)–\(high)") { range = low...max(low, high) }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.s4)
        .frame(minWidth: 280)
        .onAppear { low = range.lowerBound; high = range.upperBound }
    }
}
