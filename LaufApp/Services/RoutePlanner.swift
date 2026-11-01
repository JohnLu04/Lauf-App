import Foundation
import MapKit

/// Verbindet zwei Punkte entlang von Fußwegen (Apple Karten). Ohne Netz oder ohne gefundenen
/// Weg wird die Luftlinie verwendet.
enum RoutePlanner {
    struct Segment {
        var coordinates: [RouteCoordinate]
        /// false, wenn kein Weg gefunden wurde und die Luftlinie verwendet wird
        var followsPaths: Bool
    }

    static func segment(from start: RouteCoordinate, to end: RouteCoordinate, followPaths: Bool) async -> Segment {
        let straight = Segment(coordinates: [start, end], followsPaths: false)
        guard followPaths, start.distance(to: end) > 5 else { return straight }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return straight }
            let polyline = route.polyline
            var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
            // Die Wegsuche beginnt am nächsten Weg; damit die Linie lückenlos ist, werden
            // die getippten Punkte vorne und hinten angehängt.
            var result = [start] + coords.map(RouteCoordinate.init) + [end]
            result = result.reduce(into: []) { acc, c in
                if let last = acc.last, last.distance(to: c) < 1 { return }
                acc.append(c)
            }
            return Segment(coordinates: result, followsPaths: true)
        } catch {
            return straight
        }
    }
}
