import Foundation
import CoreLocation
import Observation
import AVFoundation

/// Zeichnet einen Lauf per GPS auf: Distanz, Zeit, Pace, Route und Kilometer-Ansagen.
@MainActor
@Observable
final class RunRecorder: NSObject {
    enum State { case idle, running, paused }

    private(set) var state: State = .idle
    private(set) var points: [RoutePoint] = []
    private(set) var distance: Double = 0
    private(set) var elevationGain: Double = 0
    private(set) var currentPace: Double = 0
    private(set) var startDate: Date?
    private(set) var lastLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Fertige Aufzeichnung, die noch gespeichert oder verworfen werden muss.
    private(set) var finishedDraft: RunDraft?
    /// Geplantes Workout, das gerade gelaufen wird (optional).
    private(set) var plannedWorkout: PlannedWorkout?

    /// true, solange der Aufzeichnungsbildschirm angezeigt werden soll.
    var isSessionActive: Bool { state != .idle || finishedDraft != nil }

    var hasLocationPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// GPS-Qualität für die Anzeige.
    var gpsSignalGood: Bool {
        guard let loc = lastLocation else { return false }
        return loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 20
            && abs(loc.timestamp.timeIntervalSinceNow) < 10
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var accumulatedTime: TimeInterval = 0
    @ObservationIgnored private var segmentStart: Date?
    @ObservationIgnored private var segment = 0
    @ObservationIgnored private var lastAccepted: CLLocation?
    @ObservationIgnored private var elevation = ElevationTracker()
    @ObservationIgnored private var announcedKm = 0
    @ObservationIgnored private var lastKmTime: TimeInterval = 0
    @ObservationIgnored private let speech = AVSpeechSynthesizer()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        speech.delegate = self
    }

    // MARK: - Steuerung

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// GPS vorwärmen, damit beim Start schon ein gutes Signal da ist.
    func startPreview() {
        guard hasLocationPermission else { return }
        manager.startUpdatingLocation()
    }

    func stopPreview() {
        guard state == .idle else { return }
        manager.stopUpdatingLocation()
    }

    func start(planned: PlannedWorkout? = nil) {
        guard state == .idle, finishedDraft == nil else { return }
        if authorizationStatus == .notDetermined { requestPermission() }
        reset()
        plannedWorkout = planned
        state = .running
        startDate = Date()
        segmentStart = startDate
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        speak("Aufzeichnung gestartet.")
    }

    func pause() {
        guard state == .running else { return }
        if let segmentStart { accumulatedTime += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        segment += 1
        lastAccepted = nil
        currentPace = 0
        state = .paused
        speak("Pausiert.")
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = Date()
        state = .running
        speak("Weiter geht's.")
    }

    /// Beendet die Aufzeichnung. Danach liegt `finishedDraft` zum Speichern bereit.
    func finish() {
        guard state != .idle else { return }
        if state == .running { pause() }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        finishedDraft = RunDraft(startDate: startDate ?? Date(), endDate: Date(),
                                 movingTime: accumulatedTime, distance: distance,
                                 points: points, plannedWorkoutID: plannedWorkout?.id)
        state = .idle
    }

    /// Nach dem Speichern oder Verwerfen aufrufen.
    func clearDraft() {
        finishedDraft = nil
        reset()
    }

    /// Bewegungszeit (ohne Pausen) zu einem Zeitpunkt – für die Live-Uhr.
    func movingTime(at date: Date = Date()) -> TimeInterval {
        accumulatedTime + (segmentStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    var averagePace: Double {
        let t = movingTime()
        return distance > 10 ? t / (distance / 1000) : 0
    }

    private func reset() {
        points = []
        distance = 0
        elevationGain = 0
        currentPace = 0
        accumulatedTime = 0
        segmentStart = nil
        segment = 0
        lastAccepted = nil
        elevation = ElevationTracker()
        announcedKm = 0
        lastKmTime = 0
        startDate = nil
        plannedWorkout = nil
    }

    // MARK: - GPS-Verarbeitung

    fileprivate func process(_ locations: [CLLocation]) {
        for loc in locations {
            lastLocation = loc
            guard state == .running else { continue }
            // Ungenaue oder veraltete Punkte verwerfen
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 30 else { continue }
            guard abs(loc.timestamp.timeIntervalSinceNow) < 15 else { continue }

            let altitude: Double? = (loc.verticalAccuracy >= 0 && loc.verticalAccuracy <= 20) ? loc.altitude : nil

            if let prev = lastAccepted {
                let d = loc.distance(from: prev)
                let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                if d / dt > 12 { continue }   // unrealistischer Sprung (> 43 km/h)
                if d < 3 { continue }          // GPS-Zittern im Stand ignorieren
                distance += d
            }
            elevation.add(altitude)
            elevationGain = elevation.gain
            lastAccepted = loc
            points.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                     altitude: altitude, timestamp: loc.timestamp, segment: segment))
            updateCurrentPace()
            checkKilometer()
        }
    }

    /// Aktuelle Pace über die letzten ~30 Sekunden.
    private func updateCurrentPace() {
        guard let last = points.last else { return }
        var dist = 0.0
        var earliest = last
        for (a, b) in zip(points.reversed().dropFirst(), points.reversed()) {
            guard a.segment == last.segment, b.segment == last.segment else { break }
            dist += Geo.distance(a, b)
            earliest = a
            if last.timestamp.timeIntervalSince(a.timestamp) >= 30 { break }
        }
        let dt = last.timestamp.timeIntervalSince(earliest.timestamp)
        currentPace = (dist > 20 && dt > 5) ? dt / (dist / 1000) : 0
    }

    private func checkKilometer() {
        let km = Int(distance / 1000)
        guard km > announcedKm else { return }
        announcedKm = km
        let t = movingTime()
        let split = t - lastKmTime
        lastKmTime = t
        speak("\(km) Kilometer. Zeit: \(Format.spokenDuration(t)). Letzter Kilometer: \(Format.spokenDuration(split)).")
    }

    // MARK: - Sprachausgabe

    private func speak(_ text: String) {
        guard UserDefaults.standard.object(forKey: "voiceFeedback") as? Bool ?? true else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        speech.speak(utterance)
    }
}

extension RunRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.process(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.hasLocationPermission { self.startPreview() }
        }
    }
}

extension RunRecorder: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Andere Audio-Apps (Musik, Podcasts) wieder laut stellen
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
