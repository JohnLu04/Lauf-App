import SwiftUI
import MapKit

/// Pfeilspitze, zeigt nach oben.
struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Einzelner Richtungspfeil auf der Karte. Auf gemeinsam genutzten Abschnitten (Hin- und Rückweg
/// auf derselben Straße) sitzt er rechts neben der Linie, sonst auf ihr.
struct DirectionArrowView: View {
    let arrow: RouteArrow
    /// Drehung der Karte (Grad), damit der Pfeil auch auf gedrehten Karten in Laufrichtung zeigt
    let mapHeading: Double
    var color: Color = .accentColor
    var size: CGFloat = 11

    var body: some View {
        ArrowHead()
            .fill(color)
            .overlay(ArrowHead().stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)))
            .frame(width: size, height: size * 1.1)
            // Erst seitlich versetzen, dann drehen: So liegt der Versatz immer rechts der Laufrichtung
            .offset(x: arrow.isShared ? size * 0.85 : 0)
            .rotationEffect(.degrees(arrow.bearing - mapHeading))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Richtungspfeile als Karteninhalt. Mit `progress` (Navigation) entfallen die Pfeile hinter dem
/// Läufer, die nächsten 500 m sind hervorgehoben, weiter entfernte blasser.
struct RouteArrowsLayer: MapContent {
    let arrows: [RouteArrow]
    let mapHeading: Double
    var color: Color = .accentColor
    var progress: Double?

    var body: some MapContent {
        ForEach(visibleArrows) { arrow in
            Annotation("", coordinate: arrow.coordinate.coordinate, anchor: .center) {
                DirectionArrowView(arrow: arrow, mapHeading: mapHeading, color: color, size: size(for: arrow))
                    .opacity(opacity(for: arrow))
            }
            .annotationTitles(.hidden)
        }
    }

    private var visibleArrows: [RouteArrow] {
        guard let progress else { return arrows }
        return arrows.filter { $0.along > progress + 15 }
    }

    private func isAhead(_ arrow: RouteArrow) -> Bool {
        guard let progress else { return false }
        return arrow.along - progress < 500
    }

    private func size(for arrow: RouteArrow) -> CGFloat { isAhead(arrow) ? 13 : 11 }

    private func opacity(for arrow: RouteArrow) -> Double {
        guard progress != nil else { return 1 }
        return isAhead(arrow) ? 1 : 0.55
    }
}

/// Hält die Pfeile einer Karte aktuell: neu berechnet, wenn sich die Strecke oder der Ausschnitt
/// (Zoom) ändert; die Drehung der Karte wird laufend übernommen.
private struct RouteArrowTracker: ViewModifier {
    let path: [RouteCoordinate]
    @Binding var arrows: [RouteArrow]
    @Binding var heading: Double
    @State private var visible: MKMapRect?

    func body(content: Content) -> some View {
        content
            .onMapCameraChange(frequency: .continuous) { context in
                if abs(context.camera.heading - heading) > 0.5 { heading = context.camera.heading }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visible = context.rect
                update()
            }
            .onChange(of: path) { _, _ in update() }
            .onAppear { update() }
    }

    private func update() {
        arrows = RouteGeometry.arrows(path, visible: visible)
    }
}

extension View {
    /// Berechnet die Richtungspfeile für `path` passend zum Kartenausschnitt (an der `Map` anbringen).
    func routeArrows(for path: [RouteCoordinate], arrows: Binding<[RouteArrow]>, heading: Binding<Double>) -> some View {
        modifier(RouteArrowTracker(path: path, arrows: arrows, heading: heading))
    }
}
