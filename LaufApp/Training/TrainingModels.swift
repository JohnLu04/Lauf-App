import Foundation
import SwiftData
import SwiftUI

enum RaceGoal: String, Codable, CaseIterable, Identifiable {
    case fiveK, tenK, half, marathon
    var id: String { rawValue }

    var distance: Double {
        switch self {
        case .fiveK: 5000
        case .tenK: 10000
        case .half: 21097.5
        case .marathon: 42195
        }
    }

    var name: String {
        switch self {
        case .fiveK: "5 km"
        case .tenK: "10 km"
        case .half: "Halbmarathon"
        case .marathon: "Marathon"
        }
    }

    var shortName: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "HM"
        case .marathon: "M"
        }
    }

    var minWeeks: Int {
        switch self {
        case .fiveK: 6
        case .tenK: 8
        case .half: 10
        case .marathon: 12
        }
    }

    var maxWeeks: Int { self == .marathon ? 24 : 20 }

    var taperWeeks: Int {
        switch self {
        case .fiveK, .tenK: 1
        case .half: 2
        case .marathon: 3
        }
    }

    /// Spitzenlänge des langen Laufs (Meter), auf die der Plan hinarbeitet.
    var longRunPeak: Double {
        switch self {
        case .fiveK: 10000
        case .tenK: 14000
        case .half: 20000
        case .marathon: 32000
        }
    }

    /// Größte Steigerung des langen Laufs von einer Aufbauwoche zur nächsten (Meter).
    var longRunStep: Double {
        switch self {
        case .fiveK: 1000
        case .tenK: 1500
        case .half: 2000
        case .marathon: 2500
        }
    }

    /// Mindestumfang (km/Woche), ab dem das Ziel gut erreichbar ist.
    var recommendedMinWeeklyKm: Double {
        switch self {
        case .fiveK: 15
        case .tenK: 20
        case .half: 30
        case .marathon: 45
        }
    }

    /// Typischer Spitzenumfang (km/Woche) bei 5 Läufen pro Woche.
    var typicalPeakKm: Double {
        switch self {
        case .fiveK: 35
        case .tenK: 45
        case .half: 55
        case .marathon: 70
        }
    }
}

enum TrainingPhase: String, Codable {
    case base, build, peak, taper

    var name: String {
        switch self {
        case .base: "Grundlage"
        case .build: "Aufbau"
        case .peak: "Wettkampfspezifisch"
        case .taper: "Tapering"
        }
    }

    var color: Color {
        switch self {
        case .base: .blue
        case .build: .green
        case .peak: .orange
        case .taper: .purple
        }
    }
}

enum WorkoutKind: String, Codable {
    case easy, strides, long, threshold, intervals, repetition, racePace, race

    var name: String {
        switch self {
        case .easy: "Lockerer Lauf"
        case .strides: "Locker + Steigerungen"
        case .long: "Langer Lauf"
        case .threshold: "Schwellenlauf"
        case .intervals: "Intervalle"
        case .repetition: "Tempowiederholungen"
        case .racePace: "Wettkampftempo"
        case .race: "Wettkampf"
        }
    }

    var symbol: String {
        switch self {
        case .easy: "figure.walk.motion"
        case .strides: "figure.run"
        case .long: "road.lanes"
        case .threshold: "speedometer"
        case .intervals: "bolt.fill"
        case .repetition: "hare.fill"
        case .racePace: "flag.checkered"
        case .race: "trophy.fill"
        }
    }

    var color: Color {
        switch self {
        case .easy, .strides: .green
        case .long: .blue
        case .threshold: .orange
        case .intervals, .repetition: .red
        case .racePace: .purple
        case .race: .yellow
        }
    }

    var isQuality: Bool { ![.easy, .strides, .long].contains(self) }
}

/// Ein Abschnitt eines strukturierten Workouts, z.B. "Einlaufen 2 km" oder "Intervall 3 von 5".
struct WorkoutStep: Codable, Hashable {
    enum Kind: String, Codable {
        case warmup, run, recovery, cooldown

        var name: String {
            switch self {
            case .warmup: "Einlaufen"
            case .run: "Laufen"
            case .recovery: "Trabpause"
            case .cooldown: "Auslaufen"
            }
        }
    }

