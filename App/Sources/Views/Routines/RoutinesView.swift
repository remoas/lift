import SwiftUI
import SwiftData
import LiftCore

/// §3.7 Routines. No filled primary on this screen.
struct RoutinesView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]
    @State private var editing: Routine?
    @State private var changingDays = false

    private var next: Routine? { LiftStore.nextRoutine(routines: routines, finished: finished) }
    private var anyEmpty: Bool { routines.contains { $0.sortedItems.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                        Text("Routines").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
                        (Text("Push, Pull, Legs, then round again. ") + Text("\(settings.daysPerWeek) days a week.").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                         + Text(anyEmpty ? " Add exercises to each whenever you like." : ""))
                            .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(routines) { r in
                        Button { editing = r } label: { row(r) }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.Colors.bgCanvas)
                    }
                    .onMove { from, to in
                        var list = routines
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, r) in list.enumerated() { r.order = i }
                    }
                }
                Section {
                    Button("Change days a week") { changingDays = true }.buttonStyle(TextActionStyle())
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bgCanvas)
            .sheet(item: $editing) { r in
                NavigationStack {
                    BuildDayView(routine: r, context: .sheet, onDone: { editing = nil })
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $changingDays) {
                DaysStep(onPicked: { changingDays = false }, eyebrow: nil)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func row(_ r: Routine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.s2) {
                Text(r.name).font(Theme.Fonts.exercise).foregroundStyle(Theme.Colors.textPrimary)
                if r.id == next?.id { Text("Next").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Colors.accent) }
            }
            if r.sortedItems.isEmpty {
                HStack(spacing: Theme.Spacing.s1) {
                    Text("No exercises yet ·").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    Button("Add exercises") { editing = r }.buttonStyle(TextActionStyle()).font(.subheadline)
                }
            } else {
                Text(ListFormatter.localizedString(byJoining: r.sortedItems.compactMap { $0.exercise?.name }) + ".")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.setRow, alignment: .leading)
        .contentShape(Rectangle())
    }
}
