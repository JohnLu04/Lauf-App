import Foundation

/// Alles, was aus den GPS-Punkten eines Laufs berechnet wird.
enum RunAnalysis {
    struct BestEffortDistance: Identifiable, Hashable {
        let meters: Int
        let name: String
        var id: Int { meters }
    }

    static let bestEffortDistances: [BestEffortDistance] = [
        .init(meters: 400, name: "400 m"),
        .init(meters: 1000, name: "1 km"),
        .init(meters: 1609, name: "1 Meile"),
        .init(meters: 5000, name: "5 km"),
        .init(meters: 10000, name: "10 km"),
        .init(meters: 21098, name: "Halbmarathon"),
        .init(meters: 42195, name: "Marathon"),
    ]

    struct Sample {
        var distance: Double  // kumuliert, Meter
        var time: Double      // kumulierte Bewegungszeit, Sekunden
        var altitude: Double?
    }

    /// Kumulierte Distanz/Bewegungszeit je Punkt. Pausen (Segmentwechsel) zählen weder Zeit noch Distanz.
    static func samples(_ points: [RoutePoint]) -> [Sample] {
        guard let first = points.first else { return [] }
        var result = [Sample(distance: 0, time: 0, altitude: first.altitude)]
        result.reserveCapacity(points.count)
        var dist = 0.0, time = 0.0
        for (prev, cur) in zip(points, points.dropFirst()) {
            if prev.segment == cur.segment {
                dist += Geo.distance(prev, cur)
                time += max(0, cur.timestamp.timeIntervalSince(prev.timestamp))
            }
            result.append(Sample(distance: dist, time: time, altitude: cur.altitude))
        }
        return result
    }

    static func totals(_ points: [RoutePoint]) -> (distance: Double, movingTime: Double, gain: Double, loss: Double) {
        let s = samples(points)
        var elevation = ElevationTracker()
        s.forEach { elevation.add($0.altitude) }
        return (s.last?.distance ?? 0, s.last?.time ?? 0, elevation.gain, elevation.loss)
    }

    /// Kilometer-Splits mit interpolierter Zeit an jeder km-Grenze.
    static func splits(_ points: [RoutePoint]) -> [Split] { splits(samples: samples(points)) }

    static func splits(samples s: [Sample]) -> [Split] {
        guard s.count > 1 else { return [] }
        var splits: [Split] = []
        var splitStartDist = 0.0, splitStartTime = 0.0
        var elevation = ElevationTracker()
        elevation.add(s[0].altitude)
        for (prev, cur) in zip(s, s.dropFirst()) {
            elevation.add(cur.altitude)
            while cur.distance - splitStartDist >= 1000 {
                let boundary = splitStartDist + 1000
                let segDist = cur.distance - prev.distance
                let frac = segDist > 0 ? (boundary - prev.distance) / segDist : 1
                let t = prev.time + (cur.time - prev.time) * frac
                splits.append(Split(index: splits.count + 1, distance: 1000,
                                    duration: t - splitStartTime, elevationGain: elevation.gain))
                elevation.resetCounters()
                splitStartDist = boundary
                splitStartTime = t
            }
        }
        if let last = s.last, last.distance - splitStartDist >= 50 {
            splits.append(Split(index: splits.count + 1, distance: last.distance - splitStartDist,
                                duration: last.time - splitStartTime, elevationGain: elevation.gain))
        }
        return splits
    }

    /// Schnellste Zeit für jede Standard-Distanz, die im Lauf enthalten ist.
    static func bestEfforts(_ points: [RoutePoint]) -> [Int: Double] { bestEfforts(samples: samples(points)) }

    static func bestEfforts(samples s: [Sample]) -> [Int: Double] {
        guard let total = s.last?.distance else { return [:] }
        var result: [Int: Double] = [:]
        for target in bestEffortDistances where Double(target.meters) <= total {
            let d = Double(target.meters)
            var best = Double.infinity
            var i = 0
            for j in s.indices {
                while i + 1 < j, s[j].distance - s[i + 1].distance >= d { i += 1 }
                let covered = s[j].distance - s[i].distance
                if covered >= d {
                    // auf exakte Zieldistanz normieren
                    let t = (s[j].time - s[i].time) * d / covered
                    best = min(best, t)
                }
            }
            if best.isFinite { result[target.meters] = best }
        }
        return result
    }

