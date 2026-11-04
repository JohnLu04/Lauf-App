#if DEBUG
import Foundation
import UIKit
import AVFoundation
import HealthKit
import CoreLocation

/// Erzeugt realistische Test-Läufe für den Simulator (nur Debug-Builds).
enum DemoData {
    /// Speichert einen Test-Lauf (Route, Herzfrequenz, Schritte, Distanz, eine Pause) in Apple Health.
    static func writeHealthWorkout(to store: HKHealthStore) async throws {
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
                                             HealthSync.heartRate, HealthSync.steps, HealthSync.distance]
        try await store.requestAuthorization(toShare: shareTypes, read: HealthSync.readTypes)

        // Vorlage: zufälliger Demo-Lauf (Route und Messwerte), heute vor zwei Stunden
        let template = makeRun()
        RunPhotoStore.deleteAll(for: template.id)
        let shift = Date.now.addingTimeInterval(-7200).timeIntervalSince(template.startDate)
        let points = template.route.map { p -> RoutePoint in
            var p = p
            p.timestamp = p.timestamp.addingTimeInterval(shift)
            return p
        }
        guard let first = points.first, let last = points.last else { return }
        // Zwei Minuten Pause nach der Hälfte (Ampel)
        let pauseIndex = points.count / 2
        let pause: TimeInterval = 120
        let timed = points.enumerated().map { i, p -> RoutePoint in
            var p = p
            if i > pauseIndex { p.timestamp = p.timestamp.addingTimeInterval(pause) }
            return p
        }
        let start = first.timestamp, end = last.timestamp.addingTimeInterval(pause)
        let pauseStart = timed[pauseIndex].timestamp

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        let bpm = HKUnit.count().unitDivided(by: .minute())
        var samples: [HKSample] = []
        let sensors = template.sensorSamples
        // Messwerte alle 10 s
        var t = start
        var previous = start
        var index = 0
        while t < end {
            let next = min(end, t.addingTimeInterval(10))
            if !(t >= pauseStart && t < pauseStart.addingTimeInterval(pause)) {
                while index < timed.count - 1 && timed[index].timestamp < next { index += 1 }
                let sensor = sensors.isEmpty ? nil : sensors[min(sensors.count - 1, index * sensors.count / max(1, timed.count))]
                if let hr = sensor?.heartRate {
                    samples.append(HKQuantitySample(type: HealthSync.heartRate, quantity: HKQuantity(unit: bpm, doubleValue: hr), start: t, end: t))
                }
                let cadence = sensor?.cadence ?? 168
                samples.append(HKQuantitySample(type: HealthSync.steps, quantity: HKQuantity(unit: .count(), doubleValue: cadence * next.timeIntervalSince(t) / 60),
                                                start: t, end: next))
                let segment = timed.filter { $0.timestamp > previous && $0.timestamp <= next }
                var meters = 0.0
                for (a, b) in zip(segment, segment.dropFirst()) { meters += Geo.distance(a, b) }
                if meters > 0 {
                    samples.append(HKQuantitySample(type: HealthSync.distance, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                                                    start: t, end: next))
                }
            }
            previous = next
            t = next
        }
        try await builder.addSamples(samples)
        try await builder.addWorkoutEvents([
            HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pauseStart, duration: 0), metadata: nil),
            HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pauseStart.addingTimeInterval(pause), duration: 0), metadata: nil),
        ])
        try await builder.addMetadata([HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: template.elevationGain)])
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        let locations = timed.map {
            CLLocation(coordinate: $0.coordinate, altitude: $0.altitude ?? 0, horizontalAccuracy: 5, verticalAccuracy: 3,
                       course: -1, speed: -1, timestamp: $0.timestamp)
        }
        try await routeBuilder.insertRouteData(locations)
        try await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    /// Sechs Einheiten „Maximalkraft“ der letzten drei Wochen mit steigenden Gewichten
    static func makeStrengthSessions() -> [StrengthSession] {
        (0..<6).map { i in
            let date = Calendar.current.date(byAdding: .day, value: -3 * (6 - i), to: .now)!
            let session = StrengthSession(date: date, programID: "maxStrength")
            let squat = 70 + Double(i) * 2.5
            session.entries = [
                StrengthEntry(exerciseID: "backSquat", sets: (0..<4).map { s in
                    StrengthSet(reps: s == 3 && i % 2 == 0 ? 3 : 4, weight: squat, reserve: s == 3 ? 0 : 1)
                }),
                StrengthEntry(exerciseID: "romanianDeadlift", sets: (0..<3).map { _ in StrengthSet(reps: 6, weight: 50 + Double(i / 2) * 5) }),
                StrengthEntry(exerciseID: "bulgarianSplitSquat", sets: (0..<3).map { _ in StrengthSet(reps: 6, weight: 16 + Double(i / 3) * 2) }),
                StrengthEntry(exerciseID: "soleusRaise", sets: (0..<3).map { _ in StrengthSet(reps: 8, weight: 40 + Double(i) * 2.5) }),
                StrengthEntry(exerciseID: "plank", sets: (0..<2).map { _ in StrengthSet(seconds: 40 + i * 5) }),
            ]
            session.durationMinutes = 45 + i
            session.effort = 7
            return session
        }
    }

    /// Strecke mit Hin- und Rückweg auf denselben Straßen und einer kleinen Schleife am Wendepunkt
    /// (zum Prüfen der Richtungspfeile)
    static func makeOutAndBackRoute() -> PlannedRoute {
        let out = [(49.2323, 7.0000), (49.2300, 6.9985), (49.2285, 7.0010), (49.2270, 7.0050),
                   (49.2255, 7.0095), (49.2245, 7.0130)]
            .map { RouteCoordinate(latitude: $0.0, longitude: $0.1) }
        let loop = [(49.2235, 7.0142), (49.2226, 7.0122), (49.2237, 7.0108), (49.2245, 7.0130)]
            .map { RouteCoordinate(latitude: $0.0, longitude: $0.1) }
        let path = ElevationService.resample(out + loop + out.reversed().dropFirst(), every: 10).map(\.point)
        return PlannedRoute(name: "Demo: Hin und zurück", waypoints: [out[0], out[5], out[0]], path: path, followsPaths: false)
    }

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

        // Generierte Testmedien: zwei Fotos, ein abspielbares Video, ein Video nur mit Standbild
        run.stravaID = Int.random(in: 10_000_000_000...99_999_999_999)  // für „In Strava ansehen“
        let items: [(caption: String, from: UIColor, to: UIColor, kind: Int)] = [
            ("Sonnenaufgang am Staden", .systemOrange, .systemPink, 0),
            ("Zieleinlauf", .systemTeal, .systemIndigo, 0),
            ("Video: Testclip", .systemGreen, .systemBlue, 1),
            ("Video nur in Strava", .systemPurple, .systemRed, 2),
        ]
        run.photos = items.enumerated().compactMap { i, item in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).image { ctx in
                let colors = [item.from.cgColor, item.to.cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1200, y: 900), options: [])
                let text = NSAttributedString(string: item.caption, attributes: [
                    .font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.white])
                text.draw(at: CGPoint(x: 60, y: 760))
            }
            let id = "demo-\(i)"
            guard let data = image.jpegData(compressionQuality: 0.85),
                  let fileName = try? RunPhotoStore.save(data, photoID: id, runID: run.id) else { return nil }
            var photo = RunPhoto(id: id, fileName: fileName, caption: item.caption)
            if item.kind > 0 { photo.isVideo = true }
            if item.kind == 1 { photo.videoFileName = makeTestVideo(id: id, runID: run.id) }
            return photo
        }

        // Beispiel-Kudos und -Kommentare
        run.kudoers = [("Anna", "M."), ("Ben", "K."), ("Clara", "S."), ("David", "W."), ("Elif", "Y."), ("Felix", "R."), ("Greta", "")]
            .map { StravaKudoer(firstName: $0.0, lastName: $0.1) }
        run.kudosCount = run.kudoers.count
        run.comments = [
            StravaComment(id: 1, text: "Starke Pace! 🔥", date: run.endDate.addingTimeInterval(1_800), firstName: "Anna", lastName: "M."),
            StravaComment(id: 2, text: "Schöne Runde an der Saar, die muss ich auch mal laufen.", date: run.endDate.addingTimeInterval(7_200),
                          firstName: "Felix", lastName: "R."),
        ]
        run.commentCount = run.comments.count
        return run
    }

    /// Erzeugt ein 4-Sekunden-Testvideo im Hochformat (Farbfläche mit wanderndem Quadrat) im Ordner des Laufs.
    private static func makeTestVideo(id: String, runID: UUID) -> String? {
        let fileName = id + "-video.mp4"
        let folder = RunPhotoStore.folder(for: runID)
        let url = folder.appending(path: fileName)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let size = CGSize(width: 360, height: 640)  // Hochformat wie beim Handy-Video
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 30
        for frame in 0..<(4 * Int(fps)) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                let t = CGFloat(frame) / CGFloat(4 * fps)
                ctx.setFillColor(UIColor(hue: 0.35 + 0.25 * t, saturation: 0.7, brightness: 0.8, alpha: 1).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: 140, y: t * (size.height - 80), width: 80, height: 80))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        return writer.status == .completed ? fileName : nil
    }
}
#endif
