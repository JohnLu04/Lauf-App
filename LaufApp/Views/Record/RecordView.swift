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

    private var todaysWorkout: PlannedWorkout? { plans.first?.workout(on: .now) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
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
                        gpsPill
                        startButton
                    }
                }
                .padding()
                .padding(.bottom, 8)
            }
            .navigationTitle("Aufnehmen")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { recorder.startPreview() }
            .onDisappear { recorder.stopPreview() }
        }
    }

    private var startButton: some View {
        Button {
            recorder.start(planned: linkWorkout ? todaysWorkout : nil)
        } label: {
            Text("START")
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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
            Text(workout.details)
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
