import SwiftUI
import SwiftData
import LiftCore

/// §3.10 Settings: native inset-grouped list.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSyncMonitor.self) private var cloud
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Weights in", selection: $settings.unit) {
                        ForEach(WeightUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show the other unit too", isOn: $settings.showOtherUnit)
                } header: { Text("Units").textCase(nil) } footer: {
                    Text("Each set keeps the unit you logged it in, so switching never changes a record.")
                }

                Section {
                    NavigationLink { PlatesEditor(unit: .lb) } label: {
                        LabeledContent("Pounds", value: plateSummary(settings.plateSetLb)).monospacedDigit()
                    }
                    NavigationLink { PlatesEditor(unit: .kg) } label: {
                        LabeledContent("Kilograms", value: plateSummary(settings.plateSetKg)).monospacedDigit()
                    }
                } header: { Text("Bar and plates").textCase(nil) }

                Section {
                    Toggle("Start rest after each set", isOn: $settings.autoStartRest)
                    restStepper("Working sets", value: $settings.workingRestSeconds)
                    restStepper("Warm-up sets", value: $settings.warmupRestSeconds)
                } header: { Text("Rest").textCase(nil) }

                Section {
                    Toggle("Banner", isOn: $settings.celebrateBanner)
                    Toggle("Haptic", isOn: $settings.celebrateHaptic)
                } header: { Text("Celebrate new bests").textCase(nil) }

                Section {
                    LabeledContent("Apple Health", value: healthText)
                    LabeledContent("iCloud backup", value: icloudText).monospacedDigit()
                    Button("Export as CSV") { export() }
                } header: { Text("Data").textCase(nil) }

                Section {
                    LabeledContent("Version", value: version).monospacedDigit()
                } header: { Text("About").textCase(nil) }
            }
            .tint(Theme.Colors.success)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bgSunken)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .sheet(item: Binding(get: { exportURL.map(ShareItem.init) }, set: { exportURL = $0?.url })) { item in
                ShareSheet(url: item.url)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func restStepper(_ label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 15...600, step: 15) {
            LabeledContent(label, value: RestCountdown.format(TimeInterval(value.wrappedValue))).monospacedDigit()
        }
    }

    private func plateSummary(_ p: PlateSet) -> String {
        "\(UnitMath.format(p.bar)) bar · " + p.plates.sorted(by: >).map(UnitMath.format).joined(separator: ", ")
    }

    private var healthText: String {
        switch HealthService.shared.status(userEnabled: settings.healthEnabled) {
        case .on: return "On"
        case .denied: return "Off"
        case .notSetUp, .unavailable: return settings.healthEnabled == false ? "Off" : "Not set up"
        }
    }

    private var icloudText: String {
        if FileManager.default.ubiquityIdentityToken == nil { return "Off: workouts stay on this iPhone only" }
        guard let last = cloud.lastSync else { return "On" }
        return "Backed up \(last.formatted(.relative(presentation: .named)))"
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func export() {
        let csv = LiftStore.csv(context)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lift-export-\(Date().formatted(.iso8601.year().month().day())).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Bar and plates for one unit: a toggle list plus "Add plate".
struct PlatesEditor: View {
    let unit: WeightUnit
    @Environment(AppSettings.self) private var settings
    @State private var newPlate = ""
    @State private var known: [Double] = []

    private var set: PlateSet { settings.plates(for: unit) }

    var body: some View {
        Form {
            Section {
                Stepper(value: Binding(get: { set.bar }, set: { var s = set; s.bar = $0; settings.setPlates(s) }), in: 0...60, step: unit == .kg ? 2.5 : 5) {
                    LabeledContent("Bar", value: "\(UnitMath.format(set.bar)) \(unit.symbol)").monospacedDigit()
                }
            }
            Section {
                ForEach(known, id: \.self) { plate in
                    Toggle(isOn: Binding(get: { set.plates.contains(plate) }, set: { on in
                        var s = set
                        if on { s.plates.append(plate) } else { s.plates.removeAll { $0 == plate } }
                        s.plates.sort(by: >)
                        settings.setPlates(s)
                    })) {
                        Text("\(UnitMath.format(plate)) \(unit.symbol)").monospacedDigit()
                    }
                }
                HStack {
                    TextField("Add plate", text: $newPlate).keyboardType(.decimalPad)
                    Button("Add") {
                        guard let v = Double(newPlate.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
                        if !known.contains(v) { known.append(v); known.sort(by: >) }
                        var s = set
                        if !s.plates.contains(v) { s.plates.append(v); s.plates.sort(by: >) }
                        settings.setPlates(s)
                        newPlate = ""
                    }
                }
            } header: { Text("Plates").textCase(nil) }
        }
        .tint(Theme.Colors.success)
        .navigationTitle(unit == .lb ? "Pounds" : "Kilograms")
        .onAppear {
            known = Array(Set(PlateSet.standard(for: unit).plates + set.plates)).sorted(by: >)
        }
    }
}
