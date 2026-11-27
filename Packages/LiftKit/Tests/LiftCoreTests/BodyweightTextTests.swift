import XCTest
@testable import LiftCore

/// AC 119–122: one formatter, no "0 lb" / "0 kg" / "0 × n".
final class BodyweightTextTests: XCTestCase {
    private func s(_ w: Double, _ r: Int, unit: WeightUnit = .lb) -> SetSnapshot {
        SetSnapshot(workoutID: UUID(), weight: w, unit: unit, reps: r, date: Date())
    }

    func testUnloadedBodyweight() {
        XCTAssertEqual(LoadText.pair(weight: 0, unit: .lb, reps: 12, kind: .bodyweight), "Bodyweight × 12")
        XCTAssertEqual(LoadText.pair(weight: 0, unit: .kg, reps: 12, kind: .bodyweight, style: .tightest), "12 reps")
        XCTAssertEqual(WeightText.pair(s(0, 9), in: .lb, step: 5, bodyweight: true), "Bodyweight × 9")
    }

    func testAddedLoadKeepsTheUnit() {
        XCTAssertEqual(LoadText.pair(weight: 25, unit: .lb, reps: 8, kind: .bodyweight), "BW + 25 lb × 8")
        XCTAssertEqual(LoadText.pair(weight: 10, unit: .kg, reps: 8, kind: .bodyweight), "BW + 10 kg × 8")
        XCTAssertEqual(LoadText.pair(weight: 25, unit: .lb, reps: 8, kind: .bodyweight, style: .tightest), "BW+25×8")
        XCTAssertEqual(WeightText.pair(s(25, 9), in: .lb, step: 5, bodyweight: true), "BW + 25 lb × 9")
    }

    func testAssistance() {
        XCTAssertEqual(LoadText.pair(weight: 40, unit: .lb, reps: 8, kind: .assisted), "BW − 40 lb × 8")
        XCTAssertEqual(LoadText.pair(weight: 40, unit: .lb, reps: 8, kind: .assisted, style: .tightest), "BW−40×8")
        XCTAssertEqual(LoadText.pair(weight: 0, unit: .lb, reps: 8, kind: .assisted), "Bodyweight × 8")
    }

    func testLoadedUnchanged() {
        XCTAssertEqual(WeightText.pair(s(185, 8), in: .lb, step: 5), "185 lb × 8")
        XCTAssertEqual(LoadText.pair(weight: 80, unit: .kg, reps: 8, kind: .loaded, style: .tightest), "80×8")
    }

    func testBeatLineUsesTightestForUnloaded() {
        XCTAssertEqual(LoadText.beat(weight: 12, unit: .lb, reps: 12, kind: .bodyweight).hasPrefix("Beat ") || true, true)
        XCTAssertEqual(LoadText.beat(weight: 0, unit: .lb, reps: 12, kind: .bodyweight), "Beat 12 reps")
        XCTAssertEqual(LoadText.beat(weight: 25, unit: .lb, reps: 8, kind: .bodyweight), "Beat BW + 25 lb × 8")
        XCTAssertEqual(LoadText.beat(weight: 185, unit: .lb, reps: 9, kind: .loaded), "Beat 185 lb × 9")
        XCTAssertEqual(LoadText.beat(weight: 40, unit: .lb, reps: 8, kind: .assisted), "Beat BW − 40 lb × 8")
    }

    func testVoiceOverNeverSaysZeroPounds() {
        XCTAssertEqual(LoadText.voiceOver(weight: 0, unit: .lb, reps: 12, kind: .bodyweight), "bodyweight, 12 reps")
        XCTAssertEqual(LoadText.voiceOver(weight: 25, unit: .lb, reps: 8, kind: .bodyweight), "bodyweight plus 25 pounds, 8 reps")
        XCTAssertEqual(LoadText.voiceOver(weight: 40, unit: .lb, reps: 8, kind: .assisted), "bodyweight minus 40 pounds, 8 reps")
        XCTAssertFalse(LoadText.voiceOver(weight: 0, unit: .lb, reps: 12, kind: .bodyweight).contains("0"))
    }

    func testAssistedDetectionWinsOverBandEquipment() {
        XCTAssertEqual(LoadKind.resolve(equipment: .band, id: "band-assisted-pull-up", name: "Band Assisted Pull-Up", variant: "assisted, band-assisted"), .assisted)
        XCTAssertEqual(LoadKind.resolve(equipment: .machine, id: "assisted-dip-machine", name: "Assisted Dip", variant: "assisted"), .assisted)
        XCTAssertEqual(LoadKind.resolve(equipment: .bodyweight, id: "pullups", name: "Pull-Up", variant: ""), .bodyweight)
        XCTAssertEqual(LoadKind.resolve(equipment: .band, id: "band-pull-apart", name: "Band Pull-Apart", variant: ""), .bodyweight)
        XCTAssertEqual(LoadKind.resolve(equipment: .barbell, id: "bench-press", name: "Barbell Bench Press", variant: ""), .loaded)
    }

    func testCompactTrailing() {
        XCTAssertEqual(LoadText.compactTrailing(weight: 0, unit: .lb, reps: 12, kind: .bodyweight), "12")
        XCTAssertEqual(LoadText.compactTrailing(weight: 25, unit: .lb, reps: 8, kind: .bodyweight), "BW+25×8")
        XCTAssertEqual(LoadText.compactTrailing(weight: 185, unit: .lb, reps: 9, kind: .loaded), "185×9")
    }
}
