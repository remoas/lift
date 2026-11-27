#if DEBUG
import SwiftUI
import LiftCore

/// Review renders of the rest Live Activity for CDO's QA (design/live-activity.md
/// §10, AC 112). These host the exact views the widget extension draws
/// (Shared/LiveActivity) at Lock Screen and Dynamic Island sizes; the wallpaper,
/// clock and Island outline around them are stand-ins for system chrome.
struct LiveActivityGallery: View {
    let frame: String
    @Environment(\.colorScheme) private var scheme

    static let names = ["la-lock-running", "la-lock-after-miss", "la-lock-long-name", "la-lock-rest-over-highlight",
                        "la-lock-settled", "la-lock-aod", "la-island-compact", "la-island-minimal",
                        "la-island-expanded", "la-island-rest-over", "la-standby",
                        "la-lock-resting-loaded", "la-lock-resting-bw", "la-lock-rest-over-loaded", "la-lock-rest-over-bw",
                        "la-lock-ready-loaded", "la-lock-ready-bw", "la-lock-ready-belt", "la-lock-ready-assist",
                        "la-island-compact-resting", "la-island-compact-ready", "la-island-minimal-resting",
                        "la-island-minimal-ready", "la-island-expanded-resting", "la-island-expanded-ready",
                        "la-island-expanded-ready-bw", "la-island-compact-ready-belt",
                        "la-lock-ready-bw-missed", "la-island-expanded-ready-bw-missed"]

    private func state(name: String = "Barbell Bench Press", set: Int? = 3, weight: Double = 185, reps: Int = 9,
                       kind: LoadKind = .loaded, over: Bool = false, highlight: Bool = false,
                       phase: RestActivityPhase = .resting,
                       targetWeight: Double? = 185, targetReps: Int? = 9,
                       needsWeight: Bool = false,
                       lastWeight: Double? = nil, lastReps: Int? = nil) -> RestActivityAttributes.ContentState {
        let now = Date()
        let end: Date
        switch phase {
        case .resting: end = over ? now : now.addingTimeInterval(102)
        case .restOver: end = now
        case .ready: end = now
        }
        return .init(exercise: name, setNumber: set, weight: weight, unit: .lb, reps: reps,
                     bodyweight: kind == .bodyweight, kind: kind,
                     start: now.addingTimeInterval(-48), end: end,
                     over: over || phase == .restOver, highlight: highlight, phase: phase,
                     targetWeight: targetWeight, targetReps: targetReps, needsWeight: needsWeight,
                     lastWeight: lastWeight ?? weight, lastReps: lastReps ?? reps)
    }

    private var model: RestActivityModel {
        switch frame {
        case "la-lock-after-miss":
            return .init(state: state(reps: 7, targetWeight: 185, targetReps: 9, lastReps: 7), isStale: false)
        case "la-lock-long-name":
            return .init(state: state(name: "Single-Arm Dumbbell Incline Bench Press (Neutral Grip)", set: 12, weight: 102.5, targetWeight: 102.5, targetReps: 8), isStale: false)
        case "la-lock-rest-over-highlight":
            return .init(state: state(over: true, highlight: true, phase: .restOver), isStale: false)
        case "la-lock-settled", "la-island-rest-over", "la-lock-rest-over-loaded":
            return .init(state: state(over: true, phase: .restOver), isStale: false)
        case "la-lock-resting-loaded", "la-island-compact-resting", "la-island-minimal-resting", "la-island-expanded-resting":
            return .init(state: state(), isStale: false)
        case "la-lock-resting-bw":
            return .init(state: state(name: "Pull-Up", weight: 0, reps: 12, kind: .bodyweight, targetWeight: 0, targetReps: 13, lastReps: 12), isStale: false)
        case "la-lock-rest-over-bw":
            return .init(state: state(name: "Pull-Up", weight: 0, reps: 12, kind: .bodyweight, over: true, phase: .restOver, targetWeight: 0, targetReps: 13, lastReps: 12), isStale: false)
        case "la-lock-ready-loaded", "la-island-compact-ready", "la-island-minimal-ready", "la-island-expanded-ready":
            return .init(state: state(phase: .ready), isStale: false)
        case "la-lock-ready-bw", "la-island-expanded-ready-bw":
            // First set of the exercise: stepper is the target (13). Last: is last session.
            return .init(state: state(name: "Pull-Up", set: 1, weight: 0, reps: 13, kind: .bodyweight, phase: .ready, targetWeight: 0, targetReps: 13, lastReps: 12), isStale: false)
        case "la-lock-ready-bw-missed", "la-island-expanded-ready-bw-missed":
            // Later set after a miss: stepper stays at the 10 just logged, Beat stays 13.
            return .init(state: state(name: "Pull-Up", weight: 0, reps: 10, kind: .bodyweight, phase: .ready, targetWeight: 0, targetReps: 13, lastReps: 10), isStale: false)
        case "la-lock-ready-belt", "la-island-compact-ready-belt":
            return .init(state: state(name: "Pull-Up", set: 1, weight: 25, reps: 9, kind: .bodyweight, phase: .ready, targetWeight: 25, targetReps: 9, lastReps: 8), isStale: false)
        case "la-lock-ready-assist":
            return .init(state: state(name: "Assisted Pull-Up", set: 1, weight: 40, reps: 9, kind: .assisted, phase: .ready, targetWeight: 40, targetReps: 9, lastReps: 8), isStale: false)
        default:
            return .init(state: state(), isStale: false)
        }
    }

