import Foundation

/// Fine-grained muscle tags.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    // Raw values are the stored/seed format (snake_case) and must never change.
    case upperChest = "upper_chest", midChest = "mid_chest", lowerChest = "lower_chest"
    case frontDelts = "front_delts", sideDelts = "side_delts", rearDelts = "rear_delts"
    case lats, traps, rhomboids, lowerBack = "lower_back"
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, adductors, abductors, calves
    case abs, obliques, neck

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .upperChest: return "Upper chest"
        case .midChest: return "Mid chest"
        case .lowerChest: return "Lower chest"
        case .frontDelts: return "Front delts"
        case .sideDelts: return "Side delts"
        case .rearDelts: return "Rear delts"
        case .lats: return "Lats"
        case .traps: return "Traps"
        case .rhomboids: return "Rhomboids"
        case .lowerBack: return "Lower back"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .adductors: return "Adductors"
        case .abductors: return "Abductors"
        case .calves: return "Calves"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .neck: return "Neck"
        }
    }

    /// Body region, used to group the muscle filter.
    public var region: String {
        switch self {
        case .upperChest, .midChest, .lowerChest: return "Chest"
        case .frontDelts, .sideDelts, .rearDelts: return "Shoulders"
        case .lats, .traps, .rhomboids, .lowerBack: return "Back"
        case .biceps, .triceps, .forearms: return "Arms"
        case .quads, .hamstrings, .glutes, .adductors, .abductors, .calves: return "Legs"
        case .abs, .obliques: return "Core"
        case .neck: return "Neck"
        }
    }

    public static let regions = ["Chest", "Shoulders", "Back", "Arms", "Legs", "Core", "Neck"]

    public static func parse(_ raw: String) -> [MuscleGroup] {
        raw.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) }
    }

    public static func join(_ list: [MuscleGroup]) -> String { list.map(\.rawValue).joined(separator: ",") }
}

public enum Equipment: String, Codable, CaseIterable, Sendable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight
    // Raw values are the stored/seed format (snake_case) and must never change.
    case medicineBall = "medicine_ball", sled, kettlebell, ezBar = "ez_bar", trapBar = "trap_bar"
    case smithMachine = "smith_machine", band, plate
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .medicineBall: return "Medicine ball"
        case .sled: return "Sled"
        case .kettlebell: return "Kettlebell"
        case .ezBar: return "EZ bar"
        case .trapBar: return "Trap bar"
        case .smithMachine: return "Smith machine"
        case .band: return "Band"
        case .plate: return "Plate"
        case .other: return "Other"
        }
    }

    /// The plate line applies to a standard loaded bar.
    public var usesPlates: Bool { self == .barbell }

    /// No external load needed to tick a set.
    public var allowsZeroWeight: Bool { self == .bodyweight || self == .band }
}

/// One library entry. `id` is a stable string so the bundled seed can be
/// replaced by a researched dataset without breaking history.
public struct LibraryExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var equipment: Equipment
    public var variant: String
    public var aliases: [String]
    public var repMin: Int
    public var repMax: Int
    public var restSeconds: Int?
    /// Vendored CC0 media key ("still:{id}", "hold:{id}", "video:{id}") or nil. Never invented.
    public var mediaRef: String?
    /// Where the text came from (free-exercise-db, open-exercise-illustrations, workout-free-videos, lift).
    public var source: String?
    /// Search ranking (v3, §10.2): 1–5, and the hand-ordered rank (1 = most common) or nil.
    public var popularity: Int
    public var popularityRank: Int?
    /// Position words ("seated", "incline"…): search attributes only, never matched alone.
    public var position: String
    /// Near-duplicate of another id: hidden from search unless logged.
    public var duplicateOf: String?

    enum CodingKeys: String, CodingKey {
        case id, name, primaryMuscles, secondaryMuscles, equipment, variant, aliases, repMin, repMax, restSeconds, mediaRef, source
        case popularity, popularityRank, position, duplicateOf
    }

    /// Lenient on optional fields (null variant, missing reps), strict on enums:
    /// an unknown muscle or equipment value fails the decode instead of being dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        primaryMuscles = try c.decodeIfPresent([MuscleGroup].self, forKey: .primaryMuscles) ?? []
        secondaryMuscles = try c.decodeIfPresent([MuscleGroup].self, forKey: .secondaryMuscles) ?? []
        equipment = try c.decode(Equipment.self, forKey: .equipment)
        variant = try c.decodeIfPresent(String.self, forKey: .variant) ?? ""
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        repMin = try c.decodeIfPresent(Int.self, forKey: .repMin) ?? 8
        repMax = try c.decodeIfPresent(Int.self, forKey: .repMax) ?? 12
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        mediaRef = try c.decodeIfPresent(String.self, forKey: .mediaRef)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        popularity = try c.decodeIfPresent(Int.self, forKey: .popularity) ?? 3
        popularityRank = try c.decodeIfPresent(Int.self, forKey: .popularityRank)
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        duplicateOf = try c.decodeIfPresent(String.self, forKey: .duplicateOf)
    }

    public var media: ExerciseMedia? { mediaRef.flatMap(ExerciseMedia.init(key:)) }

    public init(id: String, name: String, primaryMuscles: [MuscleGroup], secondaryMuscles: [MuscleGroup] = [], equipment: Equipment, variant: String = "", aliases: [String] = [], repMin: Int = 8, repMax: Int = 12, restSeconds: Int? = nil, mediaRef: String? = nil, source: String? = nil, popularity: Int = 3, popularityRank: Int? = nil, position: String = "", duplicateOf: String? = nil) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.variant = variant
        self.aliases = aliases
        self.repMin = repMin
        self.repMax = repMax
        self.restSeconds = restSeconds
        self.mediaRef = mediaRef
        self.source = source
        self.popularity = popularity
        self.popularityRank = popularityRank
        self.position = position
        self.duplicateOf = duplicateOf
    }

    public var repRange: ClosedRange<Int> { min(repMin, repMax)...max(repMin, repMax) }

    /// Deterministic row ID, identical on every device.
    public var rowID: UUID { StableID.uuid("lib:" + id) }
}

