import Foundation

/// Eingaben für die Planerstellung.
struct PlanInput {
    var goal: RaceGoal
    var raceDate: Date
    /// Aktueller Wochenumfang in km
    var currentWeeklyKm: Double
    /// Gewünschter Wochenumfang in km (in den umfangreichsten Wochen)
    var targetWeeklyKm: Double
    /// 2 bis 6 Läufe pro Woche
    var runsPerWeek: Int
    /// Tage, an denen trainiert werden kann (0 = Montag … 6 = Sonntag)
    var trainingDays: Set<Int> = Set(0...6)
    /// Tag des langen Laufs (0 = Montag … 6 = Sonntag)
    var longRunDay: Int = 6
    /// Aktuelle Form (aus einer Bestzeit berechnet)
    var currentVDOT: Double
    /// Zielzeit in Sekunden
    var goalTime: TimeInterval
    /// Beginn der Planung; beim Anpassen eines Plans der Start des ursprünglichen Plans
    var today: Date = .now
    /// Ab dieser Woche (0-basiert) gilt `currentVDOT` – wichtig beim Anpassen eines laufenden Plans
    var formWeekIndex: Int = 0
}

struct GeneratedPlan {
    var weeks: [PlanWeek]
    var goalVDOT: Double
}

enum PlanGeneratorError: LocalizedError {
    case tooShort(available: Int, required: Int)
    case notEnoughDays(available: Int, required: Int)

    var errorDescription: String? {
        switch self {
        case let .tooShort(available, required):
            "Bis zum Wettkampf bleiben nur \(available) Trainingswochen. Für dieses Ziel werden mindestens \(required) Wochen empfohlen. Wähle ein späteres Datum oder eine kürzere Distanz."
        case let .notEnoughDays(available, required):
            "Du hast \(available) Trainingstage ausgewählt, möchtest aber \(required)-mal pro Woche laufen. Wähle mehr Tage oder weniger Läufe."
        }
    }
}

/// Erstellt periodisierte Trainingspläne nach bewährten Prinzipien:
/// - Paces nach Jack Daniels' VDOT-System (E, M, T, I, R)
/// - Phasen: Grundlage → Aufbau → wettkampfspezifisch → Tapering
/// - Umfang steigt höchstens ~10 % pro Woche bis zum gewünschten Wochenumfang, jede 4. Woche ist eine Entlastungswoche
/// - Schwellenumfang ≈ 10 %, Intervallumfang ≈ 8 %, R-Umfang ≈ 5 % des Wochenumfangs
/// - Langer Lauf steigt gleichmäßig bis zur zieltypischen Spitzenlänge (5 km: 10 km … Marathon: 32 km),
///   soweit der Wochenumfang das zulässt, und ist immer der längste Lauf der Woche
/// - Einheiten liegen auf den gewählten Trainingstagen, harte Einheiten möglichst nicht an aufeinanderfolgenden Tagen
enum PlanGenerator {
    enum Slot { case quality1, quality2, easy, long }

    private struct WeekContext {
        var index: Int
        var goal: RaceGoal
        var phase: TrainingPhase
        var isRecovery: Bool
        var volume: Double        // Meter
        var longRun: Double       // Meter
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
        /// Strukturierter Ablauf für die tatsächliche Gesamtdistanz
        var steps: (Double) -> [WorkoutStep]
    }

    // MARK: - Öffentliche API

