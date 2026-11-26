import SwiftUI

/// Shared-element IDs (spec §8.1). One namespace, owned by RootView.
enum LiftTransitionID: Hashable {
    case workout(UUID)       // Workout.id, reserved before presenting
    case workoutMini(UUID)   // same Workout.id, minimised bar
    case exercise(UUID)      // Exercise.id
    case prBanner(UUID)      // SetEntry.id, banner container
    case prValue(UUID)       // SetEntry.id, the shared number
}

private struct LiftNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The one `@Namespace` for shared transitions, set by RootView.
    var liftNamespace: Namespace.ID? {
        get { self[LiftNamespaceKey.self] }
        set { self[LiftNamespaceKey.self] = newValue }
    }
}

/// iOS 18+: marks a zoom source. iOS 17: no-op (standard cover / push).
private struct LiftZoomSource: ViewModifier {
    let id: LiftTransitionID
    var radius: CGFloat = Theme.Radius.button
    @Environment(\.liftNamespace) private var ns

    func body(content: Content) -> some View {
        if let ns {
            if #available(iOS 18, *) {
                content.matchedTransitionSource(id: id, in: ns) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// iOS 18+: zoom destination. iOS 17: the standard transition.
private struct LiftZoomDestination: ViewModifier {
    let id: LiftTransitionID
    @Environment(\.liftNamespace) private var ns

    func body(content: Content) -> some View {
        if let ns {
            if #available(iOS 18, *) {
                content.navigationTransition(.zoom(sourceID: id, in: ns))
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// `matchedGeometryEffect` that can be switched off (an unmatched key), so a
/// view can start at its partner's frame and then animate to its own layout.
private struct LiftMatched: ViewModifier {
    let id: LiftTransitionID
    var active: Bool = true
    var properties: MatchedGeometryProperties = .frame
    var isSource: Bool = true
    @Environment(\.liftNamespace) private var ns

    private struct Key: Hashable { let id: LiftTransitionID; let active: Bool }

    func body(content: Content) -> some View {
        if let ns {
            content.matchedGeometryEffect(id: Key(id: id, active: active), in: ns, properties: properties, isSource: isSource)
        } else {
            content
        }
    }
}

extension View {
    func liftZoomSource(_ id: LiftTransitionID, radius: CGFloat = Theme.Radius.button) -> some View {
        modifier(LiftZoomSource(id: id, radius: radius))
    }
    func liftZoomDestination(_ id: LiftTransitionID) -> some View {
        modifier(LiftZoomDestination(id: id))
    }
    func liftMatched(_ id: LiftTransitionID, active: Bool = true, properties: MatchedGeometryProperties = .frame, isSource: Bool = true) -> some View {
        modifier(LiftMatched(id: id, active: active, properties: properties, isSource: isSource))
    }
}
