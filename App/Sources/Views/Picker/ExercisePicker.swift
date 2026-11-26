import SwiftUI
import SwiftData
import LiftCore

/// §3.12 exercise picker. Library entries become database rows only when picked.
struct ExercisePicker: View {
    enum Mode: Equatable {
        case add                      // add to today (one tap, or several with checks)
        case swap(Exercise)           // swap in one tap
    }

    let mode: Mode
    var onPick: ([Exercise]) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    @State private var selected: [Choice] = []
    @State private var creating = false
    @FocusState private var searchFocused: Bool

    /// A pick: an existing row or a library entry not yet in the database.
    enum Choice: Hashable, Identifiable {
        case row(Exercise)
        case library(LibraryExercise)
        var id: UUID {
            switch self {
            case .row(let e): return e.id
            case .library(let l): return l.rowID
            }
        }
        static func == (a: Choice, b: Choice) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    private struct Item: Identifiable {
        let choice: Choice
        let name: String
        let detail: String
        var mediaRef: String? = nil
        var primary: [MuscleGroup] = []
        var id: UUID { choice.id }
    }

    @State private var entries: [SearchEntry] = []
    @State private var choices: [UUID: Choice] = [:]
    @State private var names: Set<String> = []
    /// Cached search results: computed once per query/filter change, not per body pass.
    @State private var results: [Item] = []
    @State private var filters: [String: Set<String>] = [:]
    @State private var openFilter: String?
    @Namespace private var chipSpace

    private var isMulti: Bool { if case .swap = mode { return false } else { return true } }

    /// Variant only when it adds something the name doesn't already say ("· incline" hidden).
    static func displayName(_ name: String, variant: String) -> String {
        let v = variant.trimmingCharacters(in: .whitespaces)
        if v.isEmpty || name.localizedCaseInsensitiveContains(v) { return name }
        return "\(name) · \(v)"
    }

    private var title: String {
        switch mode {
        case .add: return "Add exercise"
        case .swap(let ex): return "Swap \(ex.name)"
        }
    }

    private var subtitle: String {
        switch mode {
        case .add: return "Added to today only."
        case .swap(let ex):
            let sets = (ex.sets ?? []).filter { $0.workout?.isActive == true && !$0.isDone }
            let first = sets.first
            _ = first
            return "Keeps \(max(sets.count, 1)) sets. Today only."
        }
    }

    private static let filterGroups: [FilterGroup] = [
        FilterGroup(id: "muscle", title: "Muscle", sections: MuscleGroup.regions.map { region in
            FilterGroup.Section(title: region, options: MuscleGroup.allCases.filter { $0.region == region }.map { .init(id: $0.rawValue, label: $0.label) })
        }),
        FilterGroup(id: "equipment", title: "Equipment", sections: [
            FilterGroup.Section(title: nil, options: Equipment.allCases.map { .init(id: $0.rawValue, label: $0.label) }),
        ]),
    ]

    // MARK: Data

    /// Builds the search index once per change: DB rows plus library entries
    /// that haven't been used yet.
    private func rebuildIndex() {
        var map: [UUID: Choice] = [:]
        var list: [SearchEntry] = []
        for ex in exercises {
            map[ex.id] = .row(ex)
            list.append(ex.searchEntry)
        }
        for lib in ExerciseLibrary.bundled.exercises where map[lib.rowID] == nil {
            map[lib.rowID] = .library(lib)
            list.append(SearchEntry(id: lib.rowID, name: lib.name, variant: lib.variant, aliases: lib.aliases, primary: lib.primaryMuscles, secondary: lib.secondaryMuscles, equipment: lib.equipment))
        }
        if case .swap(let old) = mode { list.removeAll { $0.id == old.id } }
        entries = list
        choices = map
        names = Set(list.map(\.sortKey))
        refresh()
    }

    private func refresh() {
        results = Search.run(entries, query: query, muscles: muscleFilter, equipment: equipmentFilter).compactMap(item)
    }

    private var muscleFilter: Set<MuscleGroup> { Set((filters["muscle"] ?? []).compactMap(MuscleGroup.init(rawValue:))) }
    private var equipmentFilter: Set<Equipment> { Set((filters["equipment"] ?? []).compactMap(Equipment.init(rawValue:))) }
    private var isFiltering: Bool { !query.isEmpty || !muscleFilter.isEmpty || !equipmentFilter.isEmpty }

