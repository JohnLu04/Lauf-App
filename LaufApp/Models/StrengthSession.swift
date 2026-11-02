import Foundation
import SwiftData

/// Ein Satz im Krafttraining-Tagebuch.
struct StrengthSet: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Wiederholungen (bei Halteübungen 0)
    var reps: Int = 0
    /// Zusatzgewicht in kg (0 = Körpergewicht)
    var weight: Double = 0
    /// Haltezeit in Sekunden (nur bei Halteübungen)
    var seconds: Int = 0
    /// Wiederholungen in Reserve (wie viele noch möglich gewesen wären), nil = keine Angabe
    var reserve: Int?

    /// Geschätztes Maximalgewicht für eine Wiederholung (Epley-Formel)
    var estimatedOneRepMax: Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    var volume: Double { weight * Double(reps) }
}

/// Alle Sätze einer Übung in einer Einheit.
struct StrengthEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var sets: [StrengthSet]

    var exercise: StrengthExercise? { StrengthExercise.with(id: exerciseID) }
}

/// Eine Krafttrainingseinheit im Tagebuch.
@Model
final class StrengthSession {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Programm, aus dem die Einheit stammt ("" = freie Einheit)
    var programID: String = ""
    var notes: String = ""
    /// Anstrengung 0 = keine Angabe, sonst 1–10
    var effort: Int = 0
    /// Dauer in Minuten (0 = keine Angabe)
    var durationMinutes: Int = 0
    var entriesData: Data = Data()

    init(date: Date = .now, programID: String = "") {
        self.date = date
        self.programID = programID
    }

    var entries: [StrengthEntry] {
        get { (try? JSONDecoder().decode([StrengthEntry].self, from: entriesData)) ?? [] }
        set { entriesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var program: StrengthProgram? { StrengthProgram.with(id: programID) }

    var title: String { program?.name ?? "Krafttraining" }

    var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }

    /// Bewegte Last in kg (Gewicht × Wiederholungen)
    var totalVolume: Double { entries.flatMap(\.sets).reduce(0) { $0 + $1.volume } }
}
