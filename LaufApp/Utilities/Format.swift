import Foundation

/// Einheitliche Formatierung von Distanzen, Zeiten und Pace.
enum Format {
    /// "5,23 km"
    static func distance(_ meters: Double, decimals: Int = 2) -> String {
        kilometers(meters, decimals: decimals) + " km"
    }

    /// "5,23" (ohne Einheit)
    static func kilometers(_ meters: Double, decimals: Int = 2) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(decimals)))
    }

    /// "1:02:03" oder "25:03"
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Pace in Sekunden pro km → "5:12"
    static func pace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0, secondsPerKm < 3600 else { return "–:––" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Pace mit Einheit → "5:12 /km"
    static func paceUnit(_ secondsPerKm: Double) -> String { pace(secondsPerKm) + " /km" }

    static func elevation(_ meters: Double) -> String { "\(Int(meters.rounded())) m" }

    /// Gesprochene Pace, z.B. "5 Minuten 30 pro Kilometer"
    static func spokenPace(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m) Minuten pro Kilometer" : "\(m) Minuten \(s) pro Kilometer"
    }

    /// Gesprochene Zeit, z.B. "5 Minuten 30" oder "1 Stunde 5 Minuten"
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 Stunde" : "\(h) Stunden") }
        if m > 0 || h > 0 { parts.append(m == 1 ? "1 Minute" : "\(m) Minuten") }
        if h == 0 { parts.append(s == 1 ? "1 Sekunde" : "\(s) Sekunden") }
        return parts.joined(separator: " ")
    }
}

extension Calendar {
    /// Kalender mit Montag als Wochenbeginn (deutsche Konvention).
    static var mondayFirst: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    /// Wochentag als Index 0 = Montag … 6 = Sonntag.
    func weekdayIndex(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7
    }

    /// Kurzname des Wochentags für Index 0 = Montag … 6 = Sonntag ("Mo", "Di", …).
    static func weekdayShortName(_ index: Int) -> String {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][index]
    }

    static func weekdayName(_ index: Int) -> String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][index]
    }

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
