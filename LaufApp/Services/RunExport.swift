import Foundation
import HealthKit
import CoreLocation
import Observation
import SwiftData

extension HealthSync {
    nonisolated static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distance]

    /// Darf LaufApp Trainings in Apple Health speichern? (Anders als beim Lesen verrät HealthKit das.)
    var canSaveWorkouts: Bool {
        Self.isAvailable && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Speichert den Lauf als Lauftraining in Apple Health – bei Aufzeichnungen mit Strecke und Pausen,
    /// bei eingetragenen Läufen nur mit Distanz und Zeit – und verknüpft ihn (kein doppelter Import).
    func save(_ run: Run) async throws {
        guard Self.isAvailable else { throw SyncError.unavailable }
        if !canSaveWorkouts {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        }
        guard canSaveWorkouts else { throw SyncError.writeDenied }

        let start = run.startDate
        let end = max(run.endDate, start.addingTimeInterval(max(run.elapsedTime, run.movingTime, 60)))
        // Echte GPS-Aufzeichnung (eingetragene Läufe haben höchstens eine nachgebildete Strecke)
        let points = run.isManual ? [] : run.route
        let segments = RunAnalysis.segments(points).filter { $0.count > 1 }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = segments.isEmpty ? .unknown : .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)

        // Distanz in Abschnitten von etwa 30 Sekunden (für Pace-Verlauf und Splits in Apple Health)
        var samples: [HKQuantitySample] = []
        func distanceSample(_ meters: Double, _ from: Date, _ to: Date) -> HKQuantitySample {
            HKQuantitySample(type: Self.distance, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                             start: from, end: max(to, from.addingTimeInterval(1)))
        }
        var chunks: [(meters: Double, from: Date, to: Date)] = []
        for segment in segments {
            var from = segment[0].timestamp, meters = 0.0
            for (a, b) in zip(segment, segment.dropFirst()) {
                meters += Geo.distance(a, b)
                if b.timestamp.timeIntervalSince(from) >= 30 {
                    chunks.append((meters, from, b.timestamp))
                    from = b.timestamp
                    meters = 0
                }
            }
            if meters > 0 { chunks.append((meters, from, segment.last!.timestamp)) }
        }
        let measured = chunks.reduce(0) { $0 + $1.meters }
        if measured > 0 {
            // Auf die angezeigte Distanz des Laufs abgleichen
            let scale = run.distance > 0 ? run.distance / measured : 1
            samples = chunks.map { distanceSample($0.meters * scale, $0.from, $0.to) }
        } else if run.distance > 0 {
            samples = [distanceSample(run.distance, start, end)]
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }

        // Pausen zwischen den Abschnitten der Aufzeichnung
        var events: [HKWorkoutEvent] = []
        for (a, b) in zip(segments, segments.dropFirst()) {
            guard let pauseStart = a.last?.timestamp, let resume = b.first?.timestamp, resume > pauseStart else { continue }
            events.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pauseStart, duration: 0), metadata: nil))
            events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: resume, duration: 0), metadata: nil))
        }
        if !events.isEmpty { try await builder.addWorkoutEvents(events) }

        var metadata: [String: Any] = [HKMetadataKeyExternalUUID: run.id.uuidString,
                                       HKMetadataKeyIndoorWorkout: false]
        if run.elevationGain > 0 {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: run.elevationGain)
        }
        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw SyncError.writeDenied }

        if !segments.isEmpty {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            let locations = segments.joined().map {
                CLLocation(coordinate: $0.coordinate, altitude: $0.altitude ?? 0, horizontalAccuracy: 5,
                           verticalAccuracy: $0.altitude == nil ? -1 : 5, course: -1, speed: -1, timestamp: $0.timestamp)
            }
            try await routeBuilder.insertRouteData(locations)
            try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        run.healthID = workout.uuid.uuidString
        run.healthSourceName = "LaufApp"
    }
}

/// Führt das Hochladen bzw. Speichern im Hintergrund aus (auch wenn die Ansicht schon geschlossen ist)
/// und meldet das Ergebnis als kurzen Hinweis.
@MainActor
@Observable
final class RunExporter {
    static let shared = RunExporter()

    /// Läufe, die gerade übertragen werden
    private(set) var busy: Set<UUID> = []
    /// Ergebnis für den Hinweis am unteren Bildschirmrand
    var message: String?

    func export(_ run: Run, toStrava: Bool, toHealth: Bool, context: ModelContext) {
        guard toStrava || toHealth, !busy.contains(run.id) else { return }
        busy.insert(run.id)
        Task {
            var done: [String] = []
            var errors: [String] = []
            if toHealth, RunExport.canSaveToHealth(run) {
                do {
                    try await HealthSync.shared.save(run)
                    done.append("in Apple Health gespeichert")
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            if toStrava, RunExport.canUploadToStrava(run) {
                do {
                    try await StravaSync.shared.upload(run)
                    done.append("zu Strava hochgeladen")
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            try? context.save()
            busy.remove(run.id)
            let summary = done.isEmpty ? nil : "„\(run.title)“ " + done.joined(separator: " und ") + "."
            show(([summary].compactMap { $0 } + errors).joined(separator: "\n"))
        }
    }

    private func show(_ text: String) {
        guard !text.isEmpty else { return }
        message = text
        Task {
            try? await Task.sleep(for: .seconds(text.count > 80 ? 6 : 3))
            if message == text { message = nil }
        }
    }
}
