import UIKit

/// DESIGN.md haptics. The tick's light impact is attached to the ring itself.
@MainActor
enum Haptics {
    static func newBest() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func restDone() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func step() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
