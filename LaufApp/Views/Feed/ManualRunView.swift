import SwiftUI
import SwiftData

/// Lauf nachträglich eintragen, wenn ohne Aufzeichnung gelaufen wurde.
struct ManualRunView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedRoute.createdAt, order: .reverse) private var routes: [PlannedRoute]
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true }) private var plans: [TrainingPlan]

    @State private var startDate = Date.now.addingTimeInterval(-3600)
    @State private var title = ""
    @State private var titleEdited = false
    @State private var distanceText = ""
    @State private var duration: TimeInterval = 0
    @State private var routeID: UUID?
    @State private var elevationText = ""
    @State private var heartRateText = ""
    @State private var effort = 0
    @State private var notes = ""
    @State private var linkWorkout = true
    @State private var photos: [PendingPhoto] = []
    @State private var shoeID: UUID?
    @Query private var shoes: [Shoe]
    @FocusState private var focused: Bool

    private var distance: Double { (Self.number(distanceText) ?? 0) * 1000 }
    private var pace: Double { distance > 0 ? duration / (distance / 1000) : 0 }
    private var route: PlannedRoute? { routes.first { $0.id == routeID } }
    private var plannedWorkout: PlannedWorkout? {
        plans.first?.workout(on: startDate)
    }
    private var canSave: Bool { distance > 0 && duration > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $startDate, in: ...Date.now)
                    TextField("Titel", text: Binding(get: { title }, set: { title = $0; titleEdited = true }))
                }

                Section {
                    HStack {
                        Text("Distanz")
                        Spacer()
                        TextField("0,0", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($focused)
                        Text("km").foregroundStyle(.secondary)
                    }
                    DurationPicker("Zeit", duration: $duration)
                    if canSave {
                        LabeledContent("Ø Pace", value: Format.paceUnit(pace))
                    }
                } header: {
                    Text("Distanz und Zeit")
                } footer: {
                    if canSave, pace < 150 || pace > 1200 {
                        Label("Die Pace wirkt ungewöhnlich – stimmen Distanz und Zeit?", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if !routes.isEmpty {
                    Section {
                        Picker("Strecke", selection: $routeID) {
                            Text("Keine").tag(UUID?.none)
                            ForEach(routes) { route in
                                Text("\(route.name) · \(Format.distance(route.distance, decimals: 1))").tag(UUID?.some(route.id))
                            }
                        }
                        if let route, route.path.count > 1 {
                            RouteMapView(points: route.path.enumerated().map { i, c in
                                RoutePoint(latitude: c.latitude, longitude: c.longitude, altitude: nil,
                                           timestamp: Date(timeIntervalSince1970: Double(i)), segment: 0)
                            })
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        Text("Strecke (optional)")
                    } footer: {
                        Text("Wähle eine gespeicherte Route, damit der Lauf mit Karte angezeigt wird. Distanz und Höhenmeter werden übernommen.")
                    }
                }

                Section("Details (optional)") {
                    numberRow("Höhenmeter", text: $elevationText, unit: "m")
                    numberRow("Ø Herzfrequenz", text: $heartRateText, unit: "bpm")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gefühlte Anstrengung").font(.caption).foregroundStyle(.secondary)
                        EffortSlider(effort: $effort)
                    }
                    TextField("Notizen – wie lief's?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                }

                if !shoes.isEmpty {
                    Section { ShoePickerRow(selection: $shoeID) }
                }

                PendingPhotosSection(photos: $photos)
                RunExportSection()

                if let workout = plannedWorkout {
                    Section {
                        Toggle(isOn: $linkWorkout) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Als Trainingseinheit werten")
                                Text(workout.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Trainingsplan")
                    }
                }
            }
            .navigationTitle("Lauf hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        photos.forEach { $0.discard() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focused = false }
                }
            }
            .onAppear {
                updateTitle()
                shoeID = Shoe.defaultShoe(in: context)?.id
            }
            .onChange(of: startDate) { _, _ in updateTitle() }
            .onChange(of: routeID) { _, _ in
                guard let route else { return }
                distanceText = Self.format(route.distance / 1000, decimals: 2)
                if route.elevationGain > 0 { elevationText = "\(Int(route.elevationGain.rounded()))" }
            }
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($focused)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func updateTitle() {
        if !titleEdited { title = RunAnalysis.defaultTitle(for: startDate) }
    }

    private func save() {
        let run = Run(title: title.trimmingCharacters(in: .whitespaces).isEmpty ? RunAnalysis.defaultTitle(for: startDate) : title,
                      startDate: startDate, endDate: startDate.addingTimeInterval(duration))
        run.source = "manual"
        run.distance = distance
        run.movingTime = duration
        run.elapsedTime = duration
        run.elevationGain = Double(elevationText) ?? 0
        run.averageHeartRate = Double(heartRateText) ?? 0
        run.perceivedEffort = effort
        run.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let route {
            run.route = Self.points(along: route, start: startDate, duration: duration)
            run.elevationLoss = route.elevationLoss
        }
        if linkWorkout, let workout = plannedWorkout { run.plannedWorkoutID = workout.id }
        // Keine Splits und Bestzeiten: Ohne Aufzeichnung ist der Verlauf der Pace unbekannt.
        PhotoAttachment.attach(photos, to: run)
        run.shoeID = shoeID
        context.insert(run)
        try? context.save()
        let export = RunExportSection.selection
        RunExporter.shared.export(run, toStrava: export.strava, toHealth: export.health, context: context)
        dismiss()
    }

    /// Punkte der Route mit gleichmäßig verteilter Zeit (nur für Karte und Höhenprofil)
    static func points(along route: PlannedRoute, start: Date, duration: TimeInterval) -> [RoutePoint] {
        let path = route.path
        guard path.count > 1 else { return [] }
        let total = max(1, RouteGeometry.length(path))
        let profile = route.elevation
        var along = 0.0
        var result: [RoutePoint] = []
        for (i, c) in path.enumerated() {
            if i > 0 { along += path[i - 1].distance(to: c) }
            result.append(RoutePoint(latitude: c.latitude, longitude: c.longitude,
                                     altitude: profile.flatMap { altitude(in: $0, at: along) },
                                     timestamp: start.addingTimeInterval(duration * along / total), segment: 0))
        }
        return result
    }

    private static func altitude(in profile: ElevationProfile, at distance: Double) -> Double? {
        guard let i = profile.distances.firstIndex(where: { $0 >= distance }) else { return profile.elevations.last }
        guard i > 0 else { return profile.elevations.first }
        let d0 = profile.distances[i - 1], d1 = profile.distances[i]
        let f = d1 > d0 ? (distance - d0) / (d1 - d0) : 0
        return profile.elevations[i - 1] + (profile.elevations[i] - profile.elevations[i - 1]) * f
    }

    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)).grouping(.never))
    }
}
