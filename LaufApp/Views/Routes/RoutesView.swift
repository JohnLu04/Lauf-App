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
    @State private var showSuggest = false
    @State private var showFromRun = false
    @State private var renameRoute: PlannedRoute?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Routen", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    } description: {
                        Text("Lass dir Rundkurse durch Parks und Grünflächen in deiner Nähe vorschlagen oder plane selbst eine Strecke auf der Karte.")
                    } actions: {
                        VStack(spacing: 10) {
                            Button("Rundkurs vorschlagen", systemImage: "sparkle.magnifyingglass") { showSuggest = true }
                                .buttonStyle(.borderedProminent)
                            Button("Selbst planen", systemImage: "hand.tap") { showNewRoute = true }
                                .buttonStyle(.bordered)
                            Button("Aus gelaufener Strecke", systemImage: "figure.run") { showFromRun = true }
                                .buttonStyle(.bordered)
                        }
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
                                    Button("Umbenennen", systemImage: "character.cursor.ibeam") {
                                        newName = route.name
                                        renameRoute = route
                                    }
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
                    Menu {
                        Button("Rundkurs vorschlagen", systemImage: "sparkle.magnifyingglass") { showSuggest = true }
                        Button("Selbst planen", systemImage: "hand.tap") { showNewRoute = true }
                        Button("Aus gelaufener Strecke", systemImage: "figure.run") { showFromRun = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Route")
                }
            }
            .sheet(isPresented: $showNewRoute) { RouteEditorView() }
            .sheet(isPresented: $showSuggest) {
                RouteSuggestView(selection: selection) {
                    // Beim Auswählen für den Lauf direkt zurück zum Aufnahme-Tab
                    if selection != nil { dismiss() }
                }
            }
            .sheet(item: $editorRoute) { RouteEditorView(route: $0) }
            .sheet(isPresented: $showFromRun) { RunRoutePicker() }
            .alert("Route umbenennen", isPresented: Binding(get: { renameRoute != nil }, set: { if !$0 { renameRoute = nil } })) {
                TextField("Name", text: $newName)
                Button("Sichern") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let renameRoute, !trimmed.isEmpty { renameRoute.name = trimmed; try? context.save() }
                    renameRoute = nil
                }
                Button("Abbrechen", role: .cancel) { renameRoute = nil }
            }
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
                HStack(spacing: 6) {
                    Text(Format.distance(route.distance, decimals: 1) + (route.isLoop ? " · Rundkurs" : ""))
                    if route.hasElevation { ElevationLabel(gain: route.elevationGain) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        // Ältere Routen ohne (oder mit veraltetem) Höhenprofil nachträglich ergänzen
        .task(id: route.id) {
            guard route.elevation?.isCurrent != true, let profile = await ElevationService.profile(for: route.path)
            else { return }
            route.elevation = profile
            try? route.modelContext?.save()
        }
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

/// Gelaufene Strecke auswählen und als Route speichern.
struct RunRoutePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var selected: Run?
    @State private var name = ""

    /// Läufe mit GPS-Strecke (eingetragene Läufe stammen schon aus einer Route)
    private var candidates: [Run] { runs.filter { !$0.isManual && !$0.routeData.isEmpty } }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView("Keine Läufe mit Strecke", systemImage: "map",
                                           description: Text("Aufgezeichnete oder importierte Läufe mit GPS erscheinen hier."))
                } else {
                    List(candidates) { run in
                        Button {
                            name = PlannedRoute.defaultName(for: run)
                            selected = run
                        } label: {
                            HStack(spacing: 12) {
                                RouteShapeView(path: run.route.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude) })
                                    .frame(width: 48, height: 48)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.title).font(.subheadline.weight(.semibold))
                                    Text("\(run.startDate.formatted(date: .abbreviated, time: .omitted)) · \(Format.distance(run.distance, decimals: 1))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Aus gelaufener Strecke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .alert("Als Route speichern", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                TextField("Name", text: $name)
                Button("Sichern") { save() }
                Button("Abbrechen", role: .cancel) { selected = nil }
            }
        }
    }

    private func save() {
        guard let run = selected else { return }
        selected = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let route = PlannedRoute.fromRun(run, name: trimmed.isEmpty ? PlannedRoute.defaultName(for: run) : trimmed) else { return }
        context.insert(route)
        try? context.save()
        dismiss()
    }
}
