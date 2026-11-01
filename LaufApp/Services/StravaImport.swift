import Foundation

/// Datenformate der Strava-API und die Umwandlung in einen `Run`.
enum StravaImport {
    /// Zusammenfassung einer Aktivität aus `GET /athlete/activities`.
    struct Activity: Decodable {
        let id: Int
        let name: String
        let distance: Double
        let movingTime: Double
        let elapsedTime: Double
        let totalElevationGain: Double
        let type: String
        let sportType: String?
        let startDate: Date
        let averageHeartrate: Double?
        let maxHeartrate: Double?
        let averageCadence: Double?

        var isRun: Bool {
            ["Run", "TrailRun", "VirtualRun"].contains(sportType ?? type) || type == "Run"
        }
    }

    struct Stream<T: Decodable>: Decodable {
        let data: [T]
    }

    /// Messreihen aus `GET /activities/{id}/streams?key_by_type=true`.
    struct Streams: Decodable {
        let time: Stream<Double>?
        let distance: Stream<Double>?
        let latlng: Stream<[Double]>?
        let altitude: Stream<Double>?
        let heartrate: Stream<Double>?
        let cadence: Stream<Double>?
        let moving: Stream<Bool>?
    }

    static let streamKeys = "time,distance,latlng,altitude,heartrate,cadence,moving"

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Erzeugt einen Lauf aus Zusammenfassung und Messreihen.
    /// Stillstand (laut `moving`) wird entfernt; nach jeder Pause beginnt ein neues Routen-Segment.
    static func makeRun(activity: Activity, streams: Streams?) -> Run {
        let run = Run(title: activity.name, startDate: activity.startDate,
                      endDate: activity.startDate.addingTimeInterval(activity.elapsedTime))
        run.source = "strava"
        run.stravaID = activity.id
        run.distance = activity.distance
        run.movingTime = activity.movingTime
        run.elapsedTime = activity.elapsedTime
        run.elevationGain = activity.totalElevationGain
        run.averageHeartRate = activity.averageHeartrate ?? 0
        run.maxHeartRate = activity.maxHeartrate ?? 0
        // Strava liefert die Schrittfrequenz beim Laufen pro Bein, also verdoppeln.
        run.averageCadence = (activity.averageCadence ?? 0) * 2

        guard let streams, let times = streams.time?.data, !times.isEmpty else { return run }
        let count = times.count
        func value<T>(_ stream: Stream<T>?, _ i: Int) -> T? {
            guard let data = stream?.data, i < data.count else { return nil }
            return data[i]
        }

        var points: [RoutePoint] = []
        var samples: [SensorSample] = []
        var analysisSamples: [RunAnalysis.Sample] = []
        var segment = 0
        var paused = false
        var movingTime = 0.0
        var previousTime: Double?
        var distanceOffset = 0.0       // Distanz, die während Pausen hinzukam
        var previousDistance: Double?

        for i in 0..<count {
            let t = times[i]
            let isMoving = value(streams.moving, i) ?? true
            let d = value(streams.distance, i)
            if !isMoving {
                paused = true
                previousTime = nil
                continue
            }
            if paused {
                segment += 1
                paused = false
                // Distanz, die im Stillstand gezählt wurde, herausrechnen
                if let d, let previousDistance { distanceOffset += max(0, d - previousDistance) }
            } else if let previousTime {
                if t - previousTime > 30 {
                    segment += 1   // Lücke ohne Messpunkte, z. B. Auto-Pause der Uhr
                } else {
                    movingTime += max(0, t - previousTime)
                }
            }
            previousTime = t
            if let d { previousDistance = d }
            let distance = (d ?? 0) - distanceOffset
            let altitude = value(streams.altitude, i)

            if let latlng = value(streams.latlng, i), latlng.count == 2 {
                points.append(RoutePoint(latitude: latlng[0], longitude: latlng[1], altitude: altitude,
                                         timestamp: activity.startDate.addingTimeInterval(t), segment: segment))
            }
            let heartRate = value(streams.heartrate, i)
            let cadence = value(streams.cadence, i).map { $0 * 2 }
            samples.append(SensorSample(distance: distance, time: movingTime, heartRate: heartRate, cadence: cadence))
            if d != nil {
                analysisSamples.append(RunAnalysis.Sample(distance: distance, time: movingTime, altitude: altitude))
            }
        }

        run.route = points
        if streams.heartrate != nil || streams.cadence != nil { run.sensorSamples = samples }
        // Splits und Bestzeiten aus der Distanz der Uhr, damit sie zu Garmin passen
        if analysisSamples.count > 1 {
            run.splits = RunAnalysis.splits(samples: analysisSamples)
            run.bestEfforts = RunAnalysis.bestEfforts(samples: analysisSamples)
        } else if points.count > 1 {
            run.splits = RunAnalysis.splits(points)
            run.bestEfforts = RunAnalysis.bestEfforts(points)
        }
        if !points.isEmpty { run.elevationLoss = RunAnalysis.totals(points).loss }
        // Fehlende Durchschnittswerte aus den Messreihen ergänzen
        let hrs = samples.compactMap(\.heartRate).filter { $0 > 0 }
        if run.averageHeartRate == 0, !hrs.isEmpty {
            run.averageHeartRate = hrs.reduce(0, +) / Double(hrs.count)
            run.maxHeartRate = hrs.max() ?? 0
        }
        let cads = samples.compactMap(\.cadence).filter { $0 > 0 }
        if run.averageCadence == 0, !cads.isEmpty { run.averageCadence = cads.reduce(0, +) / Double(cads.count) }
        return run
    }

    /// Wurde derselbe Lauf schon mit der App aufgezeichnet? (Start ±10 min, Distanz ±15 %)
    static func isDuplicate(_ activity: Activity, of runs: [Run]) -> Bool {
        runs.contains { run in
            !run.isFromStrava
                && abs(run.startDate.timeIntervalSince(activity.startDate)) < 600
                && abs(run.distance - activity.distance) < max(300, activity.distance * 0.15)
        }
    }
}