    var body: some View {
        Group {
            if frame.hasPrefix("la-island") {
                island
            } else if frame == "la-standby" {
                standBy
            } else {
                lockScreen
            }
        }
        .statusBarHidden(frame.hasPrefix("la-lock") || frame == "la-standby")
    }

    // MARK: Lock Screen

    private var aod: Bool { frame == "la-lock-aod" }

    private var lockScreen: some View {
        ZStack(alignment: .top) {
            wallpaper.ignoresSafeArea()
            if aod { Color.black.opacity(0.72).ignoresSafeArea() }
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title3.weight(.semibold))
                    Text("9:41").font(.system(size: 88, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(aod ? 0.55 : 0.95))
                .padding(.top, 54)
                Spacer()
                card.padding(.horizontal, 14)
                Text("Render of the Lift Live Activity views · system chrome is a stand-in")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 34)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The system draws this header on a device.
            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill").font(.caption2.weight(.bold))
                    .foregroundStyle(.white).frame(width: 18, height: 18)
                    .background(RestTokens.emberDark, in: RoundedRectangle(cornerRadius: 4))
                Text("Lift").font(.footnote.weight(.semibold))
                Spacer()
                Text("now").font(.footnote)
            }
            .foregroundStyle(RestTokens.secondary(scheme))
            .padding(.horizontal, 16).padding(.top, 12)
            RestLockScreenView(model: model)
                .environment(\.isLuminanceReduced, aod)
        }
        .background(RestLockScreenView.background(model, scheme).opacity(aod ? 0.0 : 1),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(aod ? AnyShapeStyle(Color.black.opacity(0.3)) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var wallpaper: some View {
        LinearGradient(colors: scheme == .dark ? [Color(hex: 0x1B2A4A), Color(hex: 0x4A2C5E), Color(hex: 0x0E0E14)]
                                               : [Color(hex: 0x8EC5FC), Color(hex: 0xE0C3FC), Color(hex: 0xF9D5A7)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Dynamic Island (always dark)

    private var island: some View {
        ZStack(alignment: .top) {
            Color(hex: scheme == .dark ? 0x0B0B0C : 0xF4F3F1).ignoresSafeArea()
            VStack(spacing: 24) {
                switch frame {
                case "la-island-compact", "la-island-compact-resting", "la-island-compact-ready", "la-island-compact-ready-belt":
                    HStack {
                        RestCompactLeading(model: model)
                        Spacer()
                        RestCompactTrailing(model: model)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: 250, height: 37)
                    .background(.black, in: Capsule())
                case "la-island-minimal", "la-island-minimal-resting", "la-island-minimal-ready":
                    HStack(spacing: 8) {
                        Capsule().fill(.black).frame(width: 126, height: 37)
                        RestMinimal(model: model).frame(width: 37, height: 37).background(.black, in: Circle())
                    }
                default:
                    VStack(spacing: 10) {
                        HStack(alignment: .center) {
                            RestExpandedLeading(model: model)
                            Spacer(minLength: 8)
                            RestExpandedTrailing(model: model)
                        }
                        RestExpandedBottom(model: model)
                    }
                    .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 16)
                    .frame(width: 371)
                    .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                }
                Text("Render of the Lift Live Activity views · Island outline is a stand-in")
                    .font(.caption2).foregroundStyle(RestTokens.secondary(scheme))
            }
            // Below the sim's own Island cutout, so the render isn't hidden by it.
            .padding(.top, 72)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: StandBy: the Lock Screen presentation, scaled (no custom family)

    private var standBy: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RestLockScreenView(model: model)
                .frame(width: 360)
                .background(RestTokens.raised(.dark), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, .dark)
                .scaleEffect(1.08)
            VStack { Spacer(); Text("StandBy reuses the Lock Screen view, scaled by the system · render").font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(.bottom, 30) }
        }
    }
}
#endif
