import Foundation

/// Eingaben für die Planerstellung.
struct PlanInput {
    var goal: RaceGoal
    var raceDate: Date
    /// Aktueller Wochenumfang in km
    var currentWeeklyKm: Double
    /// 3 bis 6 Läufe pro Woche
    var runsPerWeek: Int
    /// Aktuelle Form (aus einer Bestzeit berechnet)
    var currentVDOT: Double
    /// Zielzeit in Sekunden
    var goalTime: TimeInterval
    var today: Date = .now
}

struct GeneratedPlan {
    var weeks: [PlanWeek]
    var goalVDOT: Double
}

enum PlanGeneratorError: LocalizedError {
    case tooShort(available: Int, required: Int)

    var errorDescription: String? {
        switch self {
        case let .tooShort(available, required):
            "Bis zum Wettkampf bleiben nur \(available) Trainingswochen. Für dieses Ziel werden mindestens \(required) Wochen empfohlen. Wähle ein späteres Datum oder eine kürzere Distanz."
        }
    }
}

/// Erstellt periodisierte Trainingspläne nach bewährten Prinzipien:
/// - Paces nach Jack Daniels' VDOT-System (E, M, T, I, R)
/// - Phasen: Grundlage → Aufbau → wettkampfspezifisch → Tapering
/// - Umfang steigt höchstens ~10 % pro Woche, jede 4. Woche ist eine Entlastungswoche
/// - Schwellenumfang ≈ 10 %, Intervallumfang ≈ 8 %, R-Umfang ≈ 5 % des Wochenumfangs
/// - Langer Lauf ≈ 25–35 % des Wochenumfangs, gedeckelt je nach Zieldistanz
enum PlanGenerator {
    private enum Slot { case quality1, quality2, easy, long }

    /// Wochentage (0 = Montag) und Art der Einheit, je nach Anzahl Läufe pro Woche.
    private static func pattern(runs: Int) -> [(day: Int, slot: Slot)] {
        switch runs {
        case ...3: return [(1, .quality1), (3, .easy), (6, .long)]
        case 4: return [(1, .quality1), (2, .easy), (4, .quality2), (6, .long)]
        case 5: return [(1, .quality1), (2, .easy), (3, .quality2), (5, .easy), (6, .long)]
        default: return [(0, .easy), (1, .quality1), (2, .easy), (3, .quality2), (4, .easy), (6, .long)]
        }
    }

    private struct WeekContext {
        var index: Int
        var goal: RaceGoal
        var phase: TrainingPhase
        var isRecovery: Bool
        var volume: Double        // Meter
        var paces: TrainingPaces
        var goalPace: Double      // s/km
        var runs: Int
        var volumeKm: Double { volume / 1000 }
    }

    private struct Spec {
        var kind: WorkoutKind
        var title: String
        var details: String
        /// nil = Distanz eines lockeren Laufs verwenden
        var distance: Double?
    }

    // MARK: - Öffentliche API

    static func generate(_ input: PlanInput, calendar cal: Calendar = .mondayFirst) throws -> GeneratedPlan {
        let goal = input.goal
        let todayWeek = cal.startOfWeek(for: input.today)
        let weekday = cal.component(.weekday, from: input.today) // 2 = Montag, 3 = Dienstag
        var firstWeek = (weekday == 2 || weekday == 3)
            ? todayWeek
            : cal.date(byAdding: .weekOfYear, value: 1, to: todayWeek)!
        let raceWeekStart = cal.startOfWeek(for: input.raceDate)
        let days = cal.dateComponents([.day], from: firstWeek, to: raceWeekStart).day ?? 0
        var weekCount = Int((Double(days) / 7).rounded()) + 1

        if weekCount < goal.minWeeks {
            throw PlanGeneratorError.tooShort(available: max(0, weekCount), required: goal.minWeeks)
        }
        if weekCount > goal.maxWeeks {
            firstWeek = cal.date(byAdding: .weekOfYear, value: -(goal.maxWeeks - 1), to: raceWeekStart)!
            weekCount = goal.maxWeeks
        }

        let runs = min(6, max(3, input.runsPerWeek))
        let goalVDOT = VDOT.vdot(distance: goal.distance, time: input.goalTime)
        let goalPace = input.goalTime / (goal.distance / 1000)
        let volumes = weeklyVolumes(goal: goal, weekCount: weekCount,
                                    currentKm: input.currentWeeklyKm, runs: runs)
        let trainingWeeks = weekCount - goal.taperWeeks

        var weeks: [PlanWeek] = []
        for w in 0..<weekCount {
            let start = cal.date(byAdding: .weekOfYear, value: w, to: firstWeek)!
            let phase: TrainingPhase
            if w >= trainingWeeks {
                phase = .taper
            } else {
                let p = Double(w) / Double(trainingWeeks)
                phase = p < 0.3 ? .base : (p < 0.7 ? .build : .peak)
            }
            // Trainings-VDOT steigt langsam Richtung Ziel: höchstens +1 Punkt alle 4 Wochen.
            let progress = Double(w) / Double(max(1, weekCount - 1))
            let trainVDOT = min(input.currentVDOT + (goalVDOT - input.currentVDOT) * progress,
                                input.currentVDOT + Double(w) / 4)
            let ctx = WeekContext(index: w, goal: goal, phase: phase, isRecovery: volumes[w].recovery,
                                  volume: volumes[w].km * 1000,
                                  paces: VDOT.paces(vdot: max(input.currentVDOT, trainVDOT)),
                                  goalPace: goalPace, runs: runs)
            let workouts = w == weekCount - 1
                ? raceWeek(start: start, raceDate: input.raceDate, goalTime: input.goalTime, ctx: ctx, cal: cal)
                : regularWeek(start: start, ctx: ctx, cal: cal)
            weeks.append(PlanWeek(index: w + 1, startDate: start, phase: phase,
                                  isRecoveryWeek: volumes[w].recovery, workouts: workouts))
        }
        return GeneratedPlan(weeks: weeks, goalVDOT: goalVDOT)
    }

