import Foundation
import HealthKit
import CoreLocation
import Observation
import SwiftData

/// Import von Lauftrainings aus Apple Health (Apple Watch, Garmin Connect, Nike Run Club …):
/// Strecke, Herzfrequenz, Schrittfrequenz, Splits und Höhenmeter. Neue Trainings werden über einen
/// Anker erkannt, damit jedes Training nur einmal abgefragt wird.
@MainActor
@Observable
final class HealthSync {
    static let shared = HealthSync()

    enum SyncError: LocalizedError {
        case missingEntitlement
        case unavailable

        var errorDescription: String? {
            switch self {
            case .missingEntitlement:
                "Diese Installation der App hat keine Berechtigung für Apple Health. Beim Installieren (z. B. mit Sideloadly) muss die HealthKit-Berechtigung erhalten bleiben."
            case .unavailable:
                "Apple Health ist auf diesem Gerät nicht verfügbar."
            }
        }
    }

    @ObservationIgnored let store = HKHealthStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observer: HKObserverQuery?
    @ObservationIgnored private weak var observedContext: ModelContext?

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastResult: String?

    /// Import eingeschaltet (nach erteilter Erlaubnis)
    private(set) var isEnabled: Bool

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "health.enabled")
    }

    nonisolated static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private(set) var lastSyncDate: Date? {
        get { defaults.object(forKey: "health.lastSync") as? Date }
        set { defaults.set(newValue, forKey: "health.lastSync") }
    }

    /// Beim ersten Import werden die Läufe dieser letzten Tage übernommen.
    var initialImportDays: Int {
        get { defaults.object(forKey: "health.initialDays") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "health.initialDays") }
    }

    /// Fortschritt der Abfrage (neue Trainings seit dem letzten Import)
    private var anchor: HKQueryAnchor? {
        get {
            guard let data = defaults.data(forKey: "health.anchor") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            defaults.set(data, forKey: "health.anchor")
        }
    }

    nonisolated static let heartRate = HKQuantityType(.heartRate)
    nonisolated static let steps = HKQuantityType(.stepCount)
    nonisolated static let distance = HKQuantityType(.distanceWalkingRunning)
    nonisolated static let readTypes: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), heartRate, steps, distance]

    // MARK: - Ein- und Ausschalten

    /// Fragt nach der Leseerlaubnis und importiert danach. (Ob das Lesen erlaubt wurde, verrät
    /// HealthKit aus Datenschutzgründen nicht; ohne Erlaubnis werden einfach keine Trainings gefunden.)
    func enable(context: ModelContext) async {
        lastError = nil
        guard Self.isAvailable else { lastError = SyncError.unavailable.localizedDescription; return }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            isEnabled = true
            defaults.set(true, forKey: "health.enabled")
            startObserving(context: context)
            await sync(context: context)
        } catch {
            lastError = Self.describe(error)
        }
    }

    func disable() {
        isEnabled = false
        defaults.set(false, forKey: "health.enabled")
        if let observer { store.stop(observer) }
        observer = nil
    }

    /// Ältere Läufe erneut abfragen (z. B. nach Änderung des Zeitraums); vorhandene werden nicht doppelt angelegt.
    func resetAnchor() { anchor = nil }

    /// Neue Trainings importieren, sobald Apple Health sie meldet (solange die App läuft).
    func startObserving(context: ModelContext) {
        observedContext = context
        guard isEnabled, observer == nil, Self.isAvailable else { return }
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { [weak self] _, completion, error in
            completion()
            guard error == nil else { return }
            Task { @MainActor in
                guard let self, let context = self.observedContext else { return }
                await self.sync(context: context)
            }
        }
        observer = query
        store.execute(query)
    }

    /// Beim Öffnen der App höchstens jede Minute abfragen (Apple Health liegt auf dem Gerät, das geht schnell).
    func syncIfNeeded(context: ModelContext) async {
        guard isEnabled, !isSyncing else { return }
        startObserving(context: context)
        if let last = lastSyncDate, Date().timeIntervalSince(last) < 60 { return }
        await sync(context: context)
    }

    // MARK: - Import

    func sync(context: ModelContext) async {
        guard isEnabled, !isSyncing, Self.isAvailable else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let since = Calendar.current.date(byAdding: .day, value: -initialImportDays, to: .now) ?? .now
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .running),
                HKQuery.predicateForSamples(withStart: since, end: nil),
            ])
            let query = HKAnchoredObjectQueryDescriptor(predicates: [.workout(predicate)], anchor: anchor)
            let result = try await query.result(for: store)

            var existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            var imported = 0, linked = 0
            for workout in result.addedSamples.sorted(by: { $0.startDate < $1.startDate }) {
                let id = workout.uuid.uuidString
                if existing.contains(where: { $0.healthID == id }) { continue }
                let distance = Self.totalDistance(workout)
                if let duplicate = HealthImport.duplicate(start: workout.startDate, distance: distance, in: existing) {
                    // Schon von Strava importiert oder mit LaufApp aufgezeichnet: nur verknüpfen
                    if duplicate.healthID == nil, duplicate.isFromStrava {
                        duplicate.healthID = id
                        duplicate.healthSourceName = workout.sourceRevision.source.name
                        linked += 1
                    }
                    continue
                }
                let run = try await makeRun(from: workout)
                context.insert(run)
                try? context.save()
                existing.append(run)
                imported += 1
            }
            anchor = result.newAnchor
            try? context.save()
            lastSyncDate = .now
            lastResult = switch imported {
            case 0: linked > 0 ? "Keine neuen Läufe (\(linked) mit Strava-Läufen verknüpft)." : "Keine neuen Läufe."
            case 1: "1 neuer Lauf importiert."
            default: "\(imported) neue Läufe importiert."
            }
        } catch {
            lastSyncDate = .now
            lastError = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription
        if text.localizedCaseInsensitiveContains("entitlement") { return SyncError.missingEntitlement.localizedDescription }
        return text
    }

    nonisolated static func totalDistance(_ workout: HKWorkout) -> Double {
        workout.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.totalDistance?.doubleValue(for: .meter()) ?? 0
    }

    // MARK: - Ein Training in einen Lauf umwandeln

    private func makeRun(from workout: HKWorkout) async throws -> Run {
        let start = workout.startDate, end = workout.endDate
        let timeRange = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sameSource = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timeRange, HKQuery.predicateForObjects(from: workout.sourceRevision.source),
        ])

        func samples(_ type: HKQuantityType, _ predicate: NSPredicate) async throws -> [HKQuantitySample] {
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                     sortDescriptors: [SortDescriptor(\.startDate)])
            return try await descriptor.result(for: store)
        }

        // Schritte und Distanz nur von der Quelle des Trainings, sonst zählen iPhone und Uhr doppelt.
        // Die Herzfrequenz stammt oft von der Uhr, auch wenn eine andere App das Training speichert.
        var heartRates = try await samples(Self.heartRate, sameSource)
        if heartRates.isEmpty { heartRates = try await samples(Self.heartRate, timeRange) }
        let steps = try await samples(Self.steps, sameSource)
        let distances = try await samples(Self.distance, sameSource)

        // Route (GPS-Punkte)
        var locations: [CLLocation] = []
        let routes = try await HKSampleQueryDescriptor(predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                                                       sortDescriptors: []).result(for: store)
        for route in routes {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                locations.append(location)
            }
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let data = HealthImport.WorkoutData(
            start: start, end: end, duration: workout.duration,
            totalDistance: Self.totalDistance(workout),
            elevationAscended: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
            indoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false,
            averageHeartRate: workout.statistics(for: Self.heartRate)?.averageQuantity()?.doubleValue(for: bpm),
            maxHeartRate: workout.statistics(for: Self.heartRate)?.maximumQuantity()?.doubleValue(for: bpm),
            pauses: HealthImport.pauses(from: (workout.workoutEvents ?? []).map { ($0.type, $0.dateInterval) }, end: end),
            locations: locations.map { HealthImport.Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                                                             altitude: $0.verticalAccuracy >= 0 ? $0.altitude : nil, time: $0.timestamp) },
            heartRates: heartRates.map { HealthImport.Value(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: bpm)) },
            steps: steps.map { HealthImport.Value(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: .count())) },
            distances: distances.map { HealthImport.Value(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: .meter())) })

        let run = HealthImport.makeRun(data)
        run.source = "health"
        run.healthID = workout.uuid.uuidString
        run.healthSourceName = workout.sourceRevision.source.name
        return run
    }
}

