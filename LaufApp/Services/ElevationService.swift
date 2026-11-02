import Foundation

/// Höhenprofil einer Strecke.
struct ElevationProfile: Codable, Hashable {
    /// Strecke entlang der Route (Meter) je Stützpunkt
    var distances: [Double]
    /// Höhe über NN (Meter) je Stützpunkt
    var elevations: [Double]
    var gain: Double
    var loss: Double
    /// Berechnungsverfahren; ältere Profile (nil) werden neu berechnet
    var method: Int?

    var isCurrent: Bool { method == ElevationService.method }

    var series: [RunAnalysis.SeriesPoint] {
        zip(distances, elevations).map { RunAnalysis.SeriesPoint(km: $0 / 1000, value: $1) }
    }
}

/// Höhendaten von Open-Meteo (Copernicus-Höhenmodell, ~90 m Auflösung, kostenlos, ohne Schlüssel).
enum ElevationService {
    static let endpoint = URL(string: "https://api.open-meteo.com/v1/elevation")!
    /// Höchstzahl an Koordinaten pro Anfrage
    static let batchSize = 100
    /// Version der Berechnung (2 = geglättet)
    static let method = 2

    /// Höhenprofil entlang der Strecke (Stützpunkte alle 50 m, bei langen Strecken weiter auseinander).
    static func profile(for path: [RouteCoordinate]) async -> ElevationProfile? {
        guard path.count > 1 else { return nil }
        let length = RouteGeometry.length(path)
        let samples = resample(path, every: max(50, length / 300))
        guard let raw = try? await elevations(samples.map(\.point)), raw.count == samples.count
        else { return nil }
        let elevations = smoothed(raw)
        let (gain, loss) = gainAndLoss(elevations)
        return ElevationProfile(distances: samples.map(\.along), elevations: elevations, gain: gain, loss: loss,
                                method: method)
    }

    /// Höhendienste in der Reihenfolge, in der sie gefragt werden.
    enum Provider: CaseIterable {
        /// Open-Meteo (Copernicus, ~90 m)
        case openMeteo
        /// Valhalla-Server der FOSSGIS (OpenStreetMap-Community), eine Anfrage für die ganze Strecke
        case valhalla
        /// OpenTopoData (EU-DEM 25 m, sonst SRTM 30 m), höchstens eine Anfrage pro Sekunde
        case openTopoData
    }

    /// Höhen für beliebige Punkte. Ist ein Dienst überlastet oder nicht erreichbar, wird der nächste
    /// gefragt; ein ausgefallener Dienst wird danach für einige Minuten übersprungen.
    static func elevations(_ points: [RouteCoordinate]) async throws -> [Double] {
        guard !points.isEmpty else { return [] }
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for provider in await ProviderHealth.shared.ordered() {
            do {
                let heights = try await elevations(points, from: provider)
                guard heights.count == points.count else { throw URLError(.cannotParseResponse) }
                await ProviderHealth.shared.succeeded(provider)
                return heights
            } catch {
                lastError = error
                // Ohne Internet hilft auch kein anderer Dienst
                if (error as? URLError)?.code == .notConnectedToInternet { throw error }
                await ProviderHealth.shared.failed(provider)
            }
        }
        throw lastError
    }