    // MARK: - Umfangsplanung

    static func weeklyVolumes(goal: RaceGoal, weekCount: Int, currentKm: Double, runs: Int)
        -> [(km: Double, recovery: Bool)]
    {
        let trainingWeeks = weekCount - goal.taperWeeks
        let startKm = max(currentKm, Double(runs) * 4)
        let typicalPeak = goal.typicalPeakKm * Double(runs) / 5
        let peakKm = min(max(typicalPeak, startKm), startKm * 1.6)

        var result: [(km: Double, recovery: Bool)] = []
        var lastBuildKm = startKm
        for i in 0..<trainingWeeks {
            let progress = trainingWeeks > 1 ? Double(i) / Double(trainingWeeks - 1) : 1
            let target = startKm + (peakKm - startKm) * min(1, progress / 0.85)
            let isRecovery = (i + 1) % 4 == 0 && i < trainingWeeks - 1
            if isRecovery {
                result.append((lastBuildKm * 0.8, true))
            } else {
                let km = i == 0 ? startKm : min(target, lastBuildKm * 1.1)
                lastBuildKm = km
                result.append((km, false))
            }
        }
        let taperFactors: [Double] = switch goal.taperWeeks {
        case 1: [0.6]
        case 2: [0.75, 0.55]
        default: [0.8, 0.65, 0.5]
        }
        for f in taperFactors { result.append((lastBuildKm * f, false)) }
        return result
    }

    // MARK: - Wochen

    private static func regularWeek(start: Date, ctx: WeekContext, cal: Calendar) -> [PlannedWorkout] {
        let pat = pattern(runs: ctx.runs)

        var q1 = quality1(ctx)
        var q2 = quality2(ctx)
        // Bei nur 3 Läufen wechseln sich die beiden Qualitätseinheiten wöchentlich ab.
        if ctx.runs <= 3, ctx.index % 2 == 1, let alternative = q2 { q1 = alternative }
        if ctx.runs <= 3 { q2 = nil }

        let longFraction = ctx.runs <= 3 ? 0.35 : (ctx.runs == 4 ? 0.30 : 0.27)
        let longDist = roundHalfKm(min(max(ctx.volume * longFraction, 6000), ctx.goal.longRunCap))

        // Wie viele Einheiten bekommen die Distanz eines lockeren Laufs?
        var easyCount = pat.filter { $0.slot == .easy }.count
        var qualityDist = 0.0
        if let d = q1.distance { qualityDist += d } else { easyCount += 1 }
        if pat.contains(where: { $0.slot == .quality2 }) {
            if let d = q2?.distance { qualityDist += d } else { easyCount += 1 }
        }

        let remaining = ctx.volume - longDist - qualityDist
        let easyDist = roundHalfKm(max(3000, remaining / Double(max(1, easyCount))))

        return pat.map { (day: Int, slot: Slot) -> PlannedWorkout in
            let date = cal.date(byAdding: .day, value: day, to: start)!
            let spec: Spec
            switch slot {
            case .quality1: spec = q1
            case .quality2: spec = q2 ?? easyRun(ctx)
            case .easy: spec = easyRun(ctx)
            case .long: spec = longRun(ctx, distance: longDist)
            }
            return PlannedWorkout(date: date, kind: spec.kind, distance: spec.distance ?? easyDist,
                                  title: spec.title, details: spec.details)
        }
    }

