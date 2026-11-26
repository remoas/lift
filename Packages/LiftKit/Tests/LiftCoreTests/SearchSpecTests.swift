import XCTest
@testable import LiftCore

/// AC 83: every row of design/search/tests.csv, against the bundled v3 library.
/// design/search/tools/run_tests.py runs the same table on the Python reference.
final class SearchSpecTests: XCTestCase {
    static let csvURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // Packages/LiftKit
        .deletingLastPathComponent().deletingLastPathComponent()                              // repo
        .appendingPathComponent("design/search/tests.csv")

    static let library = ExerciseLibrary.bundled
    /// Built once (tokenising 1,250 rows); usage is set per test row.
    static let base: [SearchEntry] = library.exercises.map { SearchEntry(library: $0) }
    static let rowIDs: [UUID: String] = Dictionary(uniqueKeysWithValues: library.exercises.map { ($0.rowID, $0.id) })

    /// History ids, most recent first, become usage counts like the reference's.
    func index(history: [String]) -> [SearchEntry] {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var usage: [String: SearchUsage] = [:]
        for (n, id) in history.enumerated() where usage[id] == nil {
            usage[id] = SearchUsage(count: history.count - n, last: now.addingTimeInterval(-Double(n) * 86_400))
        }
        return zip(Self.library.exercises, Self.base).map { e, entry in
            var x = entry
            x.usage = usage[e.id]
            return x
        }
    }

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = Array(text).makeIterator(); var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" { if let n = it.next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" { row.append(field); field = ""; rows.append(row); row = [] }
            else if c != "\r" { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    func testEveryRowOfTestsCSV() throws {
        let text = try String(contentsOf: Self.csvURL, encoding: .utf8)
        let rows = Self.parseCSV(text)
        let header = rows[0]
        XCTAssertEqual(header, ["query", "history", "expect_top1", "expect_in_top3", "expect_not_in_top5", "expect_meta_top1", "note"])
        var failures: [String] = []
        for r in rows.dropFirst() where r.count >= 6 {
            let (query, history, top1, top3, notTop5, meta) = (r[0], r[1], r[2], r[3], r[4], r[5])
            let hits = Search.run(index(history: history.split(separator: "|").map(String.init)), query: query)
            let ids = hits.map { Self.rowIDs[$0.id] ?? "?" }
            var why: [String] = []
            if !top1.isEmpty, ids.first != top1 { why.append("top1") }
            for x in top3.split(separator: "|").map(String.init) where !ids.prefix(3).contains(x) { why.append("top3 \(x)") }
            for x in notTop5.split(separator: "|").map(String.init) where ids.prefix(5).contains(x) { why.append("not-top5 \(x)") }
            if !top1.isEmpty, (hits.first?.matchedAlias ?? "") != meta { why.append("meta=\(hits.first?.matchedAlias ?? "")") }
            if top1.isEmpty, !ids.isEmpty { why.append("expected no results") }
            if !why.isEmpty { failures.append("\(query) [\(history)]: \(why) got \(ids.prefix(5))") }
        }
        XCTAssertEqual(rows.count - 1, 105)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testCDOAddendumFamilies() {
        let names = Search.run(index(history: []), query: "deadlift").prefix(5).map(\.name)
        XCTAssertEqual(names.first, "Deadlift")
        XCTAssertTrue(names.contains("Romanian Deadlift") && names.contains("Sumo Deadlift"))
        XCTAssertFalse(names.contains("Deadlift with Bands") || names.contains("Deadlift with Chains"))
    }

    func testV3Library() {
        let lib = Self.library
        XCTAssertGreaterThanOrEqual(lib.version, 3)
        XCTAssertEqual(lib.exercises.reduce(0) { $0 + $1.aliases.count }, 922)
        XCTAssertEqual(lib.exercises.filter { $0.duplicateOf != nil }.count, 17)
        XCTAssertNil(lib.exercise("triceps-pushdown")?.duplicateOf)
        XCTAssertEqual(lib.exercise("bench-press")?.popularity, 5)
        XCTAssertEqual(lib.exercise("bench-press")?.popularityRank, 1)
    }

    func testNormalisation() {
        XCTAssertEqual(Search.tokens("pull-up"), ["pull", "up"])
        XCTAssertEqual(Search.tokens("pullup"), ["pull", "up"])
        XCTAssertEqual(Search.tokens("Plié"), Search.tokens("plie"))
        XCTAssertEqual(Search.tokens("45°"), Search.tokens("45deg"))
        XCTAssertEqual(Search.tokens("3/4 Sit-Up").first, "3\u{2044}4")
    }

    /// AC 95: Search.run under 5 ms median on the 1,250-row library.
    func testSearchRunMedianUnder5ms() {
        let ix = index(history: [])
        var times: [Double] = []
        for q in ["b", "be", "ben", "bench", "bench p", "press", "pull up", "db incline", "benhc", "squat", "rdl", "zzqx", "abs"] {
            let t = Date()
            _ = Search.run(ix, query: q)
            times.append(Date().timeIntervalSince(t))
        }
        times.sort()
        let median = times[times.count / 2]
        print("search median \(String(format: "%.2f", median * 1000)) ms, max \(String(format: "%.2f", times.last! * 1000)) ms")
        #if DEBUG
        XCTAssertLessThan(median, 0.015, "Debug build; the 5 ms budget is for optimised builds")
        #else
        XCTAssertLessThan(median, 0.005)
        #endif
        measure { _ = Search.run(ix, query: "bench") }
    }
}
