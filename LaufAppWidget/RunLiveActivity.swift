import SwiftUI
import WidgetKit
import ActivityKit

@main
struct LaufAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

/// Live-Aktivität während eines Laufs: Zeit, Distanz, Pace und – beim Folgen einer Route –
/// die nächste Abzweigung. Auf dem Sperrbildschirm und in der Dynamic Island.
struct RunLiveActivity: Widget {
    static let accent = Color(red: 0.99, green: 0.36, blue: 0.0)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Zeit", systemImage: "figure.run").font(.caption2).foregroundStyle(.secondary)
                        TimerText(state: state).font(.title3.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: 100, alignment: .leading)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Distanz").font(.caption2).foregroundStyle(.secondary)
                        Text(ActivityFormat.kilometers(state.distance) + " km")
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.turn != nil || state.routeHint != nil {
                        TurnRow(state: state, compact: true)
                    } else if let step = state.stepText {
                        Text(step).font(.subheadline).lineLimit(1)
                    } else {
                        Text("Pace \(ActivityFormat.pace(state.pace)) /km").font(.subheadline.monospacedDigit())
                    }
                }
            } compactLeading: {
                if let turn = state.turn, let d = state.turnDistance, d < 400 {
                    HStack(spacing: 2) {
                        Image(systemName: turn.symbol).foregroundStyle(Self.accent)
                        Text(ActivityFormat.shortDistance(d)).font(.caption2.monospacedDigit())
                    }
                } else {
                    Image(systemName: state.isPaused ? "pause.fill" : "figure.run").foregroundStyle(Self.accent)
                }
            } compactTrailing: {
                TimerText(state: state)
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: state.turn.map(\.symbol) ?? "figure.run").foregroundStyle(Self.accent)
            }
            .keylineTint(Self.accent)
        }
    }
}

/// Laufende Uhr (zählt ohne Aktualisierung der App weiter); in der Pause steht sie.
private struct TimerText: View {
    let state: RunActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        // Bei abgedunkeltem Sperrbildschirm zeigt iOS laufende Uhren ohne Sekunden („1:––“);
        // dann den zuletzt gemeldeten Stand anzeigen (die App aktualisiert alle paar Sekunden).
        if state.isPaused || isLuminanceReduced {
            Text(ActivityFormat.duration(state.movingTime))
        } else {
            // Die Uhr belegt die Breite des längsten möglichen Werts; mit festem Rahmen bleibt sie lesbar
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct LockScreenView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .foregroundStyle(RunLiveActivity.accent)
                Text(attributes.routeName ?? attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if state.isPaused {
                    Label("Pausiert", systemImage: "pause.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(.white)

            HStack(alignment: .firstTextBaseline) {
                metric("Zeit") { TimerText(state: state).frame(maxWidth: 110, alignment: .leading) }
                metric("Distanz") { Text(ActivityFormat.kilometers(state.distance)) + Text(" km").font(.caption) }
                metric("Pace") { Text(ActivityFormat.pace(state.pace)) + Text(" /km").font(.caption) }
            }

            if state.turn != nil || state.routeHint != nil {
                TurnRow(state: state, compact: false)
            } else if let step = state.stepText {
                Text(step)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }

    private func metric<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
            value()
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Nächste Abzweigung bzw. Hinweis zur Route.
private struct TurnRow: View {
    let state: RunActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: compact ? 18 : 22, weight: .bold))
                .foregroundStyle(state.isOffRoute ? Color.yellow : Color.white)
                .frame(width: compact ? 30 : 40, height: compact ? 30 : 40)
                .background(state.isOffRoute ? Color.yellow.opacity(0.25) : RunLiveActivity.accent,
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                if let turn = state.turn, let d = state.turnDistance, !state.isOffRoute {
                    Text("In \(ActivityFormat.shortDistance(d))")
                        .font((compact ? Font.subheadline : .headline).weight(.bold).monospacedDigit())
                    Text(turn.instruction)
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let hint = state.routeHint {
                    let prominent = state.turn == nil || state.isOffRoute
                    let font: Font = prominent ? (compact ? Font.subheadline : Font.headline).weight(.semibold) : Font.caption
                    Text(hint)
                        .font(font)
                        .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        if state.isOffRoute { return "exclamationmark.triangle.fill" }
        return state.turn?.symbol ?? "flag.checkered"
    }
}