    private static func raceWeek(start: Date, raceDate: Date, goalTime: TimeInterval,
                                 ctx: WeekContext, cal: Calendar) -> [PlannedWorkout] {
        let raceDay = cal.startOfDay(for: raceDate)
        let raceOffset = min(6, max(0, cal.dateComponents([.day], from: start, to: raceDay).day ?? 6))
        // Einheiten vor dem Wettkampf; der Tag direkt davor ist Ruhetag.
        let preDays = pattern(runs: ctx.runs).map(\.day).filter { $0 < raceOffset - 1 }.suffix(ctx.runs - 1)
        let preDist = roundHalfKm(min(8000, max(3000, ctx.volume * 0.15)))

        var workouts: [PlannedWorkout] = preDays.enumerated().map { (i: Int, day: Int) -> PlannedWorkout in
            let date = cal.date(byAdding: .day, value: day, to: start)!
            if i == preDays.count - 1 {
                return PlannedWorkout(
                    date: date, kind: .strides, distance: preDist,
                    title: "Vorbelastung",
                    details: """
                    Locker laufen (\(easyRange(ctx.paces)) /km).
                    Darin 4 × 200 m im Wettkampftempo (\(Format.pace(ctx.goalPace)) /km), dazwischen locker traben.
                    Ziel: Beine wach machen, nicht ermüden.
                    """)
            }
            return PlannedWorkout(date: date, kind: .easy, distance: preDist,
                                  title: "Lockerer Lauf",
                                  details: "Kurz und locker (\(easyRange(ctx.paces)) /km). Frisch bleiben!")
        }

        workouts.append(PlannedWorkout(
            date: cal.date(byAdding: .day, value: raceOffset, to: start)!,
            kind: .race, distance: ctx.goal.distance,
            title: "Wettkampf: \(ctx.goal.name)",
            details: """
            Zielzeit: \(Format.duration(goalTime)) (\(Format.pace(ctx.goalPace)) /km)

            • Gut einlaufen: 10–15 min locker plus ein paar Steigerungen (bei HM/Marathon kürzer).
            • Die ersten Kilometer bewusst nicht schneller als Zielpace.
            • Gleichmäßig laufen, ab der zweiten Hälfte darfst du zulegen.
            Viel Erfolg!
            """))
        return workouts
    }

    // MARK: - Auswahl der Qualitätseinheiten

    private static func quality1(_ ctx: WeekContext) -> Spec {
        if ctx.isRecovery { return strides(ctx) }
        switch ctx.phase {
        case .base: return strides(ctx)
        case .build: return threshold(ctx)
        case .peak: return [.fiveK, .tenK].contains(ctx.goal) ? intervals(ctx) : threshold(ctx)
        case .taper: return racePace(ctx, short: true)
        }
    }

    private static func quality2(_ ctx: WeekContext) -> Spec? {
        if ctx.isRecovery { return nil }
        switch ctx.phase {
        case .base: return [.fiveK, .tenK].contains(ctx.goal) ? repetition(ctx) : nil
        case .build: return ctx.goal == .marathon ? racePace(ctx, short: false) : intervals(ctx)
        case .peak: return racePace(ctx, short: false)
        case .taper: return nil
        }
    }

    // MARK: - Bausteine

    private static func easyRange(_ p: TrainingPaces) -> String {
        "\(Format.pace(p.easyFast))–\(Format.pace(p.easySlow))"
    }

    private static func easyRun(_ ctx: WeekContext) -> Spec {
        Spec(kind: .easy, title: "Lockerer Lauf",
             details: "Entspannt im Gesprächstempo: \(easyRange(ctx.paces)) /km. Du solltest dich dabei problemlos unterhalten können.",
             distance: nil)
    }

    private static func strides(_ ctx: WeekContext) -> Spec {
        Spec(kind: .strides, title: "Locker + Steigerungen",
             details: """
             Locker laufen: \(easyRange(ctx.paces)) /km.
             Zum Schluss 6 × 20 s Steigerungsläufe: locker beschleunigen bis etwa \(Format.pace(ctx.paces.repetition)) /km, dazwischen 40 s gehen oder traben.
             """,
             distance: nil)
    }

    private static func longRun(_ ctx: WeekContext, distance: Double) -> Spec {
        let km = distance / 1000
        var details = "Gleichmäßig locker: \(easyRange(ctx.paces)) /km. Ausdauer zählt hier, nicht Tempo."
        if ctx.phase == .peak, !ctx.isRecovery, [.half, .marathon].contains(ctx.goal) {
            let fast = min((km * 0.3).rounded(), ctx.goal == .marathon ? 12 : 6)
            details = """
            Die ersten \(Int(km - fast)) km locker (\(easyRange(ctx.paces)) /km),
            die letzten \(Int(fast)) km im Zieltempo (\(Format.pace(ctx.goalPace)) /km).
            Ideal, um Verpflegung und Ausrüstung für den Wettkampf zu testen.
            """
        }
        return Spec(kind: .long, title: "Langer Lauf", details: details, distance: distance)
    }

