import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import LiftCore

// Lock Screen, StandBy and Dynamic Island views for the rest Live Activity
// (design/live-activity.md §3–9). Ember only on the ring / draining line and
// on Skip; tabular numerals; no bar, no "Beat it".

enum RestTokens {
    static let emberDark = Color(red: 1.0, green: 0x8A / 255, blue: 0x3D / 255)        // #FF8A3D
    static let emberLight = Color(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255) // #C2410C
    static func ember(_ s: ColorScheme) -> Color { s == .dark ? emberDark : emberLight }
    static func raised(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x1E1E21) : .white }
    static func sunken(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x161618) : Color(hex: 0xF4F3F1) }
    static func primary(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xF5F4F1) : Color(hex: 0x141413) }
    static func secondary(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0xA6A39E) : Color(hex: 0x5E5B57) }
    static func accentSoft(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x3A1E0E) : Color(hex: 0xFCEDE5) }
    static func track(_ s: ColorScheme) -> Color { s == .dark ? Color(hex: 0x2C2C30) : Color(hex: 0xE6E4E0) }
    // The Island is always dark.
    static let islandPrimary = Color(hex: 0xF5F4F1)
    static let islandSecondary = Color(hex: 0xA6A39E)
    static let islandTrack = Color(hex: 0x6E6B67)
    static let islandSunken = Color(hex: 0x2C2C30)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// What the views draw, from the content state plus the system's stale flag.
struct RestActivityModel {
    var state: RestActivityAttributes.ContentState
    var isStale: Bool

    var over: Bool { state.over || isStale }
    var interval: ClosedRange<Date> { state.start...max(state.end, state.start.addingTimeInterval(1)) }
}

enum RestRender {
    /// True inside the widget extension, where ActivityKit draws ProgressView(timerInterval:).
    static let inWidget = Bundle.main.bundleURL.pathExtension == "appex"
}

