import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

// Gemeinsamer Code von App und Widget-Erweiterung (Live-Aktivität während eines Laufs).

/// Richtung an einer Abzweigung der Route.
enum TurnDirection: String, Codable, Hashable {
    case slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn

    /// Kurzer Hinweis, z. B. „links abbiegen“
    var instruction: String {
        switch self {
        case .slightLeft: "leicht links halten"
        case .left: "links abbiegen"
        case .sharpLeft: "scharf links abbiegen"
        case .slightRight: "leicht rechts halten"
        case .right: "rechts abbiegen"
        case .sharpRight: "scharf rechts abbiegen"
        case .uTurn: "umkehren"
        }
    }

    var symbol: String {
        switch self {
        case .slightLeft: "arrow.up.left"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.down"
        }
    }

    /// Richtung aus der Änderung der Laufrichtung (Grad, positiv = im Uhrzeigersinn = rechts)
    init?(angle: Double) {
        let a = abs(angle)
        guard a >= 30 else { return nil }
        let right = angle > 0
        switch a {
        case ..<55: self = right ? .slightRight : .slightLeft
        case ..<120: self = right ? .right : .left
        case ..<155: self = right ? .sharpRight : .sharpLeft
        default: self = .uTurn
        }
    }
}

/// Abzweigung einer Route: Richtung und Position (Meter entlang der Route).
struct RouteTurn: Codable, Hashable {
    var along: Double
    var direction: TurnDirection
}

#if canImport(ActivityKit) && os(iOS)
/// Daten der Live-Aktivität während eines Laufs.
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        /// Startpunkt für die laufende Uhr (jetzt − Bewegungszeit); die Uhr zählt ohne Aktualisierung weiter
        var timerStart: Date
        /// Bewegungszeit in Sekunden (für die Anzeige im Pausenzustand)
        var movingTime: TimeInterval
        /// Meter
        var distance: Double
        /// Aktuelle Pace in s/km (0 = unbekannt)
        var pace: Double
        /// Nächste Abzweigung auf der Route
        var turn: TurnDirection?
        /// Meter bis zur nächsten Abzweigung bzw. bis zum Ziel/Start
        var turnDistance: Double?
        /// Hinweis zur Route, z. B. „Noch 2,3 km bis zum Ziel“ oder „Abseits der Route“
        var routeHint: String?
        var isOffRoute: Bool = false
        /// Aktueller Abschnitt eines geführten Workouts, z. B. „Intervall 2/5 · noch 300 m“
        var stepText: String?
    }

    /// Name des Laufs bzw. Workouts
    var title: String
    var routeName: String?
}
#endif

/// Formatierung für die Live-Aktivität (unabhängig von der App).
enum ActivityFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds).rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func kilometers(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(2)))
    }

    static func pace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm > 0, secondsPerKm < 3600 else { return "–:––" }
        let s = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// „350 m“ bzw. „1,2 km“, kurze Strecken auf 10 m gerundet
    static func shortDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(max(0, Int((meters / 10).rounded()) * 10)) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}
