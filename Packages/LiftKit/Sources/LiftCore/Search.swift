import Foundation

// Exercise search (spec §10, AC 83–98). Shared by the iPhone picker and the
// Watch's Add exercise list.
//
//     let index = library.exercises.map { SearchEntry(library: $0) }   // once per sheet
//     let hits = Search.run(index, query: text)                         // every keystroke
//     hits.first?.entry.name; hits.first?.matchedAlias                  // "Romanian Deadlift", "RDL"
//
// Ranking: tier (exact → starts with / word starts with → inside a word →
// muscle word → fuzzy), then usage, popularity, popularityRank, the shorter
// name, A–Z. Mirrors design/search/tools/search_ref.py row for row.

/// How often the user logged an exercise. `count` is workouts in the last 90
/// days with a done set (0 = logged before that); nil = never logged.
public struct SearchUsage: Sendable, Hashable {
    public var count: Int
    public var last: Date
    public init(count: Int, last: Date) { self.count = count; self.last = last }
}

/// One searchable string (the name or an alias), normalised once at index time.
public struct SearchKey: Sendable {
    public enum Kind: Sendable { case name, alias }
    public let text: String
    public let kind: Kind
    let words: [String]
    let phrase: String
    let compact: String
    /// Without phrase expansions (RDL stays "rdl"): decides the match-reason meta.
    let raw: [String]
    let rawCompact: String
    let sortedWords: [String]
    /// Compact form from each word on ("wide grip pull up" → "widegrippullup", "grippullup"…).
    let suffixCompacts: [String]

    init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
        let words = Search.tokens(text)
        self.words = words
        phrase = words.joined(separator: " ")
        compact = words.joined()
        raw = Search.tokens(text, phrases: false)
        rawCompact = raw.joined()
        sortedWords = words.sorted()
        suffixCompacts = words.indices.map { words[$0...].joined() }
    }
}

/// Searchable entry: a library exercise or a custom one.
public struct SearchEntry: Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let primary: [MuscleGroup]
    public let secondary: [MuscleGroup]
    public let equipment: Equipment
    public let popularity: Int
    public let popularityRank: Int?
    /// Near-duplicates show only once logged.
    public let hiddenUnlessLogged: Bool
    public var usage: SearchUsage?
    /// Folded name for A–Z lists.
    public let sortKey: String
    let keys: [SearchKey]
    let attributes: [String]
    let primaryRaw: Set<String>

    public init(id: UUID, name: String, aliases: [String], primary: [MuscleGroup], secondary: [MuscleGroup] = [],
                equipment: Equipment, position: String = "", popularity: Int = 3, popularityRank: Int? = nil,
                hiddenUnlessLogged: Bool = false, usage: SearchUsage? = nil) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.popularity = popularity
        self.popularityRank = popularityRank
        self.hiddenUnlessLogged = hiddenUnlessLogged
        self.usage = usage
        sortKey = Search.fold(name)
        keys = [SearchKey(name, kind: .name)] + aliases.filter { !$0.isEmpty }.map { SearchKey($0, kind: .alias) }
        attributes = Search.tokens(equipment.rawValue.replacingOccurrences(of: "_", with: " ")) + Search.tokens(position)
        primaryRaw = Set(primary.map(\.rawValue))
    }

    /// A bundled library exercise (aliases, popularity, position, duplicates from v3).
    public init(library e: LibraryExercise, id: UUID? = nil, usage: SearchUsage? = nil) {
        self.init(id: id ?? e.rowID, name: e.name, aliases: e.aliases, primary: e.primaryMuscles, secondary: e.secondaryMuscles,
                  equipment: e.equipment, position: e.position, popularity: e.popularity, popularityRank: e.popularityRank,
                  hiddenUnlessLogged: e.duplicateOf != nil, usage: usage)
    }

    /// Older call sites. `variant` is no longer indexed (§10.7).
    public init(id: UUID, name: String, variant: String, aliases: [String], primary: [MuscleGroup], secondary: [MuscleGroup], equipment: Equipment) {
        self.init(id: id, name: name, aliases: aliases, primary: primary, secondary: secondary, equipment: equipment)
    }

    var visible: Bool { !hiddenUnlessLogged || usage != nil }
    var recentCount: Int { usage?.count ?? 0 }
}

