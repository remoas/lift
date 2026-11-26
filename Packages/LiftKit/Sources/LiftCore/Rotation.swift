import Foundation

public enum Rotation {
    /// The next routine in the rotation: the one after the last finished
    /// routine, wrapping round. Falls back to the first routine.
    public static func next<ID: Equatable>(order: [ID], lastCompleted: ID?) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let last = lastCompleted, let i = order.firstIndex(of: last) else { return order.first }
        return order[(i + 1) % order.count]
    }
}
