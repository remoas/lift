import SwiftUI
import LiftCore

/// "Rest for {Exercise}" (frame 28, watch.md §3.10): Off, then 0:30–5:00 in
/// 15 s steps. Writes Exercise.restSec from the next set; +30s during a rest
/// never changes it.
struct RestPickerSheet: View {
    let exercise: Exercise
    let current: Int
    let onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RestChoices.all(including: current), id: \.self) { s in
                        Button {
                            onPick(s)
                            dismiss()
                        } label: {
                            HStack {
                                Text(RestChoices.label(s)).font(Theme.Fonts.bodyNumber).foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                if s == current { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                            }
                            .frame(minHeight: Theme.Size.hit)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(s == current ? .isSelected : [])
                    }
                } footer: {
                    Text("From the next set. +30s during rest only changes this break.")
                }
            }
            .navigationTitle("Rest for \(exercise.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
