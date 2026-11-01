import Foundation
import EventKit
import UIKit

/// Trägt den Trainingsplan in einen eigenen Kalender "LaufApp Training" der Kalender-App ein.
/// Der Kalender gehört nur der App: Beim Aktualisieren wird sein Inhalt komplett ersetzt,
/// andere Termine bleiben unberührt.
@MainActor
enum CalendarExport {
    struct Options: Codable, Equatable {
        /// Ganztägige Einträge oder mit Uhrzeit
        var allDay = true
        var hour = 18
        var minute = 0
        /// Erinnerung: bei ganztägigen Einträgen um 8 Uhr, sonst 1 Stunde vorher
        var reminder = true
    }

    enum ExportError: LocalizedError {
        case accessDenied
        case noCalendarSource

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "LaufApp hat keinen Zugriff auf deine Kalender. Du kannst ihn in den Einstellungen unter Datenschutz & Sicherheit → Kalender erlauben."
            case .noCalendarSource:
                "Es wurde kein Kalenderkonto gefunden, in dem LaufApp einen Kalender anlegen kann."
            }
        }
    }

    static let calendarTitle = "LaufApp Training"

    private static let store = EKEventStore()
    private static let calendarIDKey = "calendarExport.calendarID"
    private static let syncedPlanKey = "calendarExport.planID"
    private static let optionsKey = "calendarExport.options"

    static var options: Options {
        get {
            guard let data = UserDefaults.standard.data(forKey: optionsKey),
                  let options = try? JSONDecoder().decode(Options.self, from: data) else { return Options() }
            return options
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: optionsKey) }
    }

    /// Plan, der zuletzt in den Kalender exportiert wurde.
    static var syncedPlanID: UUID? {
        get { UserDefaults.standard.string(forKey: syncedPlanKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: syncedPlanKey) }
    }

    static func isSynced(_ plan: TrainingPlan) -> Bool { syncedPlanID == plan.id }

    private static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Exportiert den Plan (ersetzt den bisherigen Inhalt des LaufApp-Kalenders).
    /// Gibt die Anzahl der eingetragenen Einheiten zurück.
    @discardableResult
    static func export(_ plan: TrainingPlan, options: Options) async throws -> Int {
        if !hasAccess {
            guard try await store.requestFullAccessToEvents() else { throw ExportError.accessDenied }
        }
        let calendar = try appCalendar()
        try removeAllEvents(in: calendar)

        let paces = VDOT.paces(vdot: plan.formVDOT)
        var count = 0
        for workout in plan.weeks.flatMap(\.workouts) where !plan.isSkipped(workout) {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "\(workout.title) · \(Format.distance(workout.distance, decimals: 1))"
            var notes = workout.steps.map { WorkoutStepSummary.text($0) + "\n\n" } ?? ""
            notes += workout.details
            event.notes = notes
            let day = Calendar.current.startOfDay(for: workout.date)
            if options.allDay {
                event.isAllDay = true
                event.startDate = day
                event.endDate = day
                if options.reminder { event.addAlarm(EKAlarm(relativeOffset: 8 * 3600)) }
            } else {
                let start = Calendar.current.date(bySettingHour: options.hour, minute: options.minute, second: 0, of: day) ?? day
                // Dauer grob schätzen: Wettkampf mit Zielzeit, sonst mit langsamer lockerer Pace, auf 5 min gerundet
                let seconds = workout.kind == .race ? plan.goalTime : workout.distance / 1000 * paces.easySlow
                event.startDate = start
                event.endDate = start.addingTimeInterval(max(1800, (seconds / 300).rounded(.up) * 300))
                if options.reminder { event.addAlarm(EKAlarm(relativeOffset: -3600)) }
            }
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        self.options = options
        syncedPlanID = plan.id
        return count
    }

    /// Aktualisiert den Kalender nach Änderungen am Plan, falls dieser Plan exportiert wurde.
    /// Fragt nicht nach Berechtigungen und schlägt still fehl.
    static func resyncIfNeeded(_ plan: TrainingPlan) {
        guard isSynced(plan), hasAccess else { return }
        Task { try? await export(plan, options: options) }
    }

    /// Ein neuer Plan ersetzt den bisher exportierten im Kalender.
    static func replaceSyncedPlan(with plan: TrainingPlan, previous: [TrainingPlan]) {
        guard let synced = syncedPlanID, previous.contains(where: { $0.id == synced }), hasAccess else { return }
        Task { try? await export(plan, options: options) }
    }

    /// Entfernt alle Einträge des Plans aus dem Kalender.
    static func remove(_ plan: TrainingPlan) throws {
        guard isSynced(plan) else { return }
        syncedPlanID = nil
        guard hasAccess, let calendar = existingCalendar() else { return }
        try removeAllEvents(in: calendar)
        try store.commit()
    }

    // MARK: - Kalender

    private static func existingCalendar() -> EKCalendar? {
        UserDefaults.standard.string(forKey: calendarIDKey).flatMap { store.calendar(withIdentifier: $0) }
    }

    /// Eigener Kalender der App; wird angelegt, falls er fehlt (z. B. in der Kalender-App gelöscht).
    private static func appCalendar() throws -> EKCalendar {
        if let calendar = existingCalendar() { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = UIColor.systemOrange.cgColor
        // Bevorzugt das Konto des Standardkalenders (meist iCloud), sonst ein lokales Konto
        let candidates = [store.defaultCalendarForNewEvents?.source].compactMap { $0 }
            + store.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .local }
        for source in candidates {
            calendar.source = source
            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
                return calendar
            }
        }
        throw ExportError.noCalendarSource
    }

    private static func removeAllEvents(in calendar: EKCalendar) throws {
        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let end = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        for event in store.events(matching: predicate) {
            try store.remove(event, span: .thisEvent, commit: false)
        }
    }
}
