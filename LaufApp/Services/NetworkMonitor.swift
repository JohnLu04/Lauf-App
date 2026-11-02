import Foundation
import Network
import Observation

/// Beobachtet, ob eine Internetverbindung besteht (für verständliche Fehlermeldungen).
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        #if DEBUG
        // Zum Testen im Simulator: App mit dem Argument -simulateOffline starten
        if Self.simulateOffline {
            isOnline = false
            return
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    nonisolated static var simulateOffline: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-simulateOffline")
        #else
        false
        #endif
    }

    /// Ist der Fehler auf eine fehlende oder gestörte Verbindung zurückzuführen?
    nonisolated static func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error, isNetworkError(underlying) { return true }
        // MapKit meldet Verbindungsprobleme als Serverfehler bzw. "Ort unbekannt"
        if nsError.domain == MKErrorDomainName {
            return [1 /* unknown */, 2 /* serverFailure */, 3 /* loadingThrottled */].contains(nsError.code)
        }
        return false
    }

    static let message = "Etwas ist fehlgeschlagen. Überprüfe deine Internetverbindung und versuch es noch einmal."
}

/// Name der MapKit-Fehlerdomäne (ohne MapKit importieren zu müssen)
private let MKErrorDomainName = "MKErrorDomain"