/// Umrechnung der Apple-Health-Daten in einen Lauf (ohne HealthKit, damit sie sich testen lässt).
enum HealthImport {
    struct Location { var latitude: Double; var longitude: Double; var altitude: Double?; var time: Date }
    struct Value { var start: Date; var end: Date; var value: Double }

    struct WorkoutData {
        var start: Date
        var end: Date
        /// Aktive Dauer ohne Pausen (Sekunden)
        var duration: Double
        var totalDistance: Double
        var elevationAscended: Double?
        var indoor: Bool
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var pauses: [DateInterval]
        var locations: [Location]
        var heartRates: [Value]
        var steps: [Value]
        var distances: [Value]
    }

    /// Gleicher Lauf schon vorhanden (Start auf 10 Minuten genau, Distanz ähnlich)?
    static func duplicate(start: Date, distance: Double, in runs: [Run]) -> Run? {
        runs.first { run in
            abs(run.startDate.timeIntervalSince(start)) < 600
                && abs(run.distance - distance) < max(300, distance * 0.15)
        }
    }

    /// Pausen aus den Trainingsereignissen (manuelle Pause und automatische Pause der Uhr)
    static func pauses(from events: [(HKWorkoutEventType, DateInterval)], end: Date) -> [DateInterval] {
        var result: [DateInterval] = []
        var pausedSince: Date?
        for (type, interval) in events.sorted(by: { $0.1.start < $1.1.start }) {
            switch type {
            case .pause, .motionPaused:
                if pausedSince == nil { pausedSince = interval.start }
            case .resume, .motionResumed:
                if let since = pausedSince, interval.start > since { result.append(DateInterval(start: since, end: interval.start)) }
                pausedSince = nil
            default:
                break
            }
        }
        if let since = pausedSince, end > since { result.append(DateInterval(start: since, end: end)) }
        return result
    }

