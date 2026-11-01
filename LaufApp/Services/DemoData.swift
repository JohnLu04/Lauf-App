#if DEBUG
import Foundation

/// Erzeugt realistische Test-Läufe für den Simulator (nur Debug-Builds).
enum DemoData {
    static func makeRun() -> Run {
        let daysAgo = Int.random(in: 0...20)
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            .addingTimeInterval(-Double.random(in: 0...36_000))
        let targetKm = Double.random(in: 4...14)
        let basePace = Double.random(in: 270...360)   // s/km

        // Rundkurs um den Saarbrücker Staden
        let center = (lat: 49.2330, lon: 7.0000)
        let radius = targetKm * 1000 / (2 * .pi)
        let pointCount = Int(targetKm * 1000 / 5)     // alle ~5 m ein Punkt
        var points: [RoutePoint] = []
        var time = start
        for i in 0...pointCount {
            let angle = Double(i) / Double(pointCount) * 2 * .pi
            let wobble = 1 + 0.08 * sin(angle * 5)
            let dLat = radius * wobble * sin(angle) / 111_320
            let dLon = radius * wobble * cos(angle) / (111_320 * cos(center.lat * .pi / 180))
            let pace = basePace + 15 * sin(angle * 3) + Double.random(in: -5...5)
            time = time.addingTimeInterval(pace * 5 / 1000)
            points.append(RoutePoint(latitude: center.lat + dLat, longitude: center.lon + dLon,
                                     altitude: 200 + 25 * sin(angle * 2), timestamp: time, segment: 0))
        }

        let draft = RunDraft(startDate: start, endDate: time, movingTime: time.timeIntervalSince(start),
                             distance: 0, points: points, plannedWorkoutID: nil)
        let run = RunAnalysis.makeRun(from: draft, title: RunAnalysis.defaultTitle(for: start),
                                      notes: "Demo-Lauf", effort: Int.random(in: 3...7))

        // Simulierte Uhr-Daten: Herzfrequenz steigt langsam an (Drift), Schrittfrequenz um 170 spm
        let samples = RunAnalysis.samples(points).enumerated().map { i, s -> SensorSample in
            let progress = s.time / max(1, run.movingTime)
            let hr = min(185, 128 + 20 * min(1, s.time / 300) + 12 * progress + 4 * sin(Double(i) / 40)
                + Double.random(in: -2...2))
            let cadence = 168 + 4 * sin(Double(i) / 60) + Double.random(in: -3...3)
            return SensorSample(distance: s.distance, time: s.time, heartRate: hr.rounded(), cadence: cadence.rounded())
        }
        run.sensorSamples = samples
        run.averageHeartRate = samples.compactMap(\.heartRate).reduce(0, +) / Double(max(1, samples.count))
        run.maxHeartRate = samples.compactMap(\.heartRate).max() ?? 0
        run.averageCadence = samples.compactMap(\.cadence).reduce(0, +) / Double(max(1, samples.count))
        return run
    }
}
#endif