    struct SeriesPoint: Identifiable {
        let km: Double
        let value: Double
        var id: Double { km }
    }

    /// Geglättete Pace (s/km) über die Distanz, ein Wert alle `step` Meter.
    static func paceSeries(_ points: [RoutePoint], step: Double = 100, window: Double = 300) -> [SeriesPoint] {
        let s = samples(points)
        guard let total = s.last?.distance, total > window else { return [] }
        var result: [SeriesPoint] = []
        var i = 0, j = 0
        var d = window
        while d <= total {
            while j < s.count - 1 && s[j].distance < d { j += 1 }
            while i < j && s[i + 1].distance <= d - window { i += 1 }
            let dist = s[j].distance - s[i].distance
            let time = s[j].time - s[i].time
            if dist > 0 {
                let pace = time / (dist / 1000)
                if pace > 120 && pace < 1200 { result.append(SeriesPoint(km: d / 1000, value: pace)) }
            }
            d += step
        }
        return result
    }

    /// Höhenprofil, ein Wert alle `step` Meter.
    static func elevationSeries(_ points: [RoutePoint], step: Double = 100) -> [SeriesPoint] {
        let s = samples(points)
        var result: [SeriesPoint] = []
        var next = 0.0
        for sample in s where sample.distance >= next {
            if let alt = sample.altitude { result.append(SeriesPoint(km: sample.distance / 1000, value: alt)) }
            next = sample.distance + step
        }
        return result
    }

    /// Herzfrequenz oder Schrittfrequenz über die Distanz, gemittelt je `step` Meter.
    static func sensorSeries(_ samples: [SensorSample], step: Double = 100,
                             value: (SensorSample) -> Double?) -> [SeriesPoint] {
        var result: [SeriesPoint] = []
        var binEnd = step, sum = 0.0, count = 0
        for sample in samples {
            while sample.distance > binEnd {
                if count > 0 { result.append(SeriesPoint(km: (binEnd - step / 2) / 1000, value: sum / Double(count))) }
                binEnd += step
                sum = 0
                count = 0
            }
            if let v = value(sample), v > 0 {
                sum += v
                count += 1
            }
        }
        if count > 0 { result.append(SeriesPoint(km: (binEnd - step / 2) / 1000, value: sum / Double(count))) }
        return result
    }

    /// Teilt die Route an Pausen in einzelne Linien.
    static func segments(_ points: [RoutePoint]) -> [[RoutePoint]] {
        var result: [[RoutePoint]] = []
        for p in points {
            if let last = result.last?.last, last.segment == p.segment {
                result[result.count - 1].append(p)
            } else {
                result.append([p])
            }
        }
        return result
    }

    /// Erzeugt aus einer fertigen Aufzeichnung ein speicherbares `Run`-Objekt.
    static func makeRun(from draft: RunDraft, title: String, notes: String, effort: Int) -> Run {
        let run = Run(title: title, startDate: draft.startDate, endDate: draft.endDate)
        let totals = totals(draft.points)
        run.notes = notes
        run.perceivedEffort = effort
        run.distance = totals.distance
        run.movingTime = totals.distance > 0 ? totals.movingTime : draft.movingTime
        run.elapsedTime = draft.endDate.timeIntervalSince(draft.startDate)
        run.elevationGain = totals.gain
        run.elevationLoss = totals.loss
        run.plannedWorkoutID = draft.plannedWorkoutID
        run.route = draft.points
        run.splits = splits(draft.points)
        run.bestEfforts = bestEfforts(draft.points)
        return run
    }

    static func defaultTitle(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return "Morgenlauf"
        case 11..<14: return "Mittagslauf"
        case 14..<18: return "Nachmittagslauf"
        case 18..<22: return "Abendlauf"
        default: return "Nachtlauf"
        }
    }
}

/// Ergebnis einer Aufzeichnung, bevor sie gespeichert wird.
struct RunDraft: Identifiable {
    let id = UUID()
    var startDate: Date
    var endDate: Date
    var movingTime: TimeInterval
    var distance: Double
    var points: [RoutePoint]
    var plannedWorkoutID: UUID?
}