/// Signature 2: a 3 pt Ember line that drains left-to-right, left-anchored.
struct DrainingLine: View {
    let model: RestActivityModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isLuminanceReduced) private var aod

    var body: some View {
        Group {
            if model.over {
                Capsule().fill(RestTokens.track(scheme))
            } else {
                ProgressView(timerInterval: model.interval, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(RestTokens.ember(scheme).opacity(aod ? 0.6 : 1))
                    .labelsHidden()
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// The Island's Ember mini ring: butt caps, from 12 o'clock, draining to empty.
struct MiniRing: View {
    let model: RestActivityModel
    var size: CGFloat = 23
    var line: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(RestTokens.islandTrack.opacity(0.5), lineWidth: line)
            if !model.over {
                if RestRender.inWidget {
                    // The system draws this as a smooth stroke and drains it without updates.
                    ProgressView(timerInterval: model.interval, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(RestTokens.emberDark)
                        .labelsHidden()
                } else {
                    // In-app review renders: the same stroke, drawn (UIKit's circular
                    // ProgressView is a ticked spinner outside a widget; QA Should 2).
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let total = model.interval.upperBound.timeIntervalSince(model.interval.lowerBound)
                        let left = max(0, model.interval.upperBound.timeIntervalSince(ctx.date))
                        Circle()
                            .trim(from: 0, to: total > 0 ? left / total : 0)
                            .stroke(RestTokens.emberDark, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One line; a long name ends at a word with "…", never mid-word (AC 111).
struct ExerciseName: View {
    let name: String
    var body: some View {
        let c = RestActivityText.nameCandidates(name)
        ViewThatFits(in: .horizontal) {
            ForEach(c, id: \.self) { Text($0).lineLimit(1).fixedSize() }
            // Even the first word is too wide: scale it rather than cut it.
            Text(c.last ?? name).lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityLabel(name)
    }
}

/// m:ss from the system timer (ticks without updates); 0:00 once over.
struct RestTime: View {
    let model: RestActivityModel
    var body: some View {
        Group {
            if model.over {
                Text("0:00")
            } else {
                Text(timerInterval: model.interval, countsDown: true, showsHours: false)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityLabel(model.over ? "Rest over" : "Rest remaining")
    }
}

/// One line, never cut mid-number: the first rung of the ladder that fits.
struct NextLine: View {
    let model: RestActivityModel
    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(model.state.ladder, id: \.self) { Text($0).lineLimit(1).fixedSize() }
        }
        .monospacedDigit()
    }
}

struct RestChips: View {
    var height: CGFloat = 44
    var minWidth: CGFloat = 56
    var primary: Color
    var skip: Color
    var sunken: Color

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddRestTimeIntent()) {
                Text("+30s").font(.body.weight(.medium)).monospacedDigit()
                    .foregroundStyle(primary)
                    .frame(minWidth: minWidth, minHeight: height)
                    .frame(maxWidth: .infinity)
                    .background(sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("30 seconds more, this break only")
            Button(intent: SkipRestIntent()) {
                Text("Skip").font(.body.weight(.semibold))
                    .foregroundStyle(skip)
                    .frame(minWidth: minWidth, minHeight: height)
                    .frame(maxWidth: .infinity)
                    .background(sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lock Screen (and StandBy, scaled by the system).
struct RestLockScreenView: View {
    let model: RestActivityModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isLuminanceReduced) private var aod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DrainingLine(model: model)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if model.over {
                        Text(RestActivityText.restOver(setNumber: model.state.setNumber))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(RestTokens.primary(scheme))
                            .lineLimit(1)
                    }
                    ExerciseName(name: model.state.exercise)
                        .font(.body.weight(.semibold)).foregroundStyle(RestTokens.primary(scheme))
                    Group {
                        if model.over { Text(model.state.load).monospacedDigit().lineLimit(1) } else { NextLine(model: model) }
                    }
                    .font(.subheadline).foregroundStyle(RestTokens.secondary(scheme))
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                RestTime(model: model)
                    .font(.system(.largeTitle, design: .default).weight(.semibold))
                    .foregroundStyle(RestTokens.primary(scheme))
                    .layoutPriority(2)
            }
            if !model.over && !aod {
                RestChips(primary: RestTokens.primary(scheme), skip: RestTokens.ember(scheme), sunken: RestTokens.sunken(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.15), value: model.over)
    }

    static func background(_ model: RestActivityModel, _ scheme: ColorScheme) -> Color {
        model.state.highlight ? RestTokens.accentSoft(scheme) : RestTokens.raised(scheme)
    }
}

/// Expanded Island regions (always dark).
struct RestExpandedLeading: View {
    let model: RestActivityModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.over {
                Text(RestActivityText.restOver(setNumber: model.state.setNumber))
                    .font(.footnote.weight(.semibold)).foregroundStyle(RestTokens.islandPrimary).lineLimit(1)
            }
            ExerciseName(name: model.state.exercise)
                .font(.body.weight(.semibold)).foregroundStyle(RestTokens.islandPrimary)
            Group {
                if model.over { Text(model.state.load).monospacedDigit().lineLimit(1) } else { NextLine(model: model) }
            }
            .font(.footnote).foregroundStyle(RestTokens.islandSecondary)
        }
        .padding(.leading, 6)
    }
}

struct RestExpandedTrailing: View {
    let model: RestActivityModel
    var body: some View {
        HStack(spacing: 8) {
            MiniRing(model: model, size: 34, line: 3)
            RestTime(model: model)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(RestTokens.islandPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.trailing, 6)
    }
}

struct RestExpandedBottom: View {
    let model: RestActivityModel
    var body: some View {
        if !model.over {
            RestChips(height: 40, minWidth: 56, primary: RestTokens.islandPrimary, skip: RestTokens.emberDark, sunken: RestTokens.islandSunken)
                .padding(.horizontal, 6)
        }
    }
}

struct RestCompactTrailing: View {
    let model: RestActivityModel
    var body: some View {
        RestTime(model: model)
            .font(.callout.weight(.semibold))
            .foregroundStyle(RestTokens.islandPrimary)
            .frame(maxWidth: 52)
    }
}