    private static func threshold(_ ctx: WeekContext) -> Spec {
        let tKm = min(10, max(3, (ctx.volumeKm * 0.10).rounded()))
        let t = Format.pace(ctx.paces.threshold)
        if tKm <= 5 {
            return Spec(kind: .threshold, title: "Tempodauerlauf",
                        details: """
                        2 km einlaufen (locker)
                        \(Int(tKm)) km zügig an der Schwelle: \(t) /km
                        2 km auslaufen (locker)

                        "Angenehm hart": Du könntest nur noch einzelne Wörter sprechen.
                        """,
                        distance: (tKm + 4) * 1000)
        }
        let n = Int((tKm / 2).rounded())
        return Spec(kind: .threshold, title: "Schwellenintervalle",
                    details: """
                    2 km einlaufen (locker)
                    \(n) × 2 km @ \(t) /km, je 1 min Trabpause
                    2 km auslaufen (locker)
                    """,
                    distance: Double(n) * 2000 + 4000 + Double(n) * 200)
    }

    private static func intervals(_ ctx: WeekContext) -> Spec {
        let iKm = min(8, max(3, ctx.volumeKm * 0.08))
        let rep = iKm >= 5 ? 1000.0 : 800.0
        let n = max(3, Int((iKm * 1000 / rep).rounded()))
        let repTime = ctx.paces.interval * rep / 1000
        return Spec(kind: .intervals, title: "VO2max-Intervalle",
                    details: """
                    2 km einlaufen (locker) + 4 Steigerungen
                    \(n) × \(Int(rep)) m @ \(Format.pace(ctx.paces.interval)) /km (≈ \(Format.duration(repTime)) pro Wiederholung)
                    Trabpause: 2–3 min (etwa so lang wie die Belastung)
                    2 km auslaufen (locker)
                    """,
                    distance: 4000 + Double(n) * rep + Double(n) * 400)
    }

    private static func repetition(_ ctx: WeekContext) -> Spec {
        let rKm = min(5, max(2, ctx.volumeKm * 0.05))
        let rep = rKm >= 3 ? 400.0 : 200.0
        let n = Int(rKm * 1000 / rep)
        let repTime = ctx.paces.repetition * rep / 1000
        return Spec(kind: .repetition, title: "Tempowiederholungen",
                    details: """
                    2 km einlaufen (locker)
                    \(n) × \(Int(rep)) m @ \(Format.pace(ctx.paces.repetition)) /km (≈ \(Int(repTime.rounded())) s)
                    Pause: \(Int(rep)) m locker traben – vollständig erholen
                    2 km auslaufen (locker)

                    Fokus auf saubere, lockere Technik, nicht auf Kampf.
                    """,
                    distance: 4000 + Double(n) * rep * 2)
    }

    private static func racePace(_ ctx: WeekContext, short: Bool) -> Spec {
        let gp = Format.pace(ctx.goalPace)
        let title = short ? "Tempo-Schärfung" : "Wettkampftempo"
        let reps: Int, repDist: Double, pause: String
        switch ctx.goal {
        case .fiveK:
            reps = short ? 3 : 5; repDist = 1000; pause = "2 min Trabpause"
        case .tenK:
            reps = short ? 3 : 4; repDist = short ? 1000 : 2000; pause = "2 min Trabpause"
        case .half:
            reps = short ? 2 : 3; repDist = (short || ctx.volumeKm < 45) ? 3000 : 5000; pause = "3 min Trabpause"
        case .marathon:
            let mKm = short ? 6 : min(16, max(8, (ctx.volumeKm * 0.2).rounded()))
            return Spec(kind: .racePace, title: title,
                        details: """
                        2 km einlaufen (locker)
                        \(Int(mKm)) km am Stück im Marathontempo: \(gp) /km
                        2 km auslaufen (locker)
                        """,
                        distance: (mKm + 4) * 1000)
        }
        let repText = repDist >= 1000 ? "\(Format.kilometers(repDist, decimals: 0)) km" : "\(Int(repDist)) m"
        return Spec(kind: .racePace, title: title,
                    details: """
                    2 km einlaufen (locker) + 4 Steigerungen
                    \(reps) × \(repText) im Zieltempo: \(gp) /km, \(pause)
                    2 km auslaufen (locker)
                    """,
                    distance: 4000 + Double(reps) * repDist + Double(reps) * 400)
    }

    private static func roundHalfKm(_ meters: Double) -> Double {
        (meters / 500).rounded() * 500
    }
}
