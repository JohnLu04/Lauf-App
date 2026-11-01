import Foundation
import CoreLocation
import Observation
import AVFoundation

/// Zeichnet einen Lauf per GPS auf: Distanz, Zeit, Pace, Route und Kilometer-Ansagen.
/// Bei strukturierten Workouts führt er per Sprache durch die Abschnitte und meldet Abweichungen von der Zielpace.
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
    /// Aktueller Abschnitt des geplanten Workouts
    private(set) var stepIndex = 0

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
    @ObservationIgnored private var stepStartDistance: Double = 0
    @ObservationIgnored private var stepStartTime: TimeInterval = 0
    @ObservationIgnored private var lastPaceAlert: TimeInterval = 0
    @ObservationIgnored private var announcedRemaining = false
    @ObservationIgnored private var ticker: Timer?

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
        if let first = currentStep { announce(first) }
        startTicker()
    }

    func pause() {
        guard state == .running else { return }
        if let segmentStart { accumulatedTime += Date().timeIntervalSince(segmentStart) }
        segmentStart = nil
        segment += 1
        lastAccepted = nil
        currentPace = 0
        state = .paused
        ticker?.invalidate()
        speak("Pausiert.")
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = Date()
        state = .running
        startTicker()
        speak("Weiter geht's.")
    }

    /// Beendet die Aufzeichnung. Danach liegt `finishedDraft` zum Speichern bereit.
    func finish() {
        guard state != .idle else { return }
        if state == .running { pause() }
        ticker?.invalidate()
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
        stepIndex = 0
        stepStartDistance = 0
        stepStartTime = 0
        lastPaceAlert = 0
        announcedRemaining = false
        ticker?.invalidate()
    }

    // MARK: - Geführtes Workout

    var steps: [WorkoutStep] { plannedWorkout?.steps ?? [] }
    var currentStep: WorkoutStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var nextStep: WorkoutStep? { steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1] : nil }
    var isWorkoutComplete: Bool { !steps.isEmpty && stepIndex >= steps.count }

    /// Fortschritt im aktuellen Abschnitt (0…1).
    func stepProgress(at date: Date = Date()) -> Double {
        guard let step = currentStep else { return 1 }
        if let d = step.distance, d > 0 { return min(1, (distance - stepStartDistance) / d) }
        if let t = step.duration, t > 0 { return min(1, (movingTime(at: date) - stepStartTime) / t) }
        return 0
    }

    /// Verbleibende Strecke oder Zeit im aktuellen Abschnitt, z.B. "350 m" oder "1:20".
    func stepRemainingText(at date: Date = Date()) -> String {
        guard let step = currentStep else { return "" }
        if let d = step.distance {
            let rest = max(0, d - (distance - stepStartDistance))
            return rest < 1000 ? "\(Int(rest)) m" : Format.distance(rest, decimals: 2)
        }
        if let t = step.duration { return Format.duration(max(0, t - (movingTime(at: date) - stepStartTime))) }
        return ""
    }

    /// Springt zum nächsten Abschnitt (z.B. wenn die Pause kürzer sein soll).
    func skipStep() {
        guard currentStep != nil else { return }
        advanceStep()
    }

    private func startTicker() {
        ticker?.invalidate()
        guard !steps.isEmpty else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStep() }
        }
    }

    private func updateStep() {
        guard state == .running, let step = currentStep else { return }
        let t = movingTime()
        let inStepDistance = distance - stepStartDistance
        let inStepTime = t - stepStartTime
        if let d = step.distance, inStepDistance >= d { advanceStep(); return }
        if let dur = step.duration, inStepTime >= dur { advanceStep(); return }

        if !announcedRemaining {
            if let d = step.distance, d >= 600, step.kind != .cooldown, d - inStepDistance <= 200 {
                announcedRemaining = true
                speak("Noch 200 Meter.")
            } else if let dur = step.duration, dur >= 60, dur - inStepTime <= 10 {
                announcedRemaining = true
                speak("Noch 10 Sekunden.")
            }
        }
        checkPace(step, inStepTime: inStepTime, now: t)
    }

    private func advanceStep() {
        stepIndex += 1
        stepStartDistance = distance
        stepStartTime = movingTime()
        lastPaceAlert = stepStartTime
        announcedRemaining = false
        if let step = currentStep {
            announce(step)
        } else {
            speak("Workout geschafft, super gemacht! Du kannst jetzt beenden oder locker weiterlaufen.")
        }
    }

    private func announce(_ step: WorkoutStep) {
        var text = "\(step.label). \(spokenAmount(step))"
        if let fast = step.paceFast, let slow = step.paceSlow {
            text += slow - fast < 15
                ? " im Tempo \(Format.spokenPace((fast + slow) / 2))."
                : ", locker zwischen \(Format.pace(fast).replacingOccurrences(of: ":", with: " Minuten ")) und \(Format.spokenPace(slow))."
        } else if step.kind == .run {
            text += ", zügig."
        } else {
            text += "."
        }
        if step.kind == .recovery, let next = nextStep {
            text += " Danach: \(next.label)."
        }
        speak(text)
    }

    private func spokenAmount(_ step: WorkoutStep) -> String {
        if let d = step.distance {
            return d < 1000 ? "\(Int(d)) Meter" : "\(Format.kilometers(d, decimals: d.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1)) Kilometer"
        }
        if let t = step.duration {
            return t < 60 ? "\(Int(t)) Sekunden" : Format.spokenDuration(t)
        }
        return ""
    }

    /// Meldet sich höchstens alle 45 s, wenn die Pace außerhalb des Zielbereichs liegt.
    /// Bei lockeren Bereichen (breiter als 15 s) nur, wenn man zu schnell ist.
    private func checkPace(_ step: WorkoutStep, inStepTime: TimeInterval, now: TimeInterval) {
        guard let fast = step.paceFast, let slow = step.paceSlow, currentPace > 0,
              inStepTime > 20, now - lastPaceAlert > 45 else { return }
        let isEasy = slow - fast >= 15
        if currentPace < fast * 0.98 {
            lastPaceAlert = now
            speak(isEasy ? "Etwas langsamer, ganz locker bleiben." : "Etwas langsamer. Ziel: \(Format.spokenPace((fast + slow) / 2)).")
        } else if !isEasy, currentPace > slow * 1.02 {
            lastPaceAlert = now
            speak("Etwas schneller. Ziel: \(Format.spokenPace((fast + slow) / 2)).")
        }
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
            updateStep()
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