    static func elevations(_ points: [RouteCoordinate], from provider: Provider) async throws -> [Double] {
        switch provider {
        case .openMeteo: try await openMeteo(points)
        case .valhalla: try await valhalla(points)
        case .openTopoData: try await openTopoData(points)
        }
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 10
        request.setValue("LaufApp (github.com/JohnLu04/Lauf-App)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Open-Meteo, in Paketen zu je 100 Punkten.
    private static func openMeteo(_ points: [RouteCoordinate]) async throws -> [Double] {
        var result: [Double] = []
        for start in stride(from: 0, to: points.count, by: batchSize) {
            let batch = points[start..<min(points.count, start + batchSize)]
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: batch.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: batch.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")),
            ]
            struct Response: Decodable { let elevation: [Double] }
            let decoded = try JSONDecoder().decode(Response.self, from: try await send(URLRequest(url: components.url!)))
            guard decoded.elevation.count == batch.count else { throw URLError(.cannotParseResponse) }
            result += decoded.elevation
        }
        return result
    }

    /// Valhalla-Endpunkt `/height`: alle Punkte in einer Anfrage.
    private static func valhalla(_ points: [RouteCoordinate]) async throws -> [Double] {
        var request = URLRequest(url: URL(string: "https://valhalla1.openstreetmap.de/height")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Point: Encodable { let lat: Double; let lon: Double }
        struct Body: Encodable { let shape: [Point]; let range = false }
        request.httpBody = try JSONEncoder().encode(Body(shape: points.map { Point(lat: $0.latitude, lon: $0.longitude) }))
        struct Response: Decodable { let height: [Double?] }
        let decoded = try JSONDecoder().decode(Response.self, from: try await send(request))
        let heights = decoded.height.compactMap { $0 }
        guard heights.count == points.count else { throw URLError(.cannotParseResponse) }
        return heights
    }

    /// OpenTopoData, in Paketen zu je 100 Punkten mit einer Sekunde Abstand (Nutzungsbedingung).
    private static func openTopoData(_ points: [RouteCoordinate]) async throws -> [Double] {
        var result: [Double] = []
        for start in stride(from: 0, to: points.count, by: batchSize) {
            if start > 0 { try await Task.sleep(for: .seconds(1.1)) }
            let batch = points[start..<min(points.count, start + batchSize)]
            var components = URLComponents(string: "https://api.opentopodata.org/v1/eudem25m,srtm30m")!
            components.queryItems = [URLQueryItem(name: "locations", value: batch.map {
                String(format: "%.5f,%.5f", $0.latitude, $0.longitude)
            }.joined(separator: "|"))]
            struct Response: Decodable {
                struct Result: Decodable { let elevation: Double? }
                let results: [Result]
            }
            let decoded = try JSONDecoder().decode(Response.self, from: try await send(URLRequest(url: components.url!)))
            let heights = decoded.results.compactMap(\.elevation)
            guard heights.count == batch.count else { throw URLError(.cannotParseResponse) }
            result += heights
        }
        return result
    }

    /// Gleitender Mittelwert über ±`radius` Stützpunkte. Das Höhenmodell (~90 m Raster) rauscht entlang
    /// von Straßen um einige Meter; ohne Glätten würde jedes Wackeln als Anstieg gezählt.
    static func smoothed(_ values: [Double], radius: Int = 2) -> [Double] {
        guard values.count > 2 * radius else { return values }
        return values.indices.map { i in
            let window = values[max(0, i - radius)...min(values.count - 1, i + radius)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// Anstieg und Gefälle; Schwankungen unter 3 m werden ignoriert.
    static func gainAndLoss(_ elevations: [Double]) -> (gain: Double, loss: Double) {
        var tracker = ElevationTracker(threshold: 3)
        elevations.forEach { tracker.add($0) }
        return (tracker.gain, tracker.loss)
    }

    /// Gleichmäßig verteilte Stützpunkte entlang der Strecke (inklusive Endpunkt).
    static func resample(_ path: [RouteCoordinate], every step: Double) -> [(point: RouteCoordinate, along: Double)] {
        guard let first = path.first else { return [] }
        var samples: [(point: RouteCoordinate, along: Double)] = [(first, 0)]
        var along = 0.0, next = step
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            while d > 0, next <= along + d {
                let t = (next - along) / d
                samples.append((RouteCoordinate(latitude: a.latitude + t * (b.latitude - a.latitude),
                                                longitude: a.longitude + t * (b.longitude - a.longitude)), next))
                next += step
            }
            along += d
        }
        if let last = path.last, along - (samples.last?.along ?? 0) > 1 { samples.append((last, along)) }
        return samples
    }
}

/// Merkt sich ausgefallene Höhendienste, damit nicht jede Anfrage erst auf sie wartet.
private actor ProviderHealth {
    static let shared = ProviderHealth()

    private var failedAt: [ElevationService.Provider: Date] = [:]
    /// So lange wird ein ausgefallener Dienst übersprungen
    private let pause: TimeInterval = 10 * 60

    /// Funktionierende Dienste zuerst, kürzlich ausgefallene am Ende (falls alle ausgefallen sind).
    func ordered() -> [ElevationService.Provider] {
        let all = ElevationService.Provider.allCases
        let healthy = all.filter { failedAt[$0].map { Date().timeIntervalSince($0) > pause } ?? true }
        return healthy + all.filter { !healthy.contains($0) }
    }

    func failed(_ provider: ElevationService.Provider) { failedAt[provider] = Date() }

    func succeeded(_ provider: ElevationService.Provider) { failedAt[provider] = nil }
}