    static func generate(_ input: PlanInput, calendar cal: Calendar = .mondayFirst) throws -> GeneratedPlan {
        let goal = input.goal
        let span = weekSpan(input, calendar: cal)
        if span.available < goal.minWeeks {
            throw PlanGeneratorError.tooShort(available: max(0, span.available), required: goal.minWeeks)
        }
        let days = input.trainingDays.isEmpty ? Set(0...6) : input.trainingDays
        let runs = clampedRuns(input)
        if days.count < runs {
            throw PlanGeneratorError.notEnoughDays(available: days.count, required: runs)
        }
        let weekCount = span.count
        let trainingWeeks = weekCount - goal.taperWeeks
        let pattern = schedule(runs: runs, days: days, longDay: input.longRunDay)

        let goalVDOT = VDOT.vdot(distance: goal.distance, time: input.goalTime)
        let goalPace = input.goalTime / (goal.distance / 1000)
        let start = startKm(input, runs: runs)
        let peak = peakKm(input, runs: runs, trainingWeeks: trainingWeeks)
        let volumes = weeklyVolumes(goal: goal, weekCount: weekCount, startKm: start, peakKm: peak)
        let longRuns = longRunDistances(goal: goal, volumes: volumes, runs: runs,
                                        peakLong: longRunPeak(goal: goal, peakKm: peak, runs: runs))

        var weeks: [PlanWeek] = []
        for w in 0..<weekCount {
            let weekStart = cal.date(byAdding: .weekOfYear, value: w, to: span.firstWeek)!
            let phase: TrainingPhase
            if w >= trainingWeeks {
                phase = .taper
            } else {
                let p = Double(w) / Double(trainingWeeks)
                phase = p < 0.3 ? .base : (p < 0.7 ? .build : .peak)
            }
            // Trainings-VDOT steigt langsam Richtung Ziel: höchstens +1 Punkt alle 4 Wochen.
            let sinceForm = max(0, w - input.formWeekIndex)
            let progress = Double(sinceForm) / Double(max(1, weekCount - 1 - input.formWeekIndex))
            let trainVDOT = min(input.currentVDOT + (goalVDOT - input.currentVDOT) * progress,
                                input.currentVDOT + Double(sinceForm) / 4)
            // Der Wochenumfang muss groß genug sein, dass der lange Lauf nicht zu viel davon ausmacht.
            let volume = max(volumes[w].km * 1000, longRuns[w] / maxLongShare(runs: runs, goal: goal))
            let ctx = WeekContext(index: w, goal: goal, phase: phase, isRecovery: volumes[w].recovery,
                                  volume: volume, longRun: longRuns[w],
                                  paces: VDOT.paces(vdot: max(input.currentVDOT, trainVDOT)),
                                  goalPace: goalPace, runs: runs)
            let workouts = w == weekCount - 1
                ? raceWeek(start: weekStart, raceDate: input.raceDate, goalTime: input.goalTime,
                           pattern: pattern, ctx: ctx, cal: cal)
                : regularWeek(start: weekStart, pattern: pattern, ctx: ctx, cal: cal)
            weeks.append(PlanWeek(index: w + 1, startDate: weekStart, phase: phase,
                                  isRecoveryWeek: volumes[w].recovery, workouts: workouts))
        }
        return GeneratedPlan(weeks: weeks, goalVDOT: goalVDOT)
    }

    /// Hinweise, wenn die Eingaben das Ziel gefährden (z. B. zu wenig Kilometer pro Woche).
    static func warnings(for input: PlanInput, calendar cal: Calendar = .mondayFirst) -> [String] {
        let goal = input.goal
        let span = weekSpan(input, calendar: cal)
        guard span.available >= goal.minWeeks else { return [] }
        let runs = clampedRuns(input)
        let trainingWeeks = span.count - goal.taperWeeks
        let start = startKm(input, runs: runs)
        let peak = peakKm(input, runs: runs, trainingWeeks: trainingWeeks)
        let longPeak = longRunPeak(goal: goal, peakKm: peak, runs: runs)

        var result: [String] = []
        if input.targetWeeklyKm < goal.recommendedMinWeeklyKm {
            result.append("Für \(goal.name) empfehlen wir mindestens \(Int(goal.recommendedMinWeeklyKm)) km pro Woche. Mit \(Int(input.targetWeeklyKm)) km wird es schwer, dein Ziel zu erreichen.")
        }
        if peak + 0.5 < input.targetWeeklyKm {
            result.append("Von aktuell \(Int(start)) km lässt sich der Umfang in \(trainingWeeks) Trainingswochen nur auf etwa \(Int(peak.rounded())) km pro Woche steigern, ohne das Verletzungsrisiko stark zu erhöhen. Der Plan geht deshalb nicht höher.")
        }
        // Läufe pro Woche reichen nicht, um den Umfang tatsächlich zu laufen?
        if let plan = try? generate(input, calendar: cal) {
            let maxVolume = plan.weeks.dropLast().map(\.volume).max() ?? 0
            if maxVolume / 1000 < min(peak, input.targetWeeklyKm) * 0.9 {
                result.append("Mit \(runs) Läufen pro Woche kommst du auf höchstens ca. \(Format.kilometers(maxVolume, decimals: 0)) km pro Woche. Für \(Int(input.targetWeeklyKm)) km plane mehr Läufe ein.")
            }
        }
        if longPeak < goal.longRunPeak - 999 {
            result.append("Dein längster Lauf wird nur ca. \(Format.kilometers(longPeak, decimals: 0)) km lang (empfohlen: \(Format.kilometers(goal.longRunPeak, decimals: 0)) km). Mehr Kilometer oder mehr Läufe pro Woche würden helfen.")
        }
        return result
    }

