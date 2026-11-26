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
