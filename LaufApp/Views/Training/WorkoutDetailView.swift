import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let plan: TrainingPlan
    let workout: PlannedWorkout
    @Environment(RunRecorder.self) private var recorder
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    private var manuallyDone: Bool { plan.completedIDs.contains(workout.id) }
    private var matchingRun: Run? {
        runs.first { $0.plannedWorkoutID == workout.id }
            ?? runs.first { Calendar.current.isDate($0.startDate, inSameDayAs: workout.date)
                && $0.distance >= workout.distance * 0.6 }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: workout.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(workout.kind.color, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.title).font(.title3.bold())
                        Text(workout.date.formatted(date: .complete, time: .omitted))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Art", value: workout.kind.name)
                LabeledContent("Distanz", value: "ca. " + Format.distance(workout.distance, decimals: 1))
            }

            Section("Ablauf") {
                Text(workout.details)
            }

            Section {
                if let run = matchingRun {
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        Label("Erledigt: \(run.title) – \(Format.distance(run.distance))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button(manuallyDone ? "Markierung „erledigt“ entfernen" : "Als erledigt markieren",
                           systemImage: manuallyDone ? "xmark.circle" : "checkmark.circle") {
                        plan.toggleCompleted(workout)
                    }
                }
                if recorder.state == .idle {
                    Button("Dieses Training jetzt laufen", systemImage: "play.circle.fill") {
                        recorder.start(planned: workout)
                    }
                    .bold()
                }
            }
        }
        .navigationTitle(workout.kind.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