    // MARK: - Planlänge und Umfang

    private static func clampedRuns(_ input: PlanInput) -> Int { min(6, max(2, input.runsPerWeek)) }

    /// Erste Planwoche, Anzahl der Wochen (höchstens `maxWeeks`) und verfügbare Wochen bis zum Wettkampf.
    static func weekSpan(_ input: PlanInput, calendar cal: Calendar = .mondayFirst)
        -> (firstWeek: Date, count: Int, available: Int)
    {
        let goal = input.goal
        let todayWeek = cal.startOfWeek(for: input.today)
        let weekday = cal.weekdayIndex(of: input.today) // 0 = Montag, 1 = Dienstag
        var firstWeek = weekday <= 1 ? todayWeek : cal.date(byAdding: .weekOfYear, value: 1, to: todayWeek)!
        let raceWeekStart = cal.startOfWeek(for: input.raceDate)
        let days = cal.dateComponents([.day], from: firstWeek, to: raceWeekStart).day ?? 0
        let available = Int((Double(days) / 7).rounded()) + 1
        var count = available
        if count > goal.maxWeeks {
            firstWeek = cal.date(byAdding: .weekOfYear, value: -(goal.maxWeeks - 1), to: raceWeekStart)!
            count = goal.maxWeeks
        }
        return (firstWeek, count, available)
    }

    /// Startumfang: aktueller Umfang, höchstens der gewünschte, mindestens 3 km pro Lauf.
    private static func startKm(_ input: PlanInput, runs: Int) -> Double {
        max(min(input.currentWeeklyKm, input.targetWeeklyKm), Double(runs) * 3)
    }

    /// Spitzenumfang: der gewünschte Umfang, soweit er sich sicher erreichen lässt
    /// (bei 10 % pro Woche abzüglich Entlastungswochen, höchstens das Doppelte).
    private static func peakKm(_ input: PlanInput, runs: Int, trainingWeeks: Int) -> Double {
        let start = startKm(input, runs: runs)
        let maxGrowth = min(2.0, 1 + 0.08 * Double(trainingWeeks))
        return max(start, min(input.targetWeeklyKm, start * maxGrowth))
    }

