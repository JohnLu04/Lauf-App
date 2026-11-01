import SwiftUI
import SwiftData
import MapKit

/// Gespeicherte Routen. Mit `selection` dient die Liste zum Auswählen einer Route für den nächsten Lauf.
struct RoutesView: View {
    var selection: Binding<PlannedRoute?>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedRoute.createdAt, order: .reverse) private var routes: [PlannedRoute]
    @State private var editorRoute: PlannedRoute?
    @State private var showNewRoute = false

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Routen", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    } description: {
                        Text("Plane eine Strecke auf der Karte. Die Route folgt automatisch den Wegen, auf Wunsch als Rundkurs.")
                    } actions: {
                        Button("Route planen") { showNewRoute = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if selection?.wrappedValue != nil {
                            Section {
                                Button("Ohne Route laufen", systemImage: "xmark.circle") {
                                    selection?.wrappedValue = nil
                                    dismiss()
                                }
                            }
                        }
                        Section {
                            ForEach(routes) { route in
                                Button {
                                    if let selection {
                                        selection.wrappedValue = route
                                        dismiss()
                                    } else {
                                        editorRoute = route
                                    }
                                } label: {
                                    RouteRow(route: route, selected: selection?.wrappedValue?.id == route.id)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Löschen", systemImage: "trash", role: .destructive) { delete(route) }
                                    Button("Bearbeiten", systemImage: "pencil") { editorRoute = route }
                                        .tint(.blue)
                                }
                                .contextMenu {
                                    Button("Bearbeiten", systemImage: "pencil") { editorRoute = route }
                                    Button("Löschen", systemImage: "trash", role: .destructive) { delete(route) }
                                }
                            }
                        } footer: {
                            if selection != nil {
                                Text("Tippe auf eine Route, um sie beim nächsten Lauf auf der Karte zu sehen. Zum Bearbeiten nach links wischen.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Routen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selection != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Route", systemImage: "plus") { showNewRoute = true }
                }
            }
            .sheet(isPresented: $showNewRoute) { RouteEditorView() }
            .sheet(item: $editorRoute) { RouteEditorView(route: $0) }
        }
    }

    private func delete(_ route: PlannedRoute) {
        if selection?.wrappedValue?.id == route.id { selection?.wrappedValue = nil }
        context.delete(route)
        try? context.save()
    }
}

struct RouteRow: View {
    let route: PlannedRoute
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            RouteShapeView(path: route.path)
                .frame(width: 64, height: 64)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(route.name).font(.headline)
                Text(Format.distance(route.distance, decimals: 1) + (route.isLoop ? " · Rundkurs" : ""))
                    .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Form der Strecke als Vorschau (ohne Karte), mit grünem Start- und rotem Zielpunkt.
struct RouteShapeView: View {
    let path: [RouteCoordinate]

    var body: some View {
        Canvas { ctx, size in
            guard path.count > 1 else { return }
            // In Meter umrechnen, damit die Form nicht verzerrt ist, und mittig einpassen
            let lat0 = path[0].latitude
            let points = path.map { CGPoint(x: $0.longitude * cos(lat0 * .pi / 180), y: -$0.latitude) }
            let xs = points.map(\.x), ys = points.map(\.y)
            let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
            let inset: CGFloat = 8
            let scale = min((size.width - 2 * inset) / max(maxX - minX, 1e-9),
                            (size.height - 2 * inset) / max(maxY - minY, 1e-9))
            let offset = CGPoint(x: (size.width - (maxX - minX) * scale) / 2, y: (size.height - (maxY - minY) * scale) / 2)
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: offset.x + (p.x - minX) * scale, y: offset.y + (p.y - minY) * scale)
            }
            var line = Path()
            line.addLines(points.map(map))
            ctx.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            let end = map(points.last!), start = map(points.first!)
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(.red))
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 3.5, y: start.y - 3.5, width: 7, height: 7)), with: .color(.green))
        }
        .accessibilityHidden(true)
    }
}