    var kind: Kind
    var label: String
    /// Länge in Metern – oder alternativ `duration`
    var distance: Double?
    /// Dauer in Sekunden
    var duration: TimeInterval?
    /// Zielpace-Bereich in s/km (schneller und langsamer Rand); nil = frei
    var paceFast: Double?
    var paceSlow: Double?

    var hasPaceTarget: Bool { paceFast != nil && paceSlow != nil }

    /// "800 m" / "2,0 km" / "1:30 min"
    var amountText: String {
        if let distance {
            return distance < 1000 ? "\(Int(distance)) m" : Format.distance(distance, decimals: 1)
        }
        if let duration {
            return duration < 60 ? "\(Int(duration)) s" : Format.duration(duration) + " min"
        }
        return ""
    }

    var paceText: String? {
        guard let paceFast, let paceSlow else { return nil }
        return paceSlow - paceFast < 3
            ? Format.paceUnit((paceFast + paceSlow) / 2)
            : "\(Format.pace(paceFast))–\(Format.pace(paceSlow)) /km"
    }
}

struct PlannedWorkout: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var kind: WorkoutKind
    /// Gesamtdistanz inkl. Ein-/Auslaufen (Meter)
    var distance: Double
    var title: String
    var details: String
    /// Strukturierter Ablauf für die Sprachführung (fehlt bei älteren Plänen)
    var steps: [WorkoutStep]?
}

struct PlanWeek: Codable, Identifiable, Hashable {
    var index: Int
    var startDate: Date
    var phase: TrainingPhase
    var isRecoveryWeek: Bool
    var workouts: [PlannedWorkout]
    var id: Int { index }
    var volume: Double { workouts.reduce(0) { $0 + $1.distance } }
}

@Model
final class TrainingPlan {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var goalRaw: String = RaceGoal.tenK.rawValue
    var raceDate: Date = Date()
    /// Zielzeit in Sekunden
    var goalTime: Double = 0
    var startVDOT: Double = 0
    var goalVDOT: Double = 0
    var runsPerWeek: Int = 4
    var isActive: Bool = true
    var weeksData: Data = Data()
    var completedData: Data = Data()
    var skippedData: Data = Data()
    /// Aktuelle Form (VDOT), wird beim Anpassen des Plans aktualisiert
    var currentVDOT: Double = 0
    var currentWeeklyKm: Double = 0
    var targetWeeklyKm: Double = 0
    /// Trainingstage als "0,2,4,6" (0 = Montag)
    var trainingDaysRaw: String = ""
    /// 0 = Montag … 6 = Sonntag
    var longRunDay: Int = 6

    init(input: PlanInput, generated: GeneratedPlan) {
        self.goalRaw = input.goal.rawValue
        self.raceDate = input.raceDate
        self.goalTime = input.goalTime
        self.startVDOT = input.currentVDOT
        self.currentVDOT = input.currentVDOT
        self.goalVDOT = generated.goalVDOT
        self.runsPerWeek = input.runsPerWeek
        self.currentWeeklyKm = input.currentWeeklyKm
        self.targetWeeklyKm = input.targetWeeklyKm
        self.trainingDays = input.trainingDays
        self.longRunDay = input.longRunDay
        self.weeks = generated.weeks
    }

    var goal: RaceGoal { RaceGoal(rawValue: goalRaw) ?? .tenK }

    /// Aktuelle Form; bei älteren Plänen die Form beim Erstellen
    var formVDOT: Double { currentVDOT > 0 ? currentVDOT : startVDOT }

