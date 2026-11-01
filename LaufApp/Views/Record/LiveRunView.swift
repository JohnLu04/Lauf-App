import SwiftUI
import MapKit

/// Anzeige während des Laufens: Zeit, Distanz, Pace, Karte und Steuerung.
struct LiveRunView: View {
    @Environment(RunRecorder.self) private var recorder
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var confirmFinish = false

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                UserAnnotation()
                ForEach(Array(RunAnalysis.segments(recorder.points).enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.coordinate))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapControls { MapUserLocationButton() }
            .overlay(alignment: .top) { statusBar }

            metrics
            controls
        }
        .background(Color(.systemBackground))
        .confirmationDialog("Lauf beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Beenden und speichern") { recorder.finish() }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(recorder.gpsSignalGood ? .green : .orange).frame(width: 8, height: 8)
                Text(recorder.state == .paused ? "Pausiert" : (recorder.gpsSignalGood ? "Aufzeichnung läuft" : "Schwaches GPS"))
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())

            if let workout = recorder.plannedWorkout, !recorder.steps.isEmpty {
                GuidedStepCard(workout: workout)
            } else if let workout = recorder.plannedWorkout {
                VStack(alignment: .leading, spacing: 4) {
                    Label(workout.title, systemImage: workout.kind.symbol).font(.subheadline.bold())
                    Text(workout.details).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    private var metrics: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    Text(Format.duration(recorder.movingTime(at: context.date)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Zeit").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                bigMetric(Format.kilometers(recorder.distance), "Distanz (km)")
                Divider().frame(height: 44)
                bigMetric(Format.pace(recorder.currentPace), "Pace (/km)")
                Divider().frame(height: 44)
                bigMetric(Format.pace(recorder.averagePace), "Ø Pace (/km)")
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal)
    }

    private func bigMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 40) {
            if recorder.state == .running {
                circleButton("pause.fill", "Pause", color: .primary) { recorder.pause() }
            } else {
                circleButton("play.fill", "Weiter", color: .accentColor) { recorder.resume() }
                circleButton("stop.fill", "Beenden", color: .red) { confirmFinish = true }
            }
        }
        .padding(.bottom, 24)
        .animation(.default, value: recorder.state)
    }

    private func circleButton(_ symbol: String, _ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(color == .primary ? Color(.systemBackground) : .white)
                    .frame(width: 76, height: 76)
                    .background(color, in: Circle())
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
        }
        .sensoryFeedback(.impact, trigger: recorder.state)
    }
}


/// Aktueller Abschnitt eines geführten Workouts mit Zielpace und Restdistanz/-zeit.
struct GuidedStepCard: View {
    @Environment(RunRecorder.self) private var recorder
    let workout: PlannedWorkout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(workout.title, systemImage: workout.kind.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(min(recorder.stepIndex + 1, recorder.steps.count))/\(recorder.steps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let step = recorder.currentStep {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.label).font(.headline)
                            if let pace = step.paceText {
                                Text("Ziel: \(pace)").font(.subheadline.monospacedDigit())
                                    .foregroundStyle(paceColor(step))
                            }
                        }
                        Spacer()
                        Text(recorder.stepRemainingText(at: context.date))
                            .font(.title2.bold().monospacedDigit())
                    }
                    ProgressView(value: recorder.stepProgress(at: context.date))
                        .tint(step.kind == .recovery ? .gray : .accentColor)
                    HStack {
                        if let next = recorder.nextStep {
                            Text("Danach: \(next.label) · \(next.amountText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Überspringen", systemImage: "forward.end.fill") { recorder.skipStep() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else {
                    Label("Workout geschafft!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Grün im Zielbereich, Orange bei Abweichung.
    private func paceColor(_ step: WorkoutStep) -> Color {
        guard let fast = step.paceFast, let slow = step.paceSlow, recorder.currentPace > 0 else { return .primary }
        let easy = slow - fast >= 15
        if recorder.currentPace < fast * 0.98 { return .orange }
        if !easy, recorder.currentPace > slow * 1.02 { return .orange }
        return .green
    }
}
