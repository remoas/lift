import AppIntents
import Foundation

/// +30s on the Lock Screen or the expanded Island. Runs in Lift's process
/// (LiveActivityIntent), the same action as the in-app and watch chips; it
/// lengthens this break only and never writes Exercise.restSec.
struct AddRestTimeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 30 seconds"
    static var description = IntentDescription("Adds 30 seconds to this rest only.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestIntentHandler.addThirty()
        return .result()
    }
}

/// Skip: ends rest now, no confirm and no alert.
struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("Ends this rest now.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestIntentHandler.skip()
        return .result()
    }
}

/// Step the reps that will be logged, without writing the set (AC 116).
struct AdjustRepsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust reps"
    static var description = IntentDescription("Changes the reps that will be logged.")
    static var isDiscoverable = false

    @Parameter(title: "Delta")
    var delta: Int

    init() { delta = 1 }
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        await RestIntentHandler.adjustReps(delta)
        return .result()
    }
}

/// Log the displayed load and the stepper reps, same as an in-app tick.
struct LogSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log set"
    static var description = IntentDescription("Logs this set with the reps on the stepper.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestIntentHandler.logSet()
        return .result()
    }
}