    private func item(_ e: SearchEntry) -> Item? {
        guard let c = choices[e.id] else { return nil }
        let detail: String
        switch c {
        case .row(let ex): detail = lastText(ex) ?? subtitleTags(e)
        case .library: detail = subtitleTags(e)
        }
        let media: String?
        switch c {
        case .row(let ex): media = ex.mediaRef
        case .library(let l): media = l.mediaRef
        }
        return Item(choice: c, name: displayName(c), detail: detail, mediaRef: media, primary: e.primary)
    }

    private func displayName(_ c: Choice) -> String {
        switch c {
        case .row(let ex): return Self.displayName(ex.name, variant: ex.variant)
        case .library(let l): return Self.displayName(l.name, variant: l.variant)
        }
    }

    private func subtitleTags(_ e: SearchEntry) -> String {
        "Not logged yet · " + ([e.equipment.label] + e.primary.prefix(2).map(\.label)).joined(separator: ", ")
    }

    private var filtered: [Item] { results }

    private var recent: [Item] {
        guard !isFiltering else { return [] }
        let logged = exercises.compactMap { ex -> (Exercise, Date)? in
            guard let d = (ex.sets ?? []).filter({ $0.isDone && $0.workout?.endedAt != nil }).compactMap(\.doneAt).max() else { return nil }
            return (ex, d)
        }
        return logged.sorted { $0.1 > $1.1 }.prefix(12).map { ex, date in
            Item(choice: .row(ex), name: displayName(.row(ex)),
                 detail: ([Self.ago(date)] + [lastPair(ex)].compactMap { $0 }).joined(separator: " · "),
                 mediaRef: ex.mediaRef, primary: ex.primaryMuscles)
        }
    }

