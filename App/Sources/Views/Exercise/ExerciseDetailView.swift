import SwiftUI
import SwiftData
import Charts
import UIKit
import LiftCore

/// §3.8 Exercise detail: e1RM chart, bests, note, history and settings.
struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var range: ChartRange = .threeMonths
    @State private var selected: Date?

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    private var media: ExerciseMedia? {
        #if DEBUG
        if Fixtures.mediaMode == .hidden { return nil }
        #endif
        return exercise.mediaRef.flatMap(ExerciseMedia.init(key:))
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .id("exercise-detail-range")
    }

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "1M", threeMonths = "3M", year = "1Y", all = "All"
        var id: String { rawValue }
        var days: Double? {
            switch self { case .month: return 31; case .threeMonths: return 92; case .year: return 366; case .all: return nil }
        }
    }

    private var unit: WeightUnit { exercise.unit(global: settings.unit) }
    private var logged: [LoggedSet] { LiftStore.history(for: exercise).compactMap(\.logged) }
    private var sessions: [(workoutID: UUID, date: Date, e1RMKg: Double, set: SetSnapshot)] {
        let all = History.e1RMSeries(for: exercise.id, in: logged)
        guard let days = range.days else { return all }
        let cutoff = Date().addingTimeInterval(-days * 86_400)
        return all.filter { $0.date >= cutoff }
    }
    private var workoutCount: Int { Set(logged.map(\.snapshot.workoutID)).count }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                if let media {
                    ExerciseMediaHeader(media: media)
                        // insetGrouped insets 16 pt; 4 more each side = 20 pt (353 pt on a 393 pt screen).
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.s2, leading: 4, bottom: 0, trailing: 4))
                        .listRowSeparator(.hidden)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                    Text(exercise.name).font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(exercise.equipment.label) · \(unit.symbol)").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    lede.font(.body).foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.s2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowSeparator(.hidden)
                if workoutCount > 0, exercise.loadKind == .loaded {
                    // Range control always sits under the date axis, whether or
                    // not the exercise has a clip (Pendulum Row and Bench).
                    // Bodyweight / assisted lifts have no meaningful 0 lb e1RM (AC 119).
                    chart.listRowSeparator(.hidden)
                    rangePicker.listRowSeparator(.hidden)
                }
            }
            .listRowBackground(Theme.Colors.bgCanvas)

            Section {
                if workoutCount < 2 {
                    Text("Bests appear after your second session, so day one never counts as a fake record.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    bests
                }
            } header: { Text("Bests").textCase(nil).foregroundStyle(Theme.Colors.textTertiary) }
            // Plain rows with hairlines in light and dark (QA quick-log 14).
            .listRowBackground(Theme.Colors.bgCanvas)

            Section {
                TextField("A cue for next time", text: $exercise.note, axis: .vertical)
                    .onSubmit { _ = LiftStore.save(context) }
            } header: { Text("Note").textCase(nil).foregroundStyle(Theme.Colors.textTertiary) }

            if !logged.isEmpty {
                Section { history } header: { Text("History").textCase(nil).foregroundStyle(Theme.Colors.textTertiary) }
            }

            Section { settingsRows } header: { Text("Settings for this exercise").textCase(nil).foregroundStyle(Theme.Colors.textTertiary) }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bgCanvas)
        // Safe-area inset plus 16 pt so the last Settings row clears the
        // home indicator by that amount when the list is scrolled to the
        // bottom (CDO: Heaviest may stay a mid-list row at scroll-top).
        .safeAreaPadding(.bottom, Theme.Spacing.s4)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // A view-level .tint does not recolor the system back link — the
        // bar inherits the app accent from LiftApp. Set the bar tint while
        // this screen is visible; Ember stays on the chart's latest-point
        // dot, which uses Theme.Colors.accent explicitly.
        .background {
            NavigationBarTint(
                color: UIColor(named: "textPrimary") ?? .label,
                restore: UIColor(named: "accent") ?? .systemOrange
            )
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { _ = LiftStore.save(context) }
        #if DEBUG
        .onAppear {
            // 24a scrolled: last Settings row at the bottom, so CDO can
            // measure the home-indicator clearance (safe area + 16 pt).
            if Fixtures.requested == "08c-exercise-bench-range" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    proxy.scrollTo("exercise-detail-range", anchor: .bottom)
                }
            }
            if Fixtures.requested == "24a-media-video-scrolled" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    proxy.scrollTo("exercise-detail-settings-end", anchor: .bottom)
                    // Scrolling can reset the system back link to Ember;
                    // re-apply the same textPrimary tint as the regular 24a frames.
                    let color = UIColor(named: "textPrimary") ?? .label
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap(\.windows)
                        .forEach { $0.liftDescendantNavigationBar()?.tintColor = color }
                }
            }
        }
        #endif
        }
    }

    // MARK: Lede

    @ViewBuilder private var lede: some View {
        if workoutCount == 0 {
            Text("Not logged yet.")
        } else if workoutCount == 1 {
            Text("You've logged this once. Next time, you'll have a number to beat.")
        } else if let latest = sessions.last ?? History.e1RMSeries(for: exercise.id, in: logged).last {
            let all = History.e1RMSeries(for: exercise.id, in: logged)
            let latestText = weight(latest.e1RMKg)
            let recent = all.suffix(3).map(\.e1RMKg)
            if all.count >= 3, let mx = recent.max(), let mn = recent.min(), mx - mn < 0.5 {
                Text("Holding at \(latestText) for 3 sessions.")
            } else if let first = sessions.first, first.workoutID != latest.workoutID {
                let delta = Int(UnitMath.convert(latest.e1RMKg - first.e1RMKg, from: .kg, to: unit).rounded())
                Text("Your estimated max is ") + Text(latestText).fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                    + Text(", \(delta >= 0 ? "up" : "down") \(abs(delta)) since \(first.date.formatted(.dateTime.month(.wide))).")
            } else {
                Text("Your estimated max is ") + Text(latestText).fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary) + Text(".")
            }
        }
    }

    // MARK: Chart

    private var chart: some View {
        let points = sessions
        let selectedPoint = selected.flatMap { d in points.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        return Chart {
            ForEach(points, id: \.workoutID) { p in
                LineMark(x: .value("Date", p.date), y: .value("e1RM", value(p.e1RMKg)))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value("e1RM", value(last.e1RMKg)))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.18)).symbolSize(320)
                PointMark(x: .value("Date", last.date), y: .value("e1RM", value(last.e1RMKg)))
                    .foregroundStyle(Theme.Colors.accent).symbolSize(70)
            }
            if let first = points.first, points.count > 1 {
                PointMark(x: .value("Date", first.date), y: .value("e1RM", value(first.e1RMKg)))
                    .opacity(0)
                    .annotation(position: .top, alignment: .leading) {
                        Text(UnitMath.format(value(first.e1RMKg).rounded())).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
            }
            if let s = selectedPoint {
                RuleMark(x: .value("Date", s.date))
                    .foregroundStyle(Theme.Colors.separator)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Text("\(s.date.formatted(.dateTime.day().month(.abbreviated))) · \(weight(s.e1RMKg)) from \(WeightText.pair(s.set, in: unit, step: unit.defaultStep / 2, kind: exercise.loadKind))")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(Theme.Spacing.s1)
                            .background(Theme.Colors.bgRaised, in: .continuous(Theme.Radius.control))
                    }
            }
        }
        .chartYAxis(.hidden)
        // Tight y range: the line fills the plot, no big empty gap (QA 14).
        .chartYScale(domain: yDomain(points.map { value($0.e1RMKg) }))
        .chartXScale(domain: (points.first?.date ?? Date())...max(Date(), points.last?.date ?? Date()))
        .chartXAxis {
            // Start month on the left, "Today" on the right.
            AxisMarks(values: [points.first?.date, Date()].compactMap { $0 }) { v in
                AxisValueLabel(anchor: (v.index == 0) ? .topLeading : .topTrailing) {
                    if let d = v.as(Date.self) {
                        Text(v.index == 0 ? d.formatted(.dateTime.month(.abbreviated)) : "Today")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .sensoryFeedback(.selection, trigger: selectedPoint?.workoutID)
        .frame(height: 180)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5).padding(.bottom, 24) }
        .accessibilityLabel("Estimated max over time")
    }

    private func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 2.5)
        return (lo - pad)...(hi + pad)
    }

    private func value(_ kg: Double) -> Double { UnitMath.convert(kg, from: .kg, to: unit) }
    private func weight(_ kg: Double) -> String { "\(UnitMath.format(value(kg).rounded())) \(unit.symbol)" }

    // MARK: Bests

    @ViewBuilder private var bests: some View {
        let kind = exercise.loadKind
        let working = logged.filter { $0.snapshot.kind.countsForRecords }.map(\.snapshot)
        let heaviest = kind == .assisted
            ? working.min(by: { $0.weightKg < $1.weightKg })
            : working.max(by: { $0.weightKg < $1.weightKg })
        if let heaviest {
            bestRow("Heaviest", LoadText.pair(weight: heaviest.weight, unit: heaviest.unit, reps: heaviest.reps, kind: kind), heaviest.date)
        }
        if kind == .loaded, let e = working.filter({ $0.e1RMKg != nil }).max(by: { $0.e1RMKg! < $1.e1RMKg! }) {
            bestRow("Estimated max", weight(e.e1RMKg!), e.date)
        }
        if let top = heaviest {
            let atTop = working.filter { abs($0.weightKg - top.weightKg) <= PRDetector.toleranceKg }
            if let most = atTop.max(by: { $0.reps < $1.reps }) {
                let label = kind == .loaded ? "Most reps at \(UnitMath.format(top.weight))" : "Most reps at \(LoadText.pair(weight: top.weight, unit: top.unit, reps: top.reps, kind: kind).replacingOccurrences(of: " × \(top.reps)", with: ""))"
                bestRow(label, "\(most.reps)", most.date)
            }
        }
        if kind == .loaded, let v = working.max(by: { $0.volumeKg < $1.volumeKg }) {
            bestRow("Biggest set", "\(Int(value(v.volumeKg).rounded()).formatted()) \(unit.symbol)", v.date)
        }
    }

    private func bestRow(_ label: String, _ value: String, _ date: Date) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(value).font(Theme.Fonts.bodyNumber).foregroundStyle(Theme.Colors.textPrimary)
            Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.day().month(.abbreviated)))
                .font(Theme.Fonts.bodyNumber).foregroundStyle(Theme.Colors.textSecondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .frame(minHeight: Theme.Size.groupedRow)
    }

    // MARK: History

    private var history: some View {
        let byWorkout = Dictionary(grouping: LiftStore.history(for: exercise)) { $0.workout?.id }
        let workouts = byWorkout.values.compactMap(\.first?.workout).sorted { $0.startedAt > $1.startedAt }.prefix(10)
        return ForEach(Array(workouts), id: \.id) { w in
            let sets = (byWorkout[w.id] ?? []).sorted { $0.order < $1.order }
            VStack(alignment: .leading, spacing: 2) {
                Text(w.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                Text(sets.map { LoadText.pair(weight: $0.weight, unit: $0.unit, reps: $0.reps, kind: exercise.loadKind, style: exercise.loadKind == .loaded ? .tightest : .full) }.joined(separator: ", "))
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(minHeight: Theme.Size.groupedRow, alignment: .leading)
        }
    }

    // MARK: Settings

    @ViewBuilder private var settingsRows: some View {
        Stepper("Rep goal \(exercise.repGoal)", value: $exercise.repGoal, in: 3...30).monospacedDigit().frame(minHeight: Theme.Size.hit)
        Stepper(value: Binding(get: { exercise.restSec ?? settings.workingRestSeconds }, set: { exercise.restSec = $0 }), in: 15...600, step: 15) {
            Text("Rest \(RestCountdown.format(TimeInterval(exercise.restSec ?? settings.workingRestSeconds)))").monospacedDigit()
        }
        .frame(minHeight: Theme.Size.hit)
        Stepper(value: Binding(get: { exercise.step(for: unit) }, set: { exercise.plateStep = $0 }), in: 0.5...20, step: unit == .kg ? 1.25 : 2.5) {
            Text("Plate step \(UnitMath.format(exercise.step(for: unit))) \(unit.symbol)").monospacedDigit()
        }
        .frame(minHeight: Theme.Size.hit)
        Picker("Unit", selection: Binding(get: { exercise.unitOverride }, set: { exercise.unitOverride = $0; exercise.plateStep = nil })) {
            Text("Use default (\(settings.unit.symbol))").tag(WeightUnit?.none)
            ForEach(WeightUnit.allCases) { Text($0.symbol).tag(WeightUnit?.some($0)) }
        }
        .id("exercise-detail-settings-end")
    }
}

/// Recolors the system back link on this screen only, then restores the app accent.
/// A SwiftUI `.tint` on the destination does not reach the bar, so this walks
/// up to the `UINavigationBar` in the host window.
private struct NavigationBarTint: UIViewRepresentable {
    var color: UIColor
    var restore: UIColor

    func makeCoordinator() -> Coordinator { Coordinator(restore: restore) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.restore = restore
        let apply: () -> Void = { _ = view.liftNavigationBar().map { $0.tintColor = color } }
        DispatchQueue.main.async(execute: apply)
        // List scrolling can reset the system bar to the app accent
        // (the 24a scrolled fixture showed Friday in Ember after scrollTo).
        // Re-apply after the next layouts; screenshots wait 2.5s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: apply)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        view.liftNavigationBar()?.tintColor = coordinator.restore
    }

    final class Coordinator {
        var restore: UIColor
        init(restore: UIColor) { self.restore = restore }
    }
}

private extension UIView {
    func liftNavigationBar() -> UINavigationBar? {
        var current: UIView? = self
        while let view = current {
            if let bar = view as? UINavigationBar { return bar }
            if let nav = view.next as? UINavigationController { return nav.navigationBar }
            current = view.superview
        }
        return window?.liftDescendantNavigationBar()
    }

    func liftDescendantNavigationBar() -> UINavigationBar? {
        if let bar = self as? UINavigationBar { return bar }
        for sub in subviews {
            if let bar = sub.liftDescendantNavigationBar() { return bar }
        }
        return nil
    }
}
