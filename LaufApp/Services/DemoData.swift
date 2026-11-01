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
        return RunAnalysis.makeRun(from: draft, title: RunAnalysis.defaultTitle(for: start),
                                   notes: "Demo-Lauf", effort: Int.random(in: 3...7))
    }
}
#endif