    static func makeRun(_ d: WorkoutData) -> Run {
        let title = RunAnalysis.defaultTitle(for: d.start) + (d.indoor ? " (Laufband)" : "")
        let run = Run(title: title, startDate: d.start, endDate: d.end)
        run.elapsedTime = d.end.timeIntervalSince(d.start)

        /// Bewegungszeit vom Start bis `t` (ohne Pausen)
        func movingTime(at t: Date) -> Double {
            let elapsed = t.timeIntervalSince(d.start)
            let paused = d.pauses.reduce(0.0) { sum, p in
                sum + max(0, min(t, p.end).timeIntervalSince(p.start))
            }
            return max(0, elapsed - paused)
        }
        func isPaused(_ t: Date) -> Bool { d.pauses.contains { $0.contains(t) } }

        // Kumulierte Distanz der Uhr über die Zeit (Ende jedes Abschnitts)
        var cumulative: [(time: Date, distance: Double)] = [(d.start, 0)]
        for sample in d.distances.sorted(by: { $0.start < $1.start }) {
            cumulative.append((sample.end, (cumulative.last?.distance ?? 0) + sample.value))
        }
        func distance(at t: Date) -> Double {
            guard cumulative.count > 1 else { return 0 }
            guard let i = cumulative.firstIndex(where: { $0.time >= t }) else { return cumulative.last!.distance }
            if i == 0 { return 0 }
            let a = cumulative[i - 1], b = cumulative[i]
            let span = b.time.timeIntervalSince(a.time)
            let f = span > 0 ? t.timeIntervalSince(a.time) / span : 1
            return a.distance + (b.distance - a.distance) * max(0, min(1, f))
        }

        // Route mit Segmenten (neues Segment nach Pausen und Lücken > 30 s)
        var points: [RoutePoint] = []
        var segment = 0
        var previous: Date?
        for location in d.locations.sorted(by: { $0.time < $1.time }) where !isPaused(location.time) {
            if let previous, location.time.timeIntervalSince(previous) > 30
                || d.pauses.contains(where: { $0.start >= previous && $0.start <= location.time }) {
                segment += 1
            }
            previous = location.time
            points.append(RoutePoint(latitude: location.latitude, longitude: location.longitude, altitude: location.altitude,
                                     timestamp: location.time, segment: segment))
        }
        run.route = points

        // Kennzahlen: Distanz und aktive Zeit wie auf der Uhr
        let routeTotals = points.count > 1 ? RunAnalysis.totals(points) : nil
        run.distance = d.totalDistance > 0 ? d.totalDistance : (routeTotals?.distance ?? 0)
        run.movingTime = d.duration > 0 ? d.duration : (routeTotals?.movingTime ?? run.elapsedTime)
        run.elevationGain = d.elevationAscended ?? routeTotals?.gain ?? 0
        run.elevationLoss = routeTotals?.loss ?? 0

        // Messreihen: Herzfrequenz und Schrittfrequenz über Distanz und Bewegungszeit
        let stepSamples = d.steps.sorted { $0.start < $1.start }
        func cadence(at t: Date) -> Double? {
            guard let s = stepSamples.first(where: { $0.start <= t && $0.end >= t }) ?? stepSamples.last(where: { $0.end <= t }),
                  s.end.timeIntervalSince(s.start) >= 3, abs(s.end.timeIntervalSince(t)) < 120 else { return nil }
            let value = s.value / s.end.timeIntervalSince(s.start) * 60
            return (100...260).contains(value) ? value : nil
        }
        var sensors: [SensorSample] = []
        for hr in d.heartRates.sorted(by: { $0.start < $1.start }) where !isPaused(hr.start) {
            sensors.append(SensorSample(distance: distance(at: hr.start), time: movingTime(at: hr.start),
                                        heartRate: hr.value, cadence: cadence(at: hr.start)))
        }
        if sensors.isEmpty {
            for s in stepSamples where !isPaused(s.start) {
                let mid = s.start.addingTimeInterval(s.end.timeIntervalSince(s.start) / 2)
                if let c = cadence(at: mid) {
                    sensors.append(SensorSample(distance: distance(at: mid), time: movingTime(at: mid), heartRate: nil, cadence: c))
                }
            }
        }
        if cumulative.count < 2, let routeTotals, routeTotals.distance > 0 {
            // Keine Distanzdaten der Uhr: Distanz aus der Route anteilig über die Zeit
            for i in sensors.indices { sensors[i].distance = run.distance * min(1, sensors[i].time / max(1, run.movingTime)) }
        }
        if !sensors.isEmpty { run.sensorSamples = sensors }

        run.averageHeartRate = d.averageHeartRate ?? average(sensors.compactMap(\.heartRate))
        run.maxHeartRate = d.maxHeartRate ?? sensors.compactMap(\.heartRate).max() ?? 0
        let totalSteps = stepSamples.reduce(0) { $0 + $1.value }
        run.averageCadence = totalSteps > 0 && run.movingTime > 0 ? totalSteps / run.movingTime * 60 : average(sensors.compactMap(\.cadence))

        // Splits und Bestzeiten aus der Distanz der Uhr (passt zur Anzeige auf der Uhr), sonst aus der Route
        if cumulative.count > 2 {
            let analysis = cumulative.filter { !isPaused($0.time) }.map { entry in
                RunAnalysis.Sample(distance: entry.distance, time: movingTime(at: entry.time),
                                   altitude: nearestAltitude(points, at: entry.time))
            }
            run.splits = RunAnalysis.splits(samples: analysis)
            run.bestEfforts = RunAnalysis.bestEfforts(samples: analysis)
        } else if points.count > 1 {
            run.splits = RunAnalysis.splits(points)
            run.bestEfforts = RunAnalysis.bestEfforts(points)
        }
        return run
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func nearestAltitude(_ points: [RoutePoint], at t: Date) -> Double? {
        guard !points.isEmpty else { return nil }
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].timestamp < t { lo = mid + 1 } else { hi = mid }
        }
        return points[lo].altitude
    }
}
