import XCTest
@testable import LiftCore

/// qa-search Must 5: never "0 × 9" for bodyweight.
final class BodyweightTextTests: XCTestCase {
    private func s(_ w: Double, _ r: Int) -> SetSnapshot { SetSnapshot(workoutID: UUID(), weight: w, unit: .lb, reps: r, date: Date()) }

    func testBodyweightRepsOnly() {
        XCTAssertEqual(WeightText.pair(s(0, 9), in: .lb, step: 5, bodyweight: true), "9 reps")
    }
    func testBodyweightAddedLoad() {
        XCTAssertEqual(WeightText.pair(s(25, 9), in: .lb, step: 5, bodyweight: true), "BW + 25 × 9")
    }
    func testLoadedUnchanged() {
        XCTAssertEqual(WeightText.pair(s(185, 8), in: .lb, step: 5), "185 × 8")
    }
}
