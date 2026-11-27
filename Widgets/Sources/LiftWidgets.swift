import ActivityKit
import SwiftUI
import UIKit
import WidgetKit
import LiftCore

@main
struct LiftWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

/// The rest-timer Live Activity: Lock Screen, StandBy and the Dynamic Island.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            let model = RestActivityModel(state: context.state, isStale: context.isStale)
            RestLockScreenView(model: model)
                .activityBackgroundTint(model.state.highlight ? RestDynamic.accentSoft : RestDynamic.raised)
                .activitySystemActionForegroundColor(RestDynamic.primary)
                .widgetURL(RestLinks.workout)
        } dynamicIsland: { context in
            let model = RestActivityModel(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { RestExpandedLeading(model: model) }
                DynamicIslandExpandedRegion(.trailing) { RestExpandedTrailing(model: model) }
                DynamicIslandExpandedRegion(.bottom) { RestExpandedBottom(model: model) }
            } compactLeading: {
                RestCompactLeading(model: model)
            } compactTrailing: {
                RestCompactTrailing(model: model)
            } minimal: {
                RestMinimal(model: model)
            }
            .widgetURL(RestLinks.workout)
            .keylineTint(RestTokens.emberDark)
        }
    }
}

/// Light / dark card tints for activityBackgroundTint (one Color, both appearances).
enum RestDynamic {
    static let raised = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x1E / 255, green: 0x1E / 255, blue: 0x21 / 255, alpha: 1) : .white })
    static let accentSoft = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x3A / 255, green: 0x1E / 255, blue: 0x0E / 255, alpha: 1) : UIColor(red: 0xFC / 255, green: 0xED / 255, blue: 0xE5 / 255, alpha: 1) })
    static let primary = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0xF5 / 255, green: 0xF4 / 255, blue: 0xF1 / 255, alpha: 1) : UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1) })
}

/// The extension only draws; the intents run in Lift's process.
enum RestIntentHandler {
    static func addThirty() async {}
    static func skip() async {}
    static func adjustReps(_ delta: Int) async {}
    static func logSet() async {}
}
