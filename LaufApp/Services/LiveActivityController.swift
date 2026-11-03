import Foundation
import ActivityKit

/// Steuert die Live-Aktivität (Sperrbildschirm und Dynamic Island) während einer Aufzeichnung.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<RunActivityAttributes>?
    private var lastState: RunActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    /// In den Einstellungen abschaltbar (Standard: an)
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "liveActivity") as? Bool ?? true }

    func start(_ recorder: RunRecorder) {
        endAll()
        guard Self.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RunActivityAttributes(title: recorder.plannedWorkout?.title ?? "Lauf", routeName: recorder.routeName)
        let state = Self.state(from: recorder)
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        lastState = state
        lastUpdate = .now
    }

    /// Aktualisiert die Anzeige höchstens alle 5 Sekunden, bei wichtigen Änderungen (Pause,
    /// neue Abzweigung, Abschnittswechsel, Abkommen von der Route) sofort.
    func update(_ recorder: RunRecorder) {
        guard let activity else { return }
        let state = Self.state(from: recorder)
        if let last = lastState, Date.now.timeIntervalSince(lastUpdate) < 5,
           last.isPaused == state.isPaused, last.turn == state.turn, last.isOffRoute == state.isOffRoute,
           last.stepText?.prefix(12) == state.stepText?.prefix(12), (last.routeHint == nil) == (state.routeHint == nil) {
            return
        }
        lastState = state
        lastUpdate = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Übrig gebliebene Aktivitäten beenden (z. B. nach einem Absturz während eines Laufs)
    func endAll() {
        activity = nil
        for activity in Activity<RunActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func state(from r: RunRecorder) -> RunActivityAttributes.ContentState {
        let moving = r.movingTime()
        let pace = r.currentPace > 0 ? r.currentPace : r.averagePace
        var state = RunActivityAttributes.ContentState(
            isPaused: r.state == .paused, timerStart: Date.now.addingTimeInterval(-moving), movingTime: moving,
            distance: r.distance, pace: pace)

        if r.hasRoute {
            if !r.hasJoinedRoute {
                state.routeHint = r.distanceToRouteStart.map { "Zum Start der Route: \(ActivityFormat.shortDistance($0))" }
                    ?? "Zum Start der Route"
            } else if r.isOffRoute {
                state.isOffRoute = true
                state.routeHint = "Abseits der Route"
            } else if let turn = r.nextTurn {
                state.turn = turn.direction
                state.turnDistance = turn.along - r.routeProgress
                state.routeHint = "Noch \(ActivityFormat.shortDistance(r.routeRemaining)) bis zum Ziel"
            } else {
                state.routeHint = r.routeRemaining < 30 ? "Ziel erreicht"
                    : "Geradeaus – noch \(ActivityFormat.shortDistance(r.routeRemaining)) bis zum Ziel"
            }
        }
        if let step = r.currentStep {
            state.stepText = "\(step.label) · \(r.stepRemainingText())"
        } else if r.isWorkoutComplete {
            state.stepText = "Workout geschafft"
        }
        return state
    }
}
