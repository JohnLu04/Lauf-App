import SwiftUI
import MapKit

/// Karte mit der gelaufenen Strecke, Start- (grün) und Zielpunkt (rot).
struct RouteMapView: View {
    private let segments: [[CLLocationCoordinate2D]]
    private let interactive: Bool

    init(points: [RoutePoint], interactive: Bool = false) {
        self.segments = RunAnalysis.segments(points).map { $0.map(\.coordinate) }
        self.interactive = interactive
    }

    var body: some View {
        if segments.reduce(0, { $0 + $1.count }) < 2 {
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: "map")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        } else {
            Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
                ForEach(segments.indices, id: \.self) { i in
                    MapPolyline(coordinates: segments[i])
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let start = segments.first?.first {
                    Annotation("Start", coordinate: start, anchor: .center) { marker(.green) }
                        .annotationTitles(.hidden)
                }
                if let end = segments.last?.last {
                    Annotation("Ziel", coordinate: end, anchor: .center) { marker(.red) }
                        .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(interactive)
        }
    }

    private func marker(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}