    var trainingDays: Set<Int> {
        get {
            let days = Set(trainingDaysRaw.split(separator: ",").compactMap { Int($0) })
            return days.isEmpty ? Set(weeks.first?.workouts.map { Calendar.mondayFirst.weekdayIndex(of: $0.date) } ?? []) : days
        }
        set { trainingDaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    var skippedIDs: Set<UUID> {
        get { (try? JSONDecoder().decode(Set<UUID>.self, from: skippedData)) ?? [] }
        set { skippedData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func isSkipped(_ workout: PlannedWorkout) -> Bool { skippedIDs.contains(workout.id) }

    func toggleSkipped(_ workout: PlannedWorkout) {
        var ids = skippedIDs
        if ids.contains(workout.id) { ids.remove(workout.id) } else { ids.insert(workout.id) }
        skippedIDs = ids
    }

    /// Verschiebt ein Workout auf einen anderen Tag (auch in eine andere Woche).
    func move(_ workout: PlannedWorkout, to date: Date) {
        let cal = Calendar.mondayFirst
        var all = weeks
        guard let wi = all.firstIndex(where: { $0.workouts.contains { $0.id == workout.id } }),
              let i = all[wi].workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        var moved = all[wi].workouts.remove(at: i)
        let day = cal.startOfDay(for: date)
        moved.date = day
        let target = all.lastIndex { $0.startDate <= day } ?? 0
        all[target].workouts.append(moved)
        all[target].workouts.sort { $0.date < $1.date }
        weeks = all
    }

    /// Ersetzt alle Wochen ab `index` (1-basiert) durch die Wochen eines neu erzeugten Plans.
    /// Workouts der Woche `index`, die vor `date` liegen, bleiben erhalten.
    func replaceWeeks(from index: Int, with generated: [PlanWeek], keepingBefore date: Date) {
        let today = Calendar.current.startOfDay(for: date)
        let old = weeks
        var result = old.filter { $0.index < index }
        for var week in generated where week.index >= index {
            if week.index == index, let previous = old.first(where: { $0.index == index }) {
                week.workouts = previous.workouts.filter { $0.date < today } + week.workouts.filter { $0.date >= today }
            }
            result.append(week)
        }
        weeks = result
    }

    var weeks: [PlanWeek] {
        get { (try? JSONDecoder().decode([PlanWeek].self, from: weeksData)) ?? [] }
        set { weeksData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var completedIDs: Set<UUID> {
        get { (try? JSONDecoder().decode(Set<UUID>.self, from: completedData)) ?? [] }
        set { completedData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var goalPace: Double { goalTime / (goal.distance / 1000) }

    /// Ein Workout gilt als erledigt, wenn es manuell abgehakt wurde, ein Lauf damit verknüpft ist
    /// oder am selben Tag ein Lauf mit mindestens 60 % der geplanten Distanz existiert.
    func isCompleted(_ workout: PlannedWorkout, runs: [Run]) -> Bool {
        if completedIDs.contains(workout.id) { return true }
        return runs.contains { run in
            run.plannedWorkoutID == workout.id
                || (Calendar.current.isDate(run.startDate, inSameDayAs: workout.date)
                    && run.distance >= workout.distance * 0.6)
        }
    }

    func toggleCompleted(_ workout: PlannedWorkout) {
        var ids = completedIDs
        if ids.contains(workout.id) { ids.remove(workout.id) } else { ids.insert(workout.id) }
        completedIDs = ids
    }

    func workout(on date: Date) -> PlannedWorkout? {
        weeks.flatMap(\.workouts).first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func currentWeek(at date: Date = .now) -> PlanWeek? {
        weeks.last { $0.startDate <= date }
    }

    /// Nächstes offenes Workout ab heute.
    func nextWorkout(runs: [Run], from date: Date = .now) -> PlannedWorkout? {
        let today = Calendar.current.startOfDay(for: date)
        return weeks.flatMap(\.workouts).first {
            $0.date >= today && !isCompleted($0, runs: runs) && !isSkipped($0)
        }
    }
}

extension VDOT {
    /// Form aus den Läufen der letzten Wochen: bester VDOT aus den Bestleistungen ab 1 km.
    /// Trainingsläufe sind selten Maximalleistungen, der Wert ist also eher vorsichtig.
    static func estimate(from runs: [Run], weeks: Int = 6, now: Date = .now) -> Double? {
        let since = Calendar.current.date(byAdding: .day, value: -7 * weeks, to: now) ?? now
        let values = runs.filter { $0.startDate >= since }.flatMap { run in
            run.bestEfforts.filter { $0.key >= 1000 }.map { vdot(distance: Double($0.key), time: $0.value) }
        }
        return values.max()
    }
}