    static func weeklyVolumes(goal: RaceGoal, weekCount: Int, startKm: Double, peakKm: Double)
        -> [(km: Double, recovery: Bool)]
    {
        let trainingWeeks = weekCount - goal.taperWeeks
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

    /// Höchster Anteil des langen Laufs am Wochenumfang.
    private static func maxLongShare(runs: Int, goal: RaceGoal) -> Double {
        let share: Double = switch runs {
        case ...2: 0.60
        case 3: 0.50
        case 4: 0.45
        case 5: 0.40
        default: 0.35
        }
        return goal == .marathon ? share + 0.05 : share
    }

    /// Spitzenlänge des langen Laufs: zieltypisch, aber nicht mehr, als der Wochenumfang hergibt.
    private static func longRunPeak(goal: RaceGoal, peakKm: Double, runs: Int) -> Double {
        let byVolume = (peakKm * 1000 * maxLongShare(runs: runs, goal: goal) / 500).rounded(.down) * 500
        return max(5000, min(goal.longRunPeak, byVolume))
    }

    /// Länge des langen Laufs pro Woche (Meter). Sie steigt in den Aufbauwochen gleichmäßig
    /// vom aktuellen Niveau bis `peakLong`, höchstens um `longRunStep` pro Woche.
    /// Entlastungswochen ≈ 70 %, im Tapering wird schrittweise reduziert.
    /// Die Wettkampfwoche hat keinen langen Lauf (0).
    static func longRunDistances(goal: RaceGoal, volumes: [(km: Double, recovery: Bool)], runs: Int,
                                 peakLong: Double) -> [Double] {
        let weekCount = volumes.count
        let trainingWeeks = weekCount - goal.taperWeeks
        let startShare = runs <= 3 ? 0.35 : (runs == 4 ? 0.30 : 0.27)
        let start = roundHalfKm(min(max(volumes[0].km * 1000 * startShare, 5000), peakLong))
        let buildWeeks = (0..<trainingWeeks).filter { !volumes[$0].recovery }

        var result = [Double](repeating: 0, count: weekCount)
        var last = start
        var buildIndex = 0
        for i in 0..<trainingWeeks {
            if volumes[i].recovery {
                result[i] = max(5000, roundHalfKm(last * 0.7))
                continue
            }
            let progress = buildWeeks.count > 1 ? Double(buildIndex) / Double(buildWeeks.count - 1) : 1
            let target = start + (peakLong - start) * progress
            last = buildIndex == 0 ? start : roundHalfKm(min(target, last + goal.longRunStep))
            result[i] = last
            buildIndex += 1
        }
        // Tapering (ohne Wettkampfwoche): 75 %, dann 55 % der zuletzt gelaufenen Länge
        let taperFactors: [Double] = [0.75, 0.55]
        for (j, f) in taperFactors.prefix(goal.taperWeeks - 1).enumerated() {
            result[trainingWeeks + j] = max(5000, roundHalfKm(last * f))
        }
        return result
    }

    // MARK: - Wochenaufteilung

    /// Verteilt die Läufe auf die gewählten Tage: langer Lauf am Wunschtag, die übrigen Läufe
    /// möglichst gleichmäßig verteilt, harte Einheiten mit mindestens einem Tag Abstand zueinander
    /// und zum langen Lauf, wenn die Tage das zulassen.
    static func schedule(runs: Int, days: Set<Int>, longDay: Int) -> [(day: Int, slot: Slot)] {
        var available = days.isEmpty ? Set(0...6) : days
        let long = available.contains(longDay) ? longDay : (available.max() ?? 6)
        available.remove(long)
        let others = min(max(0, runs - 1), available.count)

        func circular(_ a: Int, _ b: Int) -> Int { min(abs(a - b), 7 - abs(a - b)) }
        func gaps(_ chosen: [Int]) -> [Int] {
            let all = (chosen + [long]).sorted()
            return zip(all, all.dropFirst() + [all[0] + 7]).map { $1 - $0 }
        }
        // Gleichmäßigste Auswahl: größter kleinster Abstand, dann geringste Streuung
        let chosen = combinations(available.sorted(), others).min { a, b in
            let ga = gaps(a), gb = gaps(b)
            if ga.min()! != gb.min()! { return ga.min()! > gb.min()! }
            return ga.map { $0 * $0 }.reduce(0, +) < gb.map { $0 * $0 }.reduce(0, +)
        } ?? []

        // Harte Einheiten: bei 2–3 Läufen eine, ab 4 Läufen zwei
        let qualityCount = min(chosen.count, runs >= 4 ? 2 : 1)
        let quality = combinations(chosen, qualityCount).min { a, b in
            func score(_ q: [Int]) -> (Int, Int) {
                let points = q + [long]
                var minDist = 7, sum = 0
                for i in points.indices { for j in points.indices where j > i {
                    minDist = min(minDist, circular(points[i], points[j])); sum += circular(points[i], points[j])
                } }
                return (minDist, sum)
            }
            let sa = score(a), sb = score(b)
            if sa.0 != sb.0 { return sa.0 > sb.0 }
            if sa.1 != sb.1 { return sa.1 > sb.1 }
            return a.lexicographicallyPrecedes(b)
        } ?? []

        var result: [(day: Int, slot: Slot)] = chosen.map { day in
            if let i = quality.sorted().firstIndex(of: day) { return (day, i == 0 ? .quality1 : .quality2) }
            return (day, .easy)
        }
        result.append((long, .long))
        return result.sorted { $0.day < $1.day }
    }

    private static func combinations(_ items: [Int], _ k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var result: [[Int]] = []
        for (i, item) in items.enumerated() {
            for rest in combinations(Array(items[(i + 1)...]), k - 1) { result.append([item] + rest) }
        }
        return result
    }

    // MARK: - Wochen

    private static func regularWeek(start: Date, pattern pat: [(day: Int, slot: Slot)],
                                    ctx: WeekContext, cal: Calendar) -> [PlannedWorkout] {
        var q1 = quality1(ctx)
        var q2 = quality2(ctx)
        let hasQuality2 = pat.contains { $0.slot == .quality2 }
        // Mit nur einer harten Einheit pro Woche wechseln sich die beiden Qualitätseinheiten wöchentlich ab.
        if !hasQuality2, ctx.index % 2 == 1, let alternative = q2 { q1 = alternative }
        if !hasQuality2 { q2 = nil }

        let longDist = ctx.longRun

        // Wie viele Einheiten bekommen die Distanz eines lockeren Laufs?
        var easyCount = pat.filter { $0.slot == .easy }.count
        var qualityDist = 0.0
        if pat.contains(where: { $0.slot == .quality1 }) {
            if let d = q1.distance { qualityDist += d } else { easyCount += 1 }
        }
        if hasQuality2 {
            if let d = q2?.distance { qualityDist += d } else { easyCount += 1 }
        }

        let remaining = ctx.volume - longDist - qualityDist
        // Lockere Läufe liegen bei 40 % (ab 5 Läufen 25 %) bis 75 % des langen Laufs. Die Untergrenze
        // gilt nur, solange der Wochenumfang dadurch um höchstens 5 % überschritten wird.
        let easyCap = (longDist * 0.75 / 500).rounded(.down) * 500
        let allowedEasy = (ctx.volume * 1.05 - longDist - qualityDist) / Double(max(1, easyCount))
        let easyFloor = max(3000, min(roundHalfKm(longDist * (ctx.runs >= 5 ? 0.25 : 0.4)),
                                      (allowedEasy / 500).rounded(.down) * 500))
        let easyDist = min(roundHalfKm(max(easyFloor, remaining / Double(max(1, easyCount)))), max(easyFloor, easyCap))

        return pat.map { (day: Int, slot: Slot) -> PlannedWorkout in
            let date = cal.date(byAdding: .day, value: day, to: start)!
            let spec: Spec
            switch slot {
            case .quality1: spec = q1
            case .quality2: spec = q2 ?? easyRun(ctx)
            case .easy: spec = easyRun(ctx)
            case .long: spec = longRun(ctx, distance: longDist)
            }
            let distance = spec.distance ?? easyDist
            return PlannedWorkout(date: date, kind: spec.kind, distance: distance,
                                  title: spec.title, details: spec.details, steps: spec.steps(distance))
        }
    }

    private static func raceWeek(start: Date, raceDate: Date, goalTime: TimeInterval,
                                 pattern: [(day: Int, slot: Slot)], ctx: WeekContext, cal: Calendar) -> [PlannedWorkout] {
        let raceDay = cal.startOfDay(for: raceDate)
        let raceOffset = min(6, max(0, cal.dateComponents([.day], from: start, to: raceDay).day ?? 6))
        // Einheiten vor dem Wettkampf; der Tag direkt davor ist Ruhetag.
        let preDays = pattern.map(\.day).filter { $0 < raceOffset - 1 }.suffix(ctx.runs - 1)
        let preDist = roundHalfKm(min(8000, max(3000, ctx.volume * 0.15)))
        let easy = easyPace(ctx)

        var workouts: [PlannedWorkout] = preDays.enumerated().map { (i: Int, day: Int) -> PlannedWorkout in
            let date = cal.date(byAdding: .day, value: day, to: start)!
            if i == preDays.count - 1 {
                var steps = [WorkoutStep(kind: .run, label: "Locker laufen", distance: max(1000, preDist - 1600),
                                         paceFast: easy.fast, paceSlow: easy.slow)]
                for n in 1...4 {
                    let gp = paceRange(ctx.goalPace, tolerance: 0.02)
                    steps.append(WorkoutStep(kind: .run, label: "Wettkampftempo \(n) von 4", distance: 200,
                                             paceFast: gp.fast, paceSlow: gp.slow))
                    steps.append(WorkoutStep(kind: .recovery, label: "Locker traben", distance: 200))
                }
                return PlannedWorkout(
                    date: date, kind: .strides, distance: preDist,
                    title: "Vorbelastung",
                    details: """
                    Locker laufen (\(easyRange(ctx.paces)) /km).
                    Darin 4 × 200 m im Wettkampftempo (\(Format.pace(ctx.goalPace)) /km), dazwischen locker traben.
                    Ziel: Beine wach machen, nicht ermüden.
                    """,
                    steps: steps)
            }
            return PlannedWorkout(date: date, kind: .easy, distance: preDist,
                                  title: "Lockerer Lauf",
                                  details: "Kurz und locker (\(easyRange(ctx.paces)) /km). Frisch bleiben!",
                                  steps: [WorkoutStep(kind: .run, label: "Locker laufen", distance: preDist,
                                                      paceFast: easy.fast, paceSlow: easy.slow)])
        }

        let gp = paceRange(ctx.goalPace, tolerance: 0.02)
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
            """,
            steps: [WorkoutStep(kind: .run, label: "Wettkampf", distance: ctx.goal.distance,
                                paceFast: gp.fast, paceSlow: gp.slow)]))
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

    /// Tempoeinheiten (inkl. Ein- und Auslaufen) bleiben kürzer als der lange Lauf.
    private static func qualityLimit(_ ctx: WeekContext) -> Double {
        max(6000, ctx.longRun - 1000)
    }

    private static func easyRange(_ p: TrainingPaces) -> String {
        "\(Format.pace(p.easyFast))–\(Format.pace(p.easySlow))"
    }

    private static func easyPace(_ ctx: WeekContext) -> (fast: Double, slow: Double) {
        (ctx.paces.easyFast, ctx.paces.easySlow)
    }

    private static func paceRange(_ pace: Double, tolerance: Double = 0.03) -> (fast: Double, slow: Double) {
        (pace * (1 - tolerance), pace * (1 + tolerance))
    }

    private static func warmup(_ ctx: WeekContext, _ meters: Double = 2000) -> WorkoutStep {
        let e = easyPace(ctx)
        return WorkoutStep(kind: .warmup, label: "Einlaufen", distance: meters, paceFast: e.fast, paceSlow: e.slow)
    }

    private static func cooldown(_ ctx: WeekContext, _ meters: Double = 2000) -> WorkoutStep {
        let e = easyPace(ctx)
        return WorkoutStep(kind: .cooldown, label: "Auslaufen", distance: meters, paceFast: e.fast, paceSlow: e.slow)
    }

    /// Wiederholungen mit Pausen, z.B. 5 × 1000 m mit je 2 min Trabpause.
    private static func reps(_ n: Int, label: String, distance: Double, pace: (fast: Double, slow: Double),
                             recoveryDistance: Double? = nil, recoveryDuration: TimeInterval? = nil) -> [WorkoutStep] {
        (1...max(1, n)).flatMap { i -> [WorkoutStep] in
            var steps = [WorkoutStep(kind: .run, label: "\(label) \(i) von \(n)", distance: distance,
                                     paceFast: pace.fast, paceSlow: pace.slow)]
            if i < n {
                steps.append(WorkoutStep(kind: .recovery, label: "Trabpause", distance: recoveryDistance,
                                         duration: recoveryDistance == nil ? recoveryDuration : nil))
            }
            return steps
        }
    }

    private static func easyRun(_ ctx: WeekContext) -> Spec {
        let e = easyPace(ctx)
        return Spec(kind: .easy, title: "Lockerer Lauf",
                    details: "Entspannt im Gesprächstempo: \(easyRange(ctx.paces)) /km. Du solltest dich dabei problemlos unterhalten können.",
                    distance: nil,
                    steps: { d in [WorkoutStep(kind: .run, label: "Locker laufen", distance: d,
                                               paceFast: e.fast, paceSlow: e.slow)] })
    }

    private static func strides(_ ctx: WeekContext) -> Spec {
        let e = easyPace(ctx)
        return Spec(kind: .strides, title: "Locker + Steigerungen",
                    details: """
                    Locker laufen: \(easyRange(ctx.paces)) /km.
                    Zum Schluss 6 × 20 s Steigerungsläufe: locker beschleunigen bis etwa \(Format.pace(ctx.paces.repetition)) /km, dazwischen 40 s gehen oder traben.
                    """,
                    distance: nil,
                    steps: { d in
                        var steps = [WorkoutStep(kind: .run, label: "Locker laufen", distance: max(1000, d - 1200),
                                                 paceFast: e.fast, paceSlow: e.slow)]
                        for i in 1...6 {
                            steps.append(WorkoutStep(kind: .run, label: "Steigerung \(i) von 6", duration: 20))
                            steps.append(WorkoutStep(kind: .recovery, label: "Gehen oder traben", duration: 40))
                        }
                        return steps
                    })
    }

    private static func longRun(_ ctx: WeekContext, distance: Double) -> Spec {
        let km = distance / 1000
        let e = easyPace(ctx)
        var details = "Gleichmäßig locker: \(easyRange(ctx.paces)) /km. Ausdauer zählt hier, nicht Tempo."
        var steps = [WorkoutStep(kind: .run, label: "Langer Lauf", distance: distance, paceFast: e.fast, paceSlow: e.slow)]
        if ctx.phase == .peak, !ctx.isRecovery, [.half, .marathon].contains(ctx.goal) {
            let fast = min((km * 0.3).rounded(), ctx.goal == .marathon ? 12 : 6)
            let gp = paceRange(ctx.goalPace, tolerance: 0.02)
            details = """
            Die ersten \(Int(km - fast)) km locker (\(easyRange(ctx.paces)) /km),
            die letzten \(Int(fast)) km im Zieltempo (\(Format.pace(ctx.goalPace)) /km).
            Ideal, um Verpflegung und Ausrüstung für den Wettkampf zu testen.
            """
            steps = [
                WorkoutStep(kind: .run, label: "Locker laufen", distance: distance - fast * 1000,
                            paceFast: e.fast, paceSlow: e.slow),
                WorkoutStep(kind: .run, label: "Zieltempo", distance: fast * 1000, paceFast: gp.fast, paceSlow: gp.slow),
            ]
        }
        return Spec(kind: .long, title: "Langer Lauf", details: details, distance: distance, steps: { _ in steps })
    }

    private static func threshold(_ ctx: WeekContext) -> Spec {
        let limitKm = qualityLimit(ctx) / 1000
        let tKm = min(10, max(3, (ctx.volumeKm * 0.10).rounded()), max(2, (limitKm - 4).rounded(.down)))
        let t = Format.pace(ctx.paces.threshold)
        let tp = paceRange(ctx.paces.threshold)
        if tKm <= 5 {
            return Spec(kind: .threshold, title: "Tempodauerlauf",
                        details: """
                        2 km einlaufen (locker)
                        \(Int(tKm)) km zügig an der Schwelle: \(t) /km
                        2 km auslaufen (locker)

                        "Angenehm hart": Du könntest nur noch einzelne Wörter sprechen.
                        """,
                        distance: (tKm + 4) * 1000,
                        steps: { _ in [
                            warmup(ctx),
                            WorkoutStep(kind: .run, label: "Tempodauerlauf", distance: tKm * 1000,
                                        paceFast: tp.fast, paceSlow: tp.slow),
                            cooldown(ctx),
                        ] })
        }
        let n = min(Int((tKm / 2).rounded()), Int((limitKm - 4) / 2.2))
        return Spec(kind: .threshold, title: "Schwellenintervalle",
                    details: """
                    2 km einlaufen (locker)
                    \(n) × 2 km @ \(t) /km, je 1 min Trabpause
                    2 km auslaufen (locker)
                    """,
                    distance: Double(n) * 2000 + 4000 + Double(n) * 200,
                    steps: { _ in
                        [warmup(ctx)] + reps(n, label: "Schwelle", distance: 2000, pace: tp, recoveryDuration: 60)
                            + [cooldown(ctx)]
                    })
    }

    private static func intervals(_ ctx: WeekContext) -> Spec {
        let iKm = min(8, max(3, ctx.volumeKm * 0.08))
        let rep = iKm >= 5 ? 1000.0 : 800.0
        let n = max(3, min(Int((iKm * 1000 / rep).rounded()),
                           Int((qualityLimit(ctx) - 4000) / (rep + 400))))
        let repTime = ctx.paces.interval * rep / 1000
        return Spec(kind: .intervals, title: "VO2max-Intervalle",
                    details: """
                    2 km einlaufen (locker) + 4 Steigerungen
                    \(n) × \(Int(rep)) m @ \(Format.pace(ctx.paces.interval)) /km (≈ \(Format.duration(repTime)) pro Wiederholung)
                    Trabpause: 2–3 min (etwa so lang wie die Belastung)
                    2 km auslaufen (locker)
                    """,
                    distance: 4000 + Double(n) * rep + Double(n) * 400,
                    steps: { _ in
                        [warmup(ctx)]
                            + reps(n, label: "Intervall", distance: rep, pace: paceRange(ctx.paces.interval),
                                   recoveryDuration: min(180, max(120, repTime)))
                            + [cooldown(ctx)]
                    })
    }

    private static func repetition(_ ctx: WeekContext) -> Spec {
        let rKm = min(5, max(2, ctx.volumeKm * 0.05))
        let rep = rKm >= 3 ? 400.0 : 200.0
        let n = max(6, min(Int(rKm * 1000 / rep), Int((qualityLimit(ctx) - 4000) / (2 * rep))))
        let repTime = ctx.paces.repetition * rep / 1000
        return Spec(kind: .repetition, title: "Tempowiederholungen",
                    details: """
                    2 km einlaufen (locker)
                    \(n) × \(Int(rep)) m @ \(Format.pace(ctx.paces.repetition)) /km (≈ \(Int(repTime.rounded())) s)
                    Pause: \(Int(rep)) m locker traben – vollständig erholen
                    2 km auslaufen (locker)

                    Fokus auf saubere, lockere Technik, nicht auf Kampf.
                    """,
                    distance: 4000 + Double(n) * rep * 2,
                    steps: { _ in
                        [warmup(ctx)]
                            + reps(n, label: "Wiederholung", distance: rep, pace: paceRange(ctx.paces.repetition),
                                   recoveryDistance: rep)
                            + [cooldown(ctx)]
                    })
    }

    private static func racePace(_ ctx: WeekContext, short: Bool) -> Spec {
        let gp = Format.pace(ctx.goalPace)
        let goalRange = paceRange(ctx.goalPace, tolerance: 0.02)
        let title = short ? "Tempo-Schärfung" : "Wettkampftempo"
        var reps: Int, repDist: Double, pause: String, pauseSeconds: TimeInterval
        switch ctx.goal {
        case .fiveK:
            reps = short ? 3 : 5; repDist = 1000; pause = "2 min Trabpause"; pauseSeconds = 120
        case .tenK:
            reps = short ? 3 : 4; repDist = short ? 1000 : 2000; pause = "2 min Trabpause"; pauseSeconds = 120
        case .half:
            reps = short ? 2 : 3; repDist = (short || ctx.volumeKm < 45) ? 3000 : 5000; pause = "3 min Trabpause"
            pauseSeconds = 180
        case .marathon:
            let mKm = short ? 6 : min(16, max(8, (ctx.volumeKm * 0.2).rounded()),
                                      max(6, (qualityLimit(ctx) / 1000 - 4).rounded(.down)))
            return Spec(kind: .racePace, title: title,
                        details: """
                        2 km einlaufen (locker)
                        \(Int(mKm)) km am Stück im Marathontempo: \(gp) /km
                        2 km auslaufen (locker)
                        """,
                        distance: (mKm + 4) * 1000,
                        steps: { _ in [
                            warmup(ctx),
                            WorkoutStep(kind: .run, label: "Marathontempo", distance: mKm * 1000,
                                        paceFast: goalRange.fast, paceSlow: goalRange.slow),
                            cooldown(ctx),
                        ] })
        }
        // Passen keine zwei Wiederholungen in die erlaubte Länge, werden die Abschnitte kürzer.
        let limit = qualityLimit(ctx)
        if Int((limit - 4000) / (repDist + 400)) < 2 {
            repDist = max(1000, (((limit - 4000) / 2 - 400) / 500).rounded(.down) * 500)
        }
        reps = max(2, min(reps, Int((limit - 4000) / (repDist + 400))))
        let repText = repDist >= 1000 ? "\(Format.kilometers(repDist, decimals: 0)) km" : "\(Int(repDist)) m"
        let count = reps
        return Spec(kind: .racePace, title: title,
                    details: """
                    2 km einlaufen (locker) + 4 Steigerungen
                    \(reps) × \(repText) im Zieltempo: \(gp) /km, \(pause)
                    2 km auslaufen (locker)
                    """,
                    distance: 4000 + Double(reps) * repDist + Double(reps) * 400,
                    steps: { _ in
                        [warmup(ctx)]
                            + Self.reps(count, label: "Zieltempo", distance: repDist, pace: goalRange,
                                        recoveryDuration: pauseSeconds)
                            + [cooldown(ctx)]
                    })
    }

    private static func roundHalfKm(_ meters: Double) -> Double {
        (meters / 500).rounded() * 500
    }
}
