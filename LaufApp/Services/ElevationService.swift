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

    /// Höhen für beliebige Punkte (in Paketen zu je 100).
    static func elevations(_ points: [RouteCoordinate]) async throws -> [Double] {
        var result: [Double] = []
        for start in stride(from: 0, to: points.count, by: batchSize) {
            let batch = points[start..<min(points.count, start + batchSize)]
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: batch.map { String(format: "%.5f", $0.latitude) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: batch.map { String(format: "%.5f", $0.longitude) }.joined(separator: ",")),
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 15)
            request.setValue("LaufApp (github.com/JohnLu04/Lauf-App)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            struct Response: Decodable { let elevation: [Double] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard decoded.elevation.count == batch.count else { throw URLError(.cannotParseResponse) }
            result += decoded.elevation
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
