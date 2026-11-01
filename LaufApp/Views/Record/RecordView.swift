import SwiftUI
import SwiftData
import MapKit

/// Tab "Aufnehmen": Karte mit eigenem Standort, GPS-Status und Start-Knopf.
struct RecordView: View {
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true }) private var plans: [TrainingPlan]
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var linkWorkout = true
    @State private var selectedRoute: PlannedRoute?
    @State private var showRoutes = false

    private var todaysWorkout: PlannedWorkout? { plans.first?.workout(on: .now) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    if let route = selectedRoute, route.path.count > 1 {
                        MapPolyline(coordinates: route.path.map(\.coordinate))
                            .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        if let start = route.path.first {
                            Annotation("Start", coordinate: start.coordinate, anchor: .center) {
                                Circle().fill(.green).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                VStack(spacing: 14) {
                    if !recorder.hasLocationPermission {
                        permissionCard
                    } else {
                        if let workout = todaysWorkout {
                            todayCard(workout)
                        }
                        HStack(spacing: 10) {
                            gpsPill
                            routeButton
                        }
                        startButton
                    }
                }
                .padding()
                .padding(.bottom, 8)
            }
            .navigationTitle("Aufnehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Routen", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { showRoutes = true }
                }
            }
            .sheet(isPresented: $showRoutes) { RoutesView(selection: $selectedRoute) }
            .onChange(of: selectedRoute?.id) { _, _ in
                if let route = selectedRoute, let rect = boundingRect(route.path) {
                    withAnimation { position = .rect(rect) }
                }
            }
            .onAppear { recorder.startPreview() }
            .onDisappear { recorder.stopPreview() }
        }
    }

    private var startButton: some View {
        Button {
            recorder.start(planned: linkWorkout ? todaysWorkout : nil, route: selectedRoute)
        } label: {
            Text("START")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
    }

    /// Gewählte Route oder Knopf zum Auswählen
    private var routeButton: some View {
        Button {
            showRoutes = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                if let route = selectedRoute {
                    Text("\(route.name) · \(Format.distance(route.distance, decimals: 1))").lineLimit(1)
                } else {
                    Text("Route wählen")
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(selectedRoute == nil ? Color.primary : Color.accentColor)
        }
    }

    private var gpsPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(recorder.gpsSignalGood ? .green : .orange)
                .frame(width: 8, height: 8)
            Text(recorder.gpsSignalGood ? "GPS bereit" : "Suche GPS-Signal …")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func todayCard(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: workout.kind.symbol).foregroundStyle(workout.kind.color)
                Text("Heute: \(workout.title)").font(.headline)
                Spacer()
                Text(Format.distance(workout.distance, decimals: 1)).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(workout.steps.map { WorkoutStepSummary.text($0) } ?? workout.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Toggle("Mit Trainingsplan verknüpfen", isOn: $linkWorkout)
                .font(.footnote)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash.fill").font(.title).foregroundStyle(Color.accentColor)
            Text("Standortzugriff benötigt").font(.headline)
            Text("Damit LaufApp deine Strecke, Distanz und Pace aufzeichnen kann, braucht sie Zugriff auf dein GPS.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if recorder.authorizationStatus == .notDetermined {
                Button("Zugriff erlauben") { recorder.requestPermission() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Inhalt des Vollbilds während/nach einer Aufzeichnung.
struct RecordingSessionView: View {
    @Environment(RunRecorder.self) private var recorder

    var body: some View {
        if let draft = recorder.finishedDraft {
            SaveRunView(draft: draft)
        } else {
            LiveRunView()
        }
    }
}
