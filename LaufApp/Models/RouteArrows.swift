import Foundation
import MapKit

/// Richtungspfeil auf einer Strecke.
struct RouteArrow: Identifiable, Hashable {
    /// Nummer des Pfeils entlang der Strecke (bleibt beim Verschieben der Karte gleich)
    var id: Int
    var coordinate: RouteCoordinate
    /// Laufrichtung in Grad (0 = Norden, 90 = Osten)
    var bearing: Double
    /// Meter entlang der Strecke
    var along: Double
    /// Verläuft hier noch ein anderer Teil der Strecke (z. B. der Rückweg auf derselben Straße)?
    /// Dann wird der Pfeil rechts neben die Linie gesetzt – Hin- und Rückweg liegen so auf
    /// verschiedenen Seiten, wie zwei Fahrspuren.
    var isShared: Bool
}

extension RouteGeometry {
    /// Abstand zwischen den Pfeilen passend zum sichtbaren Ausschnitt (etwa 7 Pfeile über die Breite).
    static func arrowSpacing(visibleWidth meters: Double) -> Double {
        let raw = meters / 7
        return [50.0, 100, 200, 250, 500, 1000, 2000, 5000, 10_000, 20_000].first { $0 >= raw } ?? 20_000
    }

    /// Richtungspfeile in regelmäßigen Abständen. Mit `visible` nur Pfeile im (etwas vergrößerten)
    /// Kartenausschnitt; der Abstand richtet sich dann nach dessen Breite, sonst nach der Größe der Strecke.
    /// Mit `count` genau so viele Pfeile, gleichmäßig verteilt (z. B. für kleine Vorschauen).
    static func arrows(_ path: [RouteCoordinate], visible: MKMapRect? = nil, count fixedCount: Int? = nil,
                       maxCount: Int = 60) -> [RouteArrow] {
        guard path.count > 1 else { return [] }
        // Lokal eben rechnen (Meter), ausreichend genau für Laufstrecken
        let lat0 = path[0].latitude, lon0 = path[0].longitude
        let mx = 111_320.0 * cos(lat0 * .pi / 180), my = 110_540.0
        let xy = path.map { (x: ($0.longitude - lon0) * mx, y: ($0.latitude - lat0) * my) }
        var cumulative = [0.0]
        for i in 1..<xy.count {
            cumulative.append(cumulative[i - 1] + hypot(xy[i].x - xy[i - 1].x, xy[i].y - xy[i - 1].y))
        }
        let total = cumulative.last ?? 0
        guard total > 20 else { return [] }

        let width: Double
        if let visible {
            width = visible.width / MKMapPointsPerMeterAtLatitude(lat0)
        } else {
            let xs = xy.map(\.x), ys = xy.map(\.y)
            width = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        }
        let spacing = arrowSpacing(visibleWidth: max(width, 100))
        let count = fixedCount ?? max(1, Int(total / spacing))
        let step = total / Double(count)

        /// Punkt (Meter) bei einer Strecke entlang des Wegs
        func point(at s: Double) -> (x: Double, y: Double) {
            let s = min(max(s, 0), total)
            var lo = 0, hi = cumulative.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if cumulative[mid] <= s { lo = mid } else { hi = mid }
            }
            let length = cumulative[hi] - cumulative[lo]
            let t = length > 0 ? (s - cumulative[lo]) / length : 0
            return (xy[lo].x + t * (xy[hi].x - xy[lo].x), xy[lo].y + t * (xy[hi].y - xy[lo].y))
        }

        // Sichtbarer Bereich mit Rand, damit beim Verschieben keine Lücken am Rand entstehen
        let area = visible.map { $0.insetBy(dx: -$0.width * 0.3, dy: -$0.height * 0.3) }

        /// Liegt ein Abschnitt, der entlang der Strecke mindestens 60 m entfernt ist, näher als 20 m?
        func isShared(_ p: (x: Double, y: Double), along s: Double) -> Bool {
            for i in 0..<(xy.count - 1) {
                if cumulative[i + 1] > s - 60 && cumulative[i] < s + 60 { continue }
                let a = xy[i], b = xy[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                let t = length2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2)) : 0
                if hypot(a.x + t * dx - p.x, a.y + t * dy - p.y) < 20 { return true }
            }
            return false
        }

        var result: [RouteArrow] = []
        for n in 0..<count {
            let s = (Double(n) + 0.5) * step
            let p = point(at: s)
            let coordinate = RouteCoordinate(latitude: lat0 + p.y / my, longitude: lon0 + p.x / mx)
            if let area, !area.contains(MKMapPoint(coordinate.coordinate)) { continue }
            // Richtung über ±12 m geglättet (GPS-Zacken und kurze Knicke)
            let a = point(at: s - 12), b = point(at: s + 12)
            let bearing = atan2(b.x - a.x, b.y - a.y) * 180 / .pi
            result.append(RouteArrow(id: n, coordinate: coordinate, bearing: bearing, along: s,
                                     isShared: isShared(p, along: s)))
            if result.count >= maxCount { break }
        }
        return result
    }
}