/// One result row.
public struct SearchHit: Sendable, Identifiable {
    public let entry: SearchEntry
    /// 1 exact, 3 starts with / word starts with, 4 inside a word, 5 muscle word, 6 fuzzy;
    /// 0 for an empty query. Logged matches at 3–4 report 3.
    public let tier: Int
    /// The alias to lead the detail line with when the name doesn't explain the match ("RDL").
    public let matchedAlias: String?
    public init(entry: SearchEntry, tier: Int, matchedAlias: String?) {
        self.entry = entry
        self.tier = tier
        self.matchedAlias = matchedAlias
    }
    public var id: UUID { entry.id }
    public var name: String { entry.name }
    /// An exact name or alias match: no Create row (AC 96).
    public var isExact: Bool { tier == 1 }
}

public enum Search {
    /// Case- and diacritic-folded (also used for duplicate-name checks).
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Ranked results. An empty query returns every visible entry passing the
    /// filters: A–Z, or by usage then popularity when a filter is on (§10.6).
    public static func run(_ entries: [SearchEntry], query: String, muscles: Set<MuscleGroup> = [], equipment: Set<Equipment> = []) -> [SearchHit] {
        func passes(_ e: SearchEntry) -> Bool {
            if !equipment.isEmpty, !equipment.contains(e.equipment) { return false }
            if !muscles.isEmpty, muscles.isDisjoint(with: e.primary), muscles.isDisjoint(with: e.secondary) { return false }
            return e.visible
        }
        let qt = tokens(query)
        if qt.isEmpty {
            // Only punctuation ("-"): nothing matches, as in the reference.
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
            let all = entries.filter(passes)
            let sorted = (muscles.isEmpty && equipment.isEmpty)
                ? all.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
                : all.sorted { popularityOrder($0, $1) }
            return sorted.map { SearchHit(entry: $0, tier: 0, matchedAlias: nil) }
        }
        let qraw = tokens(query, phrases: false)
        let q = Query(words: qt, phrase: qt.joined(separator: " "), compact: qt.joined(), sorted: qt.sorted(),
                      generic: qt.count == 1 && SearchRules.generic.contains(qt[0]))

        struct Row { var tier: Double; var sub: Int; let index: Int; let key: SearchKey }
        var rows: [Row] = []
        var seen = Set<Int>()
        for (i, e) in entries.enumerated() where passes(e) {
            var best: (t: Double, pref: (Int, Int), key: SearchKey)?
            for (n, k) in e.keys.enumerated() {
                guard let t = tier(q, k, attributes: e.attributes) else { continue }
                let pref = (k.kind == .name ? 0 : (allPrefix(qraw, k.raw) ? 1 : 2), n)
                if best == nil || (t, pref.0, pref.1) < (best!.t, best!.pref.0, best!.pref.1) { best = (t, pref, k) }
            }
            if let b = best {
                rows.append(Row(tier: b.t == 2.9 ? 3 : b.t, sub: b.t == 2.9 ? 0 : 1, index: i, key: b.key))
                seen.insert(i)
            }
        }
        // Tier 5: a single muscle or body-part word lists exercises that train it.
        if qt.count == 1, let targets = SearchRules.muscles[qt[0]] {
            for (i, e) in entries.enumerated() where !seen.contains(i) && passes(e) && !targets.isDisjoint(with: e.primaryRaw) {
                rows.append(Row(tier: 5, sub: 0, index: i, key: e.keys[0]))
                seen.insert(i)
            }
        }
        // Tier 6: fuzzy, only when tiers 1–5 found fewer than 3; at most 8.
        if rows.count < 3 {
            var fz: [Row] = []
            for (i, e) in entries.enumerated() where !seen.contains(i) && passes(e) {
                var best: (Int, SearchKey)?
                for k in e.keys { if let d = fuzzy(qt, k), best == nil || d < best!.0 { best = (d, k) } }
                if let b = best { fz.append(Row(tier: 6, sub: b.0, index: i, key: b.1)) }
            }
            fz.sort { a, b in
                let x = entries[a.index], y = entries[b.index]
                if a.sub != b.sub { return a.sub < b.sub }
                if x.recentCount != y.recentCount { return x.recentCount > y.recentCount }
                if x.popularity != y.popularity { return x.popularity > y.popularity }
                if (x.popularityRank ?? 1_000_000) != (y.popularityRank ?? 1_000_000) { return (x.popularityRank ?? 1_000_000) < (y.popularityRank ?? 1_000_000) }
                if x.name.count != y.name.count { return x.name.count < y.name.count }
                return a.index < b.index
            }
            rows += fz.prefix(8)
        }
        // Your lifts float up: logged in the last 90 days and matching at 3–4 → right after exact.
        for r in rows.indices where entries[rows[r].index].recentCount > 0 && (3...4).contains(rows[r].tier) { rows[r].tier = 1.5 }
        rows.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.tier == 6, a.sub != b.sub { return a.sub < b.sub }
            let x = entries[a.index], y = entries[b.index]
            if x.recentCount != y.recentCount { return x.recentCount > y.recentCount }
            if let ux = x.usage, let uy = y.usage, x.recentCount > 0, ux.last != uy.last { return ux.last > uy.last }
            if x.popularity != y.popularity { return x.popularity > y.popularity }
            let rx = x.popularityRank ?? 1_000_000, ry = y.popularityRank ?? 1_000_000
            if rx != ry { return rx < ry }
            if a.tier != 6, a.sub != b.sub { return a.sub < b.sub }
            if x.name.count != y.name.count { return x.name.count < y.name.count }
            if x.name != y.name { return x.name < y.name }
            return a.index < b.index
        }
        let rc = qraw.joined()
        return rows.map { r in
            let e = entries[r.index]
            return SearchHit(entry: e, tier: r.tier == 1.5 ? 3 : Int(r.tier), matchedAlias: meta(e, used: r.key, qraw: qraw, rc: rc))
        }
    }

    /// Usage, then popularity, rank, shorter name, A–Z (chips with no query; Common).
    public static func popularityOrder(_ x: SearchEntry, _ y: SearchEntry) -> Bool {
        if x.recentCount != y.recentCount { return x.recentCount > y.recentCount }
        if x.popularity != y.popularity { return x.popularity > y.popularity }
        let rx = x.popularityRank ?? 1_000_000, ry = y.popularityRank ?? 1_000_000
        if rx != ry { return rx < ry }
        if x.name.count != y.name.count { return x.name.count < y.name.count }
        return x.name < y.name
    }

    // MARK: Matching

    struct Query { let words: [String]; let phrase: String; let compact: String; let sorted: [String]; let generic: Bool }

    /// 1, 2.9 (single-word starts with; ranks with 3, breaks ties after rank), 3, 4 or nil.
    static func tier(_ q: Query, _ k: SearchKey, attributes: [String]) -> Double? {
        // Cheap reject: every tier needs each query word inside the key (or an attribute).
        for w in q.words where !k.compact.contains(w) && !attributes.contains(where: { $0.hasPrefix(w) }) { return nil }
        if k.phrase == q.phrase || k.compact == q.compact || k.sortedWords == q.sorted { return 1 }
        if k.phrase.hasPrefix(q.phrase) || k.compact.hasPrefix(q.compact) { return (q.generic || q.words.count > 1) ? 3 : 2.9 }
        for s in k.suffixCompacts where s.hasPrefix(q.compact) { return 3 }
        if wordPrefixes(q.words, k.words) { return 3 }
        if q.words.count > 1, q.words.contains(where: { w in k.words.contains { $0.hasPrefix(w) } }),
           wordPrefixes(q.words, k.words + attributes) { return 3 }
        if q.words.allSatisfy({ w in k.words.contains { $0.contains(w) } }) { return 4 }
        return nil
    }

    /// Every query word starts a different key word, any order.
    static func wordPrefixes(_ qs: [String], _ ks: [String]) -> Bool {
        var used = [Bool](repeating: false, count: ks.count)
        for q in qs {
            guard let hit = ks.indices.first(where: { !used[$0] && ks[$0].hasPrefix(q) }) else { return false }
            used[hit] = true
        }
        return true
    }

    static func allPrefix(_ qs: [String], _ ks: [String]) -> Bool {
        qs.allSatisfy { q in ks.contains { $0.hasPrefix(q) } }
    }

    static func meta(_ e: SearchEntry, used k: SearchKey, qraw: [String], rc: String) -> String? {
        func hits(_ key: SearchKey) -> Bool { key.rawCompact.contains(rc) || allPrefix(qraw, key.raw) }
        if hits(e.keys[0]) { return nil }
        let echo = e.keys.dropFirst().filter(hits).enumerated().sorted { a, b in
            let x = (a.element.rawCompact != rc ? 1 : 0, a.element.rawCompact.hasPrefix(rc) ? 0 : 1, a.offset)
            let y = (b.element.rawCompact != rc ? 1 : 0, b.element.rawCompact.hasPrefix(rc) ? 0 : 1, b.offset)
            return x < y
        }
        if let first = echo.first { return first.element.text }
        return k.kind == .alias ? k.text : nil
    }

    // MARK: Fuzzy

    static func damerau(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let c = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + c)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    static func fuzzyWord(_ q: String, _ k: String, last: Bool) -> Int? {
        let qc = Array(q), kc = Array(k)
        guard qc.count >= 4, !kc.isEmpty else { return nil }
        let last = qc.count < 5 ? false : last
        let limit = qc.count < 8 ? 1 : 2
        if qc[0] != kc[0], !(qc.count > 1 && kc.count > 1 && qc[0] == kc[1] && qc[1] == kc[0]) { return nil }
        var cands = [kc]
        if last { for n in [qc.count, qc.count + 1] where n > 0 && n < kc.count { cands.append(Array(kc[0..<n])) } }
        let best = cands.map { damerau(qc, $0) }.min()!
        return best <= limit ? best : nil
    }

    static func fuzzy(_ qt: [String], _ k: SearchKey) -> Int? {
        var total = 0
        var used = Set<Int>()
        for (n, q) in qt.enumerated() {
            let isLast = n == qt.count - 1
            var best: (Int, Int)?
            for (i, w) in k.words.enumerated() where !used.contains(i) {
                let d: Int? = (isLast ? w.hasPrefix(q) : w == q) ? 0 : fuzzyWord(q, w, last: isLast)
                if let d, best == nil || d < best!.0 { best = (d, i) }
            }
            guard let b = best else { return nil }
            used.insert(b.1)
            total += b.0
        }
        return total > 0 ? total : nil
    }

    // MARK: Normalisation (§10.3)

    static let fraction: Character = "\u{2044}"

    /// Lowercase, diacritics folded, punctuation to spaces, fractions kept.
    static func foldWords(_ s: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        for u in s.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars where u.properties.canonicalCombiningClass == .notReordered {
            switch u {
            case "\u{00B0}": scalars.append(contentsOf: " degree ".unicodeScalars)
            case "&": scalars.append(contentsOf: " and ".unicodeScalars)
            case "'", "\u{2019}": break
            default: scalars.append(u)
            }
        }
        var chars = Array(String(scalars))
        // digit/digit → one token ("3/4", "90/90"), non-overlapping like re.sub
        var i = 1
        while i + 1 < chars.count {
            if chars[i] == "/", chars[i - 1].isASCII, chars[i - 1].isNumber, chars[i + 1].isASCII, chars[i + 1].isNumber {
                chars[i] = fraction
                i += 3
            } else { i += 1 }
        }
        let cleaned = String(chars.map { c -> Character in
            (c.isASCII && (c.isLowercase || c.isNumber)) || c == fraction ? c : " "
        })
        var out: [String] = []
        for word in cleaned.split(separator: " ") { out += splitDegree(String(word)) }
        return out
    }

    /// "45deg" → "45 deg", "90degree" → "90 degree".
    static func splitDegree(_ w: String) -> [String] {
        let c = Array(w)
        for i in 0..<max(0, c.count - 1) where c[i].isNumber {
            for unit in ["degree", "deg"] {
                let u = Array(unit)
                let end = i + 1 + u.count
                if end <= c.count, Array(c[(i + 1)..<end]) == u, end == c.count || c[end] == fraction {
                    return [String(c[0...i])] + splitDegree(String(c[(i + 1)...]))
                }
            }
        }
        return [w]
    }

    static func stem(_ t: String) -> String {
        if SearchRules.noStem.contains(t) || t.count <= 3 || t.allSatisfy({ $0.isASCII && $0.isNumber }) { return t }
        if t.hasSuffix("ies") { return String(t.dropLast(3)) + "y" }
        if t.hasSuffix("shes") || t.hasSuffix("ches") || t.hasSuffix("xes") || t.hasSuffix("sses") { return String(t.dropLast(2)) }
        if t.hasSuffix("s"), !t.hasSuffix("ss"), !t.hasSuffix("us") { return String(t.dropLast()) }
        return t
    }

    /// Normalised words. `phrases: false` keeps OHP/RDL unexpanded (for the meta check).
    public static func tokens(_ s: String, phrases: Bool = true) -> [String] {
        var out: [String] = []
        for var t in foldWords(s) {
            t = SearchRules.typo[t] ?? t
            t = SearchRules.token[t] ?? t
            if phrases { t = SearchRules.phrase[t] ?? t }
            out += t.split(separator: " ").map(String.init)
        }
        out = out.map(stem)
        for (from, to) in SearchRules.pairs {
            var i = 0, next: [String] = []
            while i < out.count {
                if i + from.count <= out.count, Array(out[i..<(i + from.count)]) == from { next += to; i += from.count }
                else { next.append(out[i]); i += 1 }
            }
            out = next
        }
        return out
    }
}
