import SwiftUI
import SwiftData
import MapKit

/// Rundkurse in Wunschdistanz in der Umgebung vorschlagen lassen (bevorzugt durch Grünflächen).
struct RouteSuggestView: View {
    /// Wenn gesetzt, wird die gespeicherte Route direkt für den nächsten Lauf ausgewählt
    var selection: Binding<PlannedRoute?>?
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RunRecorder.self) private var recorder
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true }) private var plans: [TrainingPlan]

    @State private var targetKm = 5.0
    @AppStorage("avoidClimbs") private var avoidClimbs = false
    @AppStorage("preferWater") private var preferWater = false
    /// Hinweis unter den Vorschlägen (z. B. keine Gewässer gefunden)
    @State private var note: String?
    @State private var showNetworkError = false
    @State private var suggestions: [LoopSuggestion] = []
    @State private var selectedID: UUID?
    @State private var status: String?
    @State private var isSearching = false
    @State private var source: GreenSpaceFinder.Source?
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchTask: Task<Void, Never>?

    private var start: RouteCoordinate? { recorder.lastLocation.map { RouteCoordinate($0.coordinate) } }
    private var selected: LoopSuggestion? { suggestions.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                    .frame(maxHeight: .infinity)
                panel
            }
            .navigationTitle("Rundkurs vorschlagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .onAppear {
                recorder.startPreview()
                // Wunschdistanz aus dem heutigen Training übernehmen
                if let workout = plans.first?.workout(on: .now), workout.kind != .race {
                    targetKm = max(1, (workout.distance / 500).rounded() / 2)
                }
            }
            .onDisappear { searchTask?.cancel() }
            .alert("Routenerstellung fehlgeschlagen", isPresented: $showNetworkError) {
                Button("Erneut versuchen") { search() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(NetworkMonitor.message)
            }
        }
    }

    // MARK: - Karte

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(suggestions) { suggestion in
                if suggestion.id != selectedID {
                    MapPolyline(coordinates: suggestion.path.map(\.coordinate))
                        .stroke(Color.gray.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            if let selected {
                MapPolyline(coordinates: selected.path.map(\.coordinate))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapControls { MapUserLocationButton() }
    }

    // MARK: - Bedienung

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wunschdistanz").font(.subheadline)
                Spacer()
                Stepper(value: $targetKm, in: 1...42, step: 0.5) {
                    Text(Format.distance(targetKm * 1000, decimals: 1)).font(.headline.monospacedDigit())
                }
                .fixedSize()
            }
            Toggle(isOn: $avoidClimbs) {
                Label("Höhenmeter meiden", systemImage: "mountain.2")
                    .font(.subheadline)
            }
            Toggle(isOn: $preferWater) {
                Label("Am Wasser entlang", systemImage: "water.waves")
                    .font(.subheadline)
            }
            HStack(spacing: 6) {
                ForEach([3.0, 5, 8, 10, 15], id: \.self) { km in
                    Button("\(Int(km)) km") { targetKm = km }
                        .buttonStyle(.bordered)
                        .tint(targetKm == km ? .accentColor : .secondary)
                        .controlSize(.small)
                }
            }

            if suggestions.isEmpty {
                Button {
                    search()
                } label: {
                    HStack {
                        Label(isSearching ? (status ?? "Suche …") : "Vorschläge suchen", systemImage: "sparkle.magnifyingglass")
                        Spacer()
                        if isSearching { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || start == nil)
                if start == nil {
                    Text("Standort wird ermittelt …").font(.caption).foregroundStyle(.secondary)
                } else if let status, !isSearching {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if let profile = selected?.elevation, profile.elevations.count > 2 {
                    ElevationMiniChart(profile: profile)
                        .frame(height: 40)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                }
                if let note {
                    Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Neu suchen", systemImage: "arrow.clockwise") { search() }
                        .buttonStyle(.bordered)
                        .disabled(isSearching)
                    Spacer()
                    Button(selection != nil ? "Speichern & wählen" : "Route speichern", systemImage: "square.and.arrow.down") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
                }
            }

            if source == .openStreetMap {
                Text("Grünflächen: © OpenStreetMap-Mitwirkende")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .onChange(of: targetKm) { _, _ in
            // Andere Distanz: alte Vorschläge passen nicht mehr
            if !suggestions.isEmpty { suggestions = []; selectedID = nil; status = nil }
        }
        .onChange(of: avoidClimbs) { _, _ in
            if !suggestions.isEmpty { suggestions = []; selectedID = nil; status = nil }
        }
        .onChange(of: preferWater) { _, _ in
            if !suggestions.isEmpty { suggestions = []; selectedID = nil; status = nil }
        }
    }

    private func suggestionCard(_ suggestion: LoopSuggestion) -> some View {
        let isSelected = suggestion.id == selectedID
        return Button {
            selectedID = suggestion.id
            if let rect = boundingRect(suggestion.path) { withAnimation { position = .rect(rect) } }
        } label: {
            HStack(spacing: 10) {
                RouteShapeView(path: suggestion.path)
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Format.distance(suggestion.distance, decimals: 1)).font(.headline.monospacedDigit())
                        if let elevation = suggestion.elevation {
                            ElevationLabel(gain: elevation.gain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(suggestion.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(width: 130, alignment: .leading)
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Suche und Speichern

    private func search() {
        guard let start else { return }
        searchTask?.cancel()
        // Ohne Verbindung gar nicht erst suchen (sonst erst nach der Wartezeit eine Meldung)
        guard NetworkMonitor.shared.isOnline else {
            status = nil
            showNetworkError = true
            return
        }
        let target = targetKm * 1000
        suggestions = []
        selectedID = nil
        note = nil
        isSearching = true
        status = "Suche Parks und Grünflächen …"
        searchTask = Task {
            let found = await GreenSpaceFinder.find(near: start, radius: target * 0.45)
            source = found.source
            let water = found.result.water
            let search = await LoopGenerator.suggestions(start: start, target: target, spaces: found.result.spaces,
                                                         avoidClimbs: avoidClimbs, water: water,
                                                         preferWater: preferWater) { text in
                status = text
            }
            let result = search.suggestions
            guard !Task.isCancelled else { return }
            isSearching = false
            if search.networkFailed, result.isEmpty {
                status = nil
                showNetworkError = true
                return
            }
            if search.networkFailed {
                note = "Einige Runden konnten wegen der Internetverbindung nicht berechnet werden."
            }
            suggestions = result
            selectedID = result.first?.id
            if let rect = boundingRect(result.flatMap(\.path)) {
                withAnimation { position = .rect(rect) }
            }
            status = result.isEmpty
                ? "Keine passende Runde gefunden. Versuch eine andere Distanz oder plane die Route selbst."
                : nil
            if note == nil, preferWater, !result.contains(where: { $0.waterShare >= 0.3 }) {
                note = found.source == .appleMaps
                    ? "Gewässerdaten werden noch geladen. Tippe gleich noch einmal auf „Neu suchen“."
                    : (water.isEmpty ? "Keine Flüsse oder Seen in der Nähe gefunden."
                                     : "Keine passende Runde am Wasser für diese Distanz gefunden.")
            }
        }
    }

    private func save() {
        guard let selected else { return }
        let name = "Rundkurs \(Format.distance(selected.distance, decimals: 1))"
            + (selected.highlights.first.map { " · \($0)" } ?? "")
        let route = PlannedRoute(name: name, waypoints: [selected.path[0]] + selected.waypoints + [selected.path[0]],
                                 path: selected.path, followsPaths: true)
        route.elevation = selected.elevation
        context.insert(route)
        try? context.save()
        selection?.wrappedValue = route
        onSaved()
        dismiss()
    }
}