    /// "Today", "Yesterday", "3 days ago", then a date.
    static func ago(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2...13: return "\(days) days ago"
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    private var exactMatch: Bool {
        names.contains(Search.fold(query.trimmingCharacters(in: .whitespaces)))
    }

    private func lastPair(_ ex: Exercise) -> String? {
        let last = LiftStore.lastSessionSets(for: ex).filter { $0.kind.countsForRecords }
        guard let top = last.max(by: { $0.snapshot.weightKg < $1.snapshot.weightKg }) else { return nil }
        let unit = ex.unit(global: settings.unit)
        return WeightText.pair(top.snapshot, in: unit, step: ex.step(for: unit))
    }

    private func lastText(_ ex: Exercise) -> String? { lastPair(ex).map { "Last \($0)" } }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            Text(subtitle).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .screenMargins()
            ChipMorphBar(groups: Self.filterGroups, selection: $filters, open: $openFilter, namespace: chipSpace)
                .padding(.vertical, Theme.Spacing.s2)
            List {
                if !recent.isEmpty {
                    Section("Recents") { ForEach(recent) { row($0) } }
                }
                if !filtered.isEmpty {
                    Section(isFiltering ? "\(filtered.count) matches" : "All exercises") { ForEach(filtered) { row($0) } }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty, !exactMatch {
                    Section {
                        if filtered.isEmpty {
                            Text("No match in your library").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Button { creating = true } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create “\(query.trimmingCharacters(in: .whitespaces))”").foregroundStyle(Theme.Colors.accent)
                                Text("A custom exercise, yours to name and set up").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(minHeight: Theme.Size.setRow, alignment: .leading)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            }
            .background(Theme.Colors.bgRaised)
            .overlay(alignment: .top) {
                if let id = openFilter, let group = Self.filterGroups.first(where: { $0.id == id }) {
                    ChipMorphPanel(group: group, selection: $filters, open: $openFilter, namespace: chipSpace)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .modifier(SearchFocus(focused: $searchFocused))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if isMulti, !selected.isEmpty {
                    Button("Add \(selected.count)") { commit(selected) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selected.isEmpty)
                        .screenMargins()
                        .padding(.bottom, Theme.Spacing.s2)
                        .background(Theme.Colors.bgRaised)
                }
            }
            .sheet(isPresented: $creating) {
                CreateExerciseForm(initialName: query.trimmingCharacters(in: .whitespaces)) { ex in
                    creating = false
                    commit([.row(ex)])
                }
            }
            .onAppear { searchFocused = true }
            .task(id: exercises.count) { rebuildIndex() }
            .onChange(of: query) { refresh() }
            .onChange(of: filters) { refresh() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ item: Item) -> some View {
        let isSelected = selected.contains(item.choice)
        return Button {
            switch mode {
            case .swap:
                commit([item.choice])
            case .add where selected.isEmpty:
                // One tap adds and closes; the ring starts a multi-pick.
                commit([item.choice])
            default:
                toggle(item.choice)
            }
        } label: {
            HStack(spacing: Theme.Spacing.s3) {
                ExerciseThumb(mediaRef: item.mediaRef, primary: item.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                    Text(item.detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if isMulti {
                    TickRing(state: isSelected ? .done : .upcoming) { toggle(item.choice) }
                }
            }
            .frame(minHeight: Theme.Size.setRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.Colors.bgRaised)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ choice: Choice) {
        Haptics.step()
        if let i = selected.firstIndex(of: choice) { selected.remove(at: i) } else { selected.append(choice) }
    }

    private func commit(_ choices: [Choice]) {
        let rows: [Exercise] = choices.compactMap { c in
            switch c {
            case .row(let e): return e
            case .library(let lib): return LiftStore.exercise(for: lib, context: context)
            }
        }
        _ = LiftStore.save(context)
        onPick(rows)
        dismiss()
    }
}

/// "Create “{query}”": the same tags as library exercises.
struct CreateExerciseForm: View {
    let initialName: String
    var onCreate: (Exercise) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variant = ""
    @State private var equipment: Equipment = .barbell
    @State private var primary: Set<MuscleGroup> = []
    @State private var secondary: Set<MuscleGroup> = []
    @State private var unit: WeightUnit? = nil
    @State private var repGoal = Target.defaultRepGoal
    @State private var rest = 120
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Variant (wide, neutral, incline 30°…)", text: $variant)
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Unit", selection: $unit) {
                        Text("Use default").tag(WeightUnit?.none)
                        ForEach(WeightUnit.allCases) { Text($0.symbol).tag(WeightUnit?.some($0)) }
                    }
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.Colors.danger) }
                }
                Section("Muscles") {
                    NavigationLink { MusclePicker(title: "Primary", selection: $primary) } label: {
                        LabeledContent("Primary", value: summary(primary))
                    }
                    NavigationLink { MusclePicker(title: "Secondary", selection: $secondary) } label: {
                        LabeledContent("Secondary", value: summary(secondary))
                    }
                }
                Section("Rep goal and rest") {
                    Stepper("Rep goal \(repGoal)", value: $repGoal, in: 3...30).monospacedDigit()
                    Stepper("Rest \(RestCountdown.format(TimeInterval(rest)))", value: $rest, in: 30...300, step: 15).monospacedDigit()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bgSunken)
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add") { create() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .screenMargins()
            }
            .onAppear { name = initialName }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func summary(_ set: Set<MuscleGroup>) -> String {
        let sorted = MuscleGroup.allCases.filter(set.contains)
        guard let first = sorted.first else { return "None" }
        return sorted.count == 1 ? first.label : "\(first.label) +\(sorted.count - 1)"
    }

    private func create() {
        do {
            let ex = try LiftStore.createExercise(
                name: name, variant: variant,
                primary: MuscleGroup.allCases.filter(primary.contains),
                secondary: MuscleGroup.allCases.filter(secondary.contains),
                equipment: equipment, unit: unit, repRange: max(repGoal - 2, 1)...repGoal, rest: rest, context: context)
            ex.repGoal = repGoal
            onCreate(ex)
            dismiss()
        } catch LiftStore.CreateError.duplicate(let existing) {
            error = "You already have \(existing)."
        } catch {
            self.error = "Couldn't create that exercise."
        }
    }
}

struct MusclePicker: View {
    let title: String
    @Binding var selection: Set<MuscleGroup>

    var body: some View {
        List {
            ForEach(MuscleGroup.regions, id: \.self) { region in
                Section(region) {
                    ForEach(MuscleGroup.allCases.filter { $0.region == region }) { m in
                        Button {
                            if selection.contains(m) { selection.remove(m) } else { selection.insert(m) }
                        } label: {
                            HStack {
                                Text(m.label).foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                if selection.contains(m) { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                            }
                            .frame(minHeight: Theme.Size.hit)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

/// `searchFocused` is iOS 18+; on iOS 17 the search field simply isn't auto-focused.
private struct SearchFocus: ViewModifier {
    var focused: FocusState<Bool>.Binding
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.searchFocused(focused)
        } else {
            content
        }
    }
}