/// Vendored media for a library entry. Files live in the app bundle under
/// ExerciseMedia/ (never hot-linked). Third-party licences: THIRD_PARTY_MEDIA.md.
public enum ExerciseMedia: Hashable, Sendable {
    /// Start and end stills (open-exercise-illustrations, CC0); crossfade start → end.
    case stills(start: String, end: String)
    /// One held-position still (open-exercise-illustrations, CC0).
    case hold(String)
    /// Looping 720p MP4, vendored under ExerciseMedia/video/.
    case video(String)

    public init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty, !parts[1].contains("/"), !parts[1].contains("..") else { return nil }
        let id = parts[1]
        switch parts[0] {
        case "still": self = .stills(start: "stills/\(id)-start.webp", end: "stills/\(id)-end.webp")
        case "hold": self = .hold("stills/\(id)-hold.webp")
        case "video": self = .video("video/\(id).mp4")
        default: return nil
        }
    }

    /// Relative paths under ExerciseMedia/.
    public var files: [String] {
        switch self {
        case .stills(let a, let b): return [a, b]
        case .hold(let a): return [a]
        case .video(let v): return [v]
        }
    }

    /// The still to use as a list thumbnail, if any (videos derive one at runtime).
    public var thumbnail: String? {
        switch self {
        case .stills(let a, _): return a
        case .hold(let a): return a
        case .video: return nil
        }
    }
}

/// The versioned, bundled exercise library (a pick list only).
public struct ExerciseLibrary: Codable, Sendable {
    public var version: Int
    public var source: String?
    public var exercises: [LibraryExercise]
    /// "Common on {Day}" ids, by day name.
    public var common: [String: [String]]

    public init(version: Int, source: String? = nil, exercises: [LibraryExercise], common: [String: [String]] = [:]) {
        self.version = version
        self.source = source
        self.exercises = exercises
        self.common = common
    }

    public static func decode(_ data: Data) throws -> ExerciseLibrary {
        try JSONDecoder().decode(ExerciseLibrary.self, from: data)
    }

    /// The seed shipped in this package.
    public static let bundled: ExerciseLibrary = {
        guard let url = Bundle.module.url(forResource: "exercise-library", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lib = try? decode(data) else {
            return ExerciseLibrary(version: 0, exercises: [])
        }
        return lib
    }()

    public func exercise(_ id: String) -> LibraryExercise? { exercises.first { $0.id == id } }

    public func common(for day: String) -> [LibraryExercise] {
        (common[day] ?? []).compactMap(exercise)
    }
}

/// Seed updates: refresh library-backed rows in place by stable ID. Custom
/// exercises are never touched, and nothing is deleted (history stays attached).
public enum LibraryMerge {
    public struct Update: Equatable, Sendable {
        public let libraryID: String
        public let entry: LibraryExercise
    }

    /// `existingLibraryIDs`: library IDs already materialised as rows (customs excluded).
    public static func updates(seed: ExerciseLibrary, appliedVersion: Int, existingLibraryIDs: Set<String>) -> [Update] {
        guard seed.version > appliedVersion else { return [] }
        return seed.exercises.filter { existingLibraryIDs.contains($0.id) }.map { Update(libraryID: $0.id, entry: $0) }
    }
}

/// Deterministic UUIDs from strings (two 64-bit FNV-1a passes), so every device
/// derives the same row ID for the same library entry.
public enum StableID {
    public static func uuid(_ key: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h: UInt64 = seed
            for b in key.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return h
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((a >> (UInt64(i) * 8)) & 0xff); bytes[i + 8] = UInt8((b >> (UInt64(i) * 8)) & 0xff) }
        bytes[6] = (bytes[6] & 0x0f) | 0x50   // version 5-style
        bytes[8] = (bytes[8] & 0x3f) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Fixed app-level lists.
public enum Defaults {
    /// Preset rep ranges in the build screen's reps menu.
    public static let repRangePresets: [ClosedRange<Int>] = [3...5, 5...8, 6...8, 8...10, 8...12, 10...12, 12...15, 15...20]
}
