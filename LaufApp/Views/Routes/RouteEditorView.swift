import SwiftUI
import SwiftData
import MapKit

/// Route auf der Karte planen: Tippen setzt Wegpunkte, die entlang von Wegen verbunden werden.
struct RouteEditorView: View {
    /// Zu bearbeitende Route; nil = neue Route
    var route: PlannedRoute?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true }) private var plans: [TrainingPlan]

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var waypoints: [RouteCoordinate] = []
    /// segments[i] verbindet waypoints[i] und waypoints[i + 1]
    @State private var segments: [RoutePlanner.Segment] = []
    @State private var followPaths = true
    @State private var pendingCalculations = 0
    @State private var showSave = false
    @State private var name = ""
    @State private var loaded = false
    @State private var elevation: ElevationProfile?
    @State private var isLoadingElevation = false

    private var path: [RouteCoordinate] {
        guard let first = waypoints.first else { return [] }
        return segments.reduce([first]) { acc, seg in acc + seg.coordinates.dropFirst() }
    }

    private var distance: Double { RouteGeometry.length(path) }

    private var isLoop: Bool {
        guard waypoints.count > 2, let first = waypoints.first, let last = waypoints.last else { return false }
        return first.distance(to: last) < 50
    }

    /// Geschätzte Dauer mit lockerer Pace aus dem Trainingsplan, sonst 6:00 /km
    private var estimatedTime: TimeInterval {
        let pace = plans.first.map { p in
            let paces = VDOT.paces(vdot: p.formVDOT)
            return (paces.easyFast + paces.easySlow) / 2
        } ?? 360
        return distance / 1000 * pace
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    if path.count > 1 {
                        MapPolyline(coordinates: path.map(\.coordinate))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    // Bei Rundkursen liegt das Ziel auf dem Start: dann nur den Startpunkt zeigen
                    ForEach(Array(waypoints.enumerated()).filter { !(isLoop && $0.offset == waypoints.count - 1) }
                        .reversed(), id: \.offset) { index, point in
                        Annotation("", coordinate: point.coordinate, anchor: .center) {
                            waypointMarker(index: index)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        addWaypoint(RouteCoordinate(coordinate))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .overlay(alignment: .top) {
                if waypoints.isEmpty {
                    hint("Tippe auf die Karte, um den Startpunkt zu setzen.")
                } else if waypoints.count == 1 {
                    hint("Tippe weitere Punkte, die Route folgt den Wegen.")
                }
            }
            .navigationTitle(route == nil ? "Neue Route" : "Route bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if name.isEmpty { name = defaultName }
                        showSave = true
                    }
                    .bold()
                    .disabled(waypoints.count < 2 || pendingCalculations > 0)
                }
            }
            .alert("Route sichern", isPresented: $showSave) {
                TextField("Name", text: $name)
                Button("Sichern") { save() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\(Format.distance(distance, decimals: 1)) · ca. \(Format.duration(estimatedTime))"
                     + (elevation.map { " · ↑ \(Int($0.gain.rounded())) m" } ?? ""))
            }
            .onAppear(perform: load)
            // Höhenprofil neu berechnen, sobald sich die Strecke nicht mehr ändert
            .task(id: elevationKey) { await updateElevation() }
        }
    }

    private var elevationKey: String {
        pendingCalculations > 0 ? "rechnet" : "\(path.count)-\(Int(distance))-\(path.first?.latitude ?? 0)"
    }

    private func updateElevation() async {
        guard pendingCalculations == 0, path.count > 1 else {
            if path.count < 2 { elevation = nil }
            return
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        isLoadingElevation = true
        let profile = await ElevationService.profile(for: path)
        guard !Task.isCancelled else { return }
        elevation = profile
        isLoadingElevation = false
    }

    // MARK: - Bedienung

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.distance(distance, decimals: 2))
                        .font(.title2.bold().monospacedDigit())
                    HStack(spacing: 8) {
                        Text(waypoints.count < 2 ? "Noch keine Strecke" : "ca. \(Format.duration(estimatedTime))\(isLoop ? " · Rundkurs" : "")")
                        if waypoints.count >= 2, let elevation {
                            ElevationLabel(gain: elevation.gain, loss: isLoop ? nil : elevation.loss)
                        } else if isLoadingElevation {
                            Text("Höhe …")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if pendingCalculations > 0 { ProgressView() }
                Toggle("Wegen folgen", isOn: $followPaths)
                    .toggleStyle(.button)
                    .font(.caption.bold())
                    .onChange(of: followPaths) { _, _ in recalculateAll() }
            }
            if waypoints.count >= 2, let elevation, elevation.elevations.count > 2 {
                ElevationMiniChart(profile: elevation)
                    .frame(height: 44)
            }
            HStack(spacing: 8) {
                controlButton("Rückgängig", "arrow.uturn.backward", disabled: waypoints.isEmpty, action: undo)
                controlButton("Rundkurs", "arrow.triangle.2.circlepath", disabled: waypoints.count < 2 || isLoop, action: closeLoop)
                controlButton("Umkehren", "arrow.left.arrow.right", disabled: waypoints.count < 2, action: reverse)
                controlButton("Löschen", "trash", disabled: waypoints.isEmpty) {
                    waypoints = []
                    segments = []
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func controlButton(_ title: String, _ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private func waypointMarker(index: Int) -> some View {
        let isStart = index == 0
        let isEnd = index == waypoints.count - 1 && index > 0
        let size: CGFloat = isStart || isEnd ? 16 : 10
        return Circle()
            .fill(isStart ? Color.green : (isEnd ? Color.red : Color.white))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(isStart || isEnd ? Color.white : Color.accentColor, lineWidth: 2))
            .shadow(radius: 1)
    }

    private var defaultName: String {
        "\(isLoop ? "Rundkurs" : "Route") \(Format.distance(distance, decimals: 1))"
    }

    // MARK: - Wegpunkte

    private func addWaypoint(_ point: RouteCoordinate) {
        waypoints.append(point)
        guard waypoints.count > 1 else { return }
        let start = waypoints[waypoints.count - 2]
        // Sofort Luftlinie zeigen, dann durch den Weg ersetzen
        segments.append(RoutePlanner.Segment(coordinates: [start, point], followsPaths: false))
        calculate(index: segments.count - 1, from: start, to: point)
    }

    private func calculate(index: Int, from start: RouteCoordinate, to end: RouteCoordinate) {
        pendingCalculations += 1
        let follow = followPaths
        Task {
            let segment = await RoutePlanner.segment(from: start, to: end, followPaths: follow)
            pendingCalculations -= 1
            // Nur übernehmen, wenn sich die Wegpunkte inzwischen nicht geändert haben
            guard index < segments.count, waypoints[index] == start, waypoints[index + 1] == end,
                  follow == followPaths else { return }
            segments[index] = segment
        }
    }

    private func recalculateAll() {
        segments = zip(waypoints, waypoints.dropFirst()).map { RoutePlanner.Segment(coordinates: [$0, $1], followsPaths: false) }
        for (i, (a, b)) in zip(waypoints, waypoints.dropFirst()).enumerated() {
            calculate(index: i, from: a, to: b)
        }
    }

    private func undo() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        if !segments.isEmpty { segments.removeLast() }
    }

    private func closeLoop() {
        guard let first = waypoints.first else { return }
        addWaypoint(first)
    }

    private func reverse() {
        waypoints.reverse()
        segments = segments.reversed().map { RoutePlanner.Segment(coordinates: $0.coordinates.reversed(), followsPaths: $0.followsPaths) }
    }

    // MARK: - Laden und Sichern

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let route else { return }
        name = route.name
        followPaths = route.followsPaths
        waypoints = route.waypoints
        recalculateAll()
        if let rect = boundingRect(route.path) { position = .rect(rect) }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? defaultName : trimmed
        if let route {
            route.name = finalName
            route.waypoints = waypoints
            route.path = path
            route.followsPaths = followPaths
            route.elevation = elevation   // nach `path`, weil das Setzen des Verlaufs das Profil zurücksetzt
        } else {
            let route = PlannedRoute(name: finalName, waypoints: waypoints, path: path, followsPaths: followPaths)
            route.elevation = elevation
            context.insert(route)
        }
        try? context.save()
        dismiss()
    }
}

/// Kartenausschnitt, der alle Punkte enthält (mit etwas Rand).
func boundingRect(_ path: [RouteCoordinate]) -> MKMapRect? {
    guard !path.isEmpty else { return nil }
    let rect = path.map { MKMapPoint($0.coordinate) }.reduce(MKMapRect.null) { r, p in
        r.union(MKMapRect(origin: p, size: MKMapSize(width: 1, height: 1)))
    }
    return rect.insetBy(dx: -rect.width * 0.2 - 300, dy: -rect.height * 0.2 - 300)
}
