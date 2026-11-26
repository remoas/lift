import SwiftUI
import SwiftData
import LiftCore
import os

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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Fixture 18a2 only: scroll to the Recents/Common boundary with the keyboard down.
    @State private var scrollTarget: UUID?
    @State private var scrollAnchor: UnitPoint = .center

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
        /// Match-reason meta ("RDL"): leads the detail line when the name doesn't explain the match.
        var alias: String? = nil
        var mediaRef: String? = nil
        var primary: [MuscleGroup] = []
        var id: UUID { choice.id }
    }

    @State private var entries: [SearchEntry] = []
    @State private var choices: [UUID: Choice] = [:]
    /// Cached search results: computed once per query/filter change, not per body pass.
    @State private var results: [Item] = []
    /// The top hit was an exact name or alias match: no Create row (AC 96).
    @State private var hasExact = false
    @State private var announce: Task<Void, Never>?
    @State private var filters: [String: Set<String>] = [:]
    @State private var openFilter: String?
    @Namespace private var chipSpace

    private var isMulti: Bool { if case .swap = mode { return false } else { return true } }

    /// The bundled library tokenised once per launch; each open only adds usage (§10.2 performance).
    @MainActor static let libraryIndex: [SearchEntry] = ExerciseLibrary.bundled.exercises.map { SearchEntry(library: $0) }
    @MainActor static let libraryByID: [String: LibraryExercise] = Dictionary(uniqueKeysWithValues: ExerciseLibrary.bundled.exercises.map { ($0.id, $0) })
    private static let signposter = OSSignposter(subsystem: "com.benspink.lift", category: "LiftSearch")

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

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// Workouts in the last 90 days with a done set, and the last time (§10.2 usage).
    private func usage(_ ex: Exercise, now: Date = Date()) -> SearchUsage? {
        let done = (ex.sets ?? []).filter { $0.isDone && $0.workout?.endedAt != nil }
        guard let last = done.compactMap(\.doneAt).max() else { return nil }
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let workouts = Set(done.filter { ($0.doneAt ?? .distantPast) >= cutoff }.compactMap { $0.workout?.id })
        return SearchUsage(count: workouts.count, last: last)
    }

    /// Builds the search index once per change: DB rows (with usage) plus library
    /// entries that haven't been materialised yet.
    private func rebuildIndex() {
        var map: [UUID: Choice] = [:]
        var list: [SearchEntry] = []
        for ex in exercises {
            map[ex.id] = .row(ex)
            let u = usage(ex)
            if let lid = ex.libraryID, let lib = Self.libraryByID[lid] {
                list.append(SearchEntry(library: lib, id: ex.id, usage: u))
            } else {
                list.append(SearchEntry(id: ex.id, name: ex.name, aliases: ex.aliases, primary: ex.primaryMuscles,
                                        secondary: ex.secondaryMuscles, equipment: ex.equipment, usage: u))
            }
        }
        for entry in Self.libraryIndex where map[entry.id] == nil { list.append(entry) }
        for lib in ExerciseLibrary.bundled.exercises where map[lib.rowID] == nil { map[lib.rowID] = .library(lib) }
        if case .swap(let old) = mode { list.removeAll { $0.id == old.id } }
        entries = list
        choices = map
        refresh()
        #if DEBUG
        // 18a2: the last Recents row whole, under the opaque sticky header, then Common.
        // 18a3: further down, to the All exercises header (qa-search run 2, Should 4).
        if Fixtures.requested == "18a2-picker-empty-scrolled" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollAnchor = UnitPoint(x: 0.5, y: 0.22); scrollTarget = recent.last?.id ?? common.first?.id }
        }
        if Fixtures.requested == "18a3-picker-empty-all" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollAnchor = UnitPoint(x: 0.5, y: 0.4); scrollTarget = common.last?.id }
        }
        if let q = Fixtures.pickerQuery, query.isEmpty {
            query = q
            refresh()
            // 18c: the alias search with two picked (QA quick-log 16).
            if Fixtures.requested == "18c-picker-rdl" { selected = Array(results.prefix(2).map(\.choice)) }
        }
        #endif
    }

    private func refresh() {
        let state = Self.signposter.beginInterval("LiftSearch")
        let hits = Search.run(entries, query: query, muscles: muscleFilter, equipment: equipmentFilter)
        results = hits.compactMap(item)
        hasExact = hits.first?.isExact == true
        Self.signposter.endInterval("LiftSearch", state)
        // VoiceOver: the count once typing pauses for 0.5 s (AC 98).
        announce?.cancel()
        guard !trimmed.isEmpty else { return }
        let n = results.count
        announce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(n == 0 ? "No results" : "\(n) result\(n == 1 ? "" : "s")").post()
        }
    }

    private var muscleFilter: Set<MuscleGroup> { Set((filters["muscle"] ?? []).compactMap(MuscleGroup.init(rawValue:))) }
    private var equipmentFilter: Set<Equipment> { Set((filters["equipment"] ?? []).compactMap(Equipment.init(rawValue:))) }
    private var hasChips: Bool { !muscleFilter.isEmpty || !equipmentFilter.isEmpty }
    private var isTyping: Bool { !trimmed.isEmpty }

    private func item(_ hit: SearchHit) -> Item? {
        let e = hit.entry
        guard let c = choices[e.id] else { return nil }
        let detail: String
        let media: String?
        switch c {
        case .row(let ex):
            detail = detailLine(last: lastText(ex), e, hint: hit.matchedAlias != nil)
            media = ex.mediaRef
        case .library(let l):
            detail = detailLine(last: nil, e, hint: hit.matchedAlias != nil)
            media = l.mediaRef
        }
        return Item(choice: c, name: e.name, detail: detail, alias: hit.matchedAlias, mediaRef: media, primary: e.primary)
    }

    /// Last set or "Not logged yet", then equipment and one muscle; with a hint, no muscle (qa-search Should 1).
    private func detailLine(last: String?, _ e: SearchEntry, hint: Bool) -> String {
        let tags = ([e.equipment.label] + (hint ? [] : e.primary.prefix(1).map(\.label))).joined(separator: ", ")
        return [last ?? "Not logged yet", tags].joined(separator: " · ")
    }

    /// Last 8 logged, most recent first: "Last 185 × 8 · Mon" (§10.6).
    private var recent: [Item] {
        guard !isTyping, !hasChips else { return [] }
        let logged = exercises.compactMap { ex -> (Exercise, Date)? in
            if case .swap(let old) = mode, old.id == ex.id { return nil }
            guard let d = (ex.sets ?? []).filter({ $0.isDone && $0.workout?.endedAt != nil }).compactMap(\.doneAt).max() else { return nil }
            return (ex, d)
        }
        return logged.sorted { $0.1 > $1.1 }.prefix(8).map { ex, date in
            Item(choice: .row(ex), name: ex.name,
                 detail: ([lastText(ex)].compactMap { $0 } + [Self.ago(date)]).joined(separator: " · "),
                 mediaRef: ex.mediaRef, primary: ex.primaryMuscles)
        }
    }

    /// The 22 Common lifts in popularityRank order, minus Recents.
    private var common: [Item] {
        guard !isTyping, !hasChips else { return [] }
        let lib = ExerciseLibrary.bundled
        var ids: [String] = []
        for day in lib.common.keys.sorted() { for id in lib.common[day] ?? [] where !ids.contains(id) { ids.append(id) } }
        let inRecents = Set(recent.map(\.id))
        let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { Self.libraryByID[$0] }
            .sorted { ($0.popularityRank ?? 1_000_000) < ($1.popularityRank ?? 1_000_000) }
            .compactMap { l in
                let rowID = choices.keys.contains(l.rowID) ? l.rowID : nil
                guard let rowID, !inRecents.contains(rowID), let e = entriesByID[rowID] else { return nil }
                return item(SearchHit(entry: e, tier: 0, matchedAlias: nil))
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

    private func lastPair(_ ex: Exercise) -> String? {
        let last = LiftStore.lastSessionSets(for: ex).filter { $0.kind.countsForRecords }
        guard let top = last.max(by: { $0.snapshot.weightKg < $1.snapshot.weightKg }) else { return nil }
        let unit = ex.unit(global: settings.unit)
        return WeightText.pair(top.snapshot, in: unit, step: ex.step(for: unit), bodyweight: ex.equipment == .bodyweight)
    }

    private func lastText(_ ex: Exercise) -> String? { lastPair(ex).map { "Last \($0)" } }

    /// Return key (AC 97).
    private func submit() {
        guard let top = results.first else {
            if isTyping { creating = true }
            return
        }
        switch mode {
        case .swap:
            commit([top.choice])
        case .add where selected.isEmpty:
            commit([top.choice])
        case .add:
            if !selected.contains(top.choice) { toggle(top.choice) }
            query = ""
            searchFocused = true
        }
    }

    // MARK: Body

    private var createRow: some View {
        Button { creating = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Create “\(trimmed)”").foregroundStyle(Theme.Colors.accent)
                Text("A custom exercise, yours to name and set up").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Size.setRow, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.Colors.bgRaised)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            // At AX sizes the subtitle steps aside while typing; it's the Add bar's hint instead.
            if !(typeSize.isAccessibilitySize && isTyping) {
                Text(subtitleLine).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .screenMargins()
            }
            // AX sizes while typing: the chips step aside rather than clip "Equipment" at
            // the edge, and the first result gets the room (qa-search run 2, Must 3).
            if !(typeSize.isAccessibilitySize && isTyping) {
                ChipMorphBar(groups: Self.filterGroups, selection: $filters, open: $openFilter, namespace: chipSpace)
                    .padding(.vertical, Theme.Spacing.s2)
            }
            ScrollViewReader { proxy in
            List {
                if isTyping {
                    // Results replace the sections: no header, no Recents (logged matches float up).
                    if results.isEmpty {
                        Text("No exercise called “\(trimmed)”.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                            .listRowBackground(Theme.Colors.bgRaised)
                    }
                    ForEach(results) { row($0) }
                    if !hasExact { createRow }
                } else if hasChips {
                    Section { ForEach(results) { row($0) } } header: { header("\(results.count) exercises") }
                } else {
                    if !recent.isEmpty { Section { ForEach(recent) { row($0) } } header: { header("Recents") } }
                    if !common.isEmpty { Section { ForEach(common) { row($0) } } header: { header("Common") } }
                    Section { ForEach(results) { row($0) } } header: { header("All exercises") }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(0)
            .scrollContentBackground(.hidden)
            // First row 8 pt under the chips (the chips' own padding); no extra top inset.
            .contentMargins(.top, 0, for: .scrollContent)
            // The Add bar never covers the last visible row's detail (qa-search Must 3, Nit 3).
            .contentMargins(.bottom, isMulti && !selected.isEmpty ? Theme.Size.primaryButton + Theme.Spacing.s2 + 12 : 0, for: .scrollContent)
            .transaction { $0.animation = nil }   // no reorder animation while typing (§10.6)
            .onChange(of: query) { if let first = results.first?.id { proxy.scrollTo(first, anchor: .top) } }
            .onChange(of: scrollTarget) { if let t = scrollTarget { proxy.scrollTo(t, anchor: scrollAnchor) } }
            }
            }
            .background(Theme.Colors.bgRaised)
            .overlay(alignment: .top) {
                if let id = openFilter, let group = Self.filterGroups.first(where: { $0.id == id }) {
                    ChipMorphPanel(group: group, selection: $filters, open: $openFilter, namespace: chipSpace)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .modifier(KeepTitleWhileSearching())
            .onSubmit(of: .search) { submit() }
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
                        .accessibilityHint(subtitle)
                        .disabled(selected.isEmpty)
                        .screenMargins()
                        .padding(.bottom, Theme.Spacing.s2)
                        .background(Theme.Colors.bgRaised)
                }
            }
            .sheet(isPresented: $creating) {
                CreateExerciseForm(initialName: trimmed) { ex in
                    creating = false
                    commit([.row(ex)])
                }
            }
            .onAppear {
                #if DEBUG
                if Fixtures.requested == "18a2-picker-empty-scrolled" || Fixtures.requested == "18a3-picker-empty-all" { return }
                #endif
                searchFocused = true
            }
            .task(id: exercises.count) { rebuildIndex() }
            .onChange(of: query) { refresh() }
            .onChange(of: filters) { refresh() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Section headers: secondary text, sentence case (6.75:1 on white; qa-search Must 4).
    private func header(_ title: String) -> some View {
        // Opaque, so a row scrolling under the sticky header is hidden, not overprinted (Should 4).
        Text(title).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary).textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.s5)
            .padding(.vertical, 6)
            .background(Theme.Colors.bgRaised)
            .listRowInsets(EdgeInsets())
    }

    /// Keeps the mode visible when the nav title can't be (iOS 17.0).
    private var subtitleLine: String {
        if #available(iOS 17.1, *) { return subtitle }
        return "\(title) · \(subtitle)"
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
            Group {
                if typeSize.isAccessibilitySize {
                    // AX: stacked (qa-search run 2, Must 3). The title has its own lines with
                    // the tick ring on its first line; the detail runs full width below,
                    // clear of the ring, ending at a word boundary rather than clipping.
                    VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s2) {
                            Text(item.name).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if isMulti {
                                TickRing(state: isSelected ? .done : .upcoming) { toggle(item.choice) }
                            }
                        }
                        DetailAtWords(parts: detailParts(item))
                            .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, Theme.Spacing.s2)
                } else {
                    HStack(spacing: Theme.Spacing.s3) {
                        ExerciseThumb(mediaRef: item.mediaRef, primary: item.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            // Title is the name only (§10.5); the alias leads the detail line.
                            Text(item.name).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                            // One line, truncating (§10.5).
                            Text(detailParts(item).joined(separator: " · "))
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                        if isMulti {
                            TickRing(state: isSelected ? .done : .upcoming) { toggle(item.choice) }
                        }
                    }
                    // A 44 pt thumb and two lines in ~60 pt (Should 1; was 78).
                    .padding(.vertical, Theme.Spacing.s2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.s5, bottom: 0, trailing: Theme.Spacing.s4))
        .listRowBackground(Theme.Colors.bgRaised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([item.name, item.alias.map { "matches \($0)" }, item.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "RDL", "Last 200 × 8", "Barbell, Hamstrings": the pieces the detail line may end between.
    private func detailParts(_ item: Item) -> [String] {
        [item.alias].compactMap { $0 } + item.detail.components(separatedBy: " · ")
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

/// The sheet keeps "Add exercise" / "Swap …" in the nav bar while searching (iOS 17.1+).
private struct KeepTitleWhileSearching: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.1, *) {
            content.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            content
        }
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

/// AX detail: wraps over up to two lines; if even that is too long, it drops
/// trailing pieces (then trailing words) and ends with "…" at a word boundary,
/// never clipping mid-word (qa-search run 2, Must 3).
private struct DetailAtWords: View {
    let parts: [String]
    /// One line of the secondary style at the current size.
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = 20
    var body: some View {
        // Proposes at most two lines; the first candidate whose full height fits wins.
        ViewThatFits(in: .vertical) {
            ForEach(Self.candidates(parts), id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            Text(Self.candidates(parts).last ?? "").lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: line * 2 + 4, alignment: .topLeading)
    }

    static func candidates(_ parts: [String]) -> [String] {
        var out = [parts.joined(separator: " · ")]
        var p = parts
        while p.count > 1 {
            let last = p.removeLast()
            // "Barbell, Hamstrings" → "Barbell…" before the whole piece goes.
            let words = last.components(separatedBy: ", ")
            if words.count > 1 { out.append((p + [words.dropLast().joined(separator: ", ")]).joined(separator: " · ") + "…") }
            out.append(p.joined(separator: " · ") + "…")
        }
        return out
    }
}
