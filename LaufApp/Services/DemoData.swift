#if DEBUG
import Foundation
import UIKit
import AVFoundation

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
