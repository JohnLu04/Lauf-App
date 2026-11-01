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

struct PlannedWorkout: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var kind: WorkoutKind
    /// Gesamtdistanz inkl. Ein-/Auslaufen (Meter)
    var distance: Double
    var title: String
    var details: String
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

    init(goal: RaceGoal, raceDate: Date, goalTime: Double, startVDOT: Double, goalVDOT: Double,
         runsPerWeek: Int, weeks: [PlanWeek]) {
        self.goalRaw = goal.rawValue
        self.raceDate = raceDate
        self.goalTime = goalTime
        self.startVDOT = startVDOT
        self.goalVDOT = goalVDOT
        self.runsPerWeek = runsPerWeek
        self.weeks = weeks
    }

    var goal: RaceGoal { RaceGoal(rawValue: goalRaw) ?? .tenK }

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
}
