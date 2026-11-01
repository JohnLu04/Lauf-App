import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let plan: TrainingPlan
    let workout: PlannedWorkout
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var showMove = false
    @State private var moveDate = Date()

    private var manuallyDone: Bool { plan.completedIDs.contains(workout.id) }
    private var skipped: Bool { plan.isSkipped(workout) }
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
                if skipped {
                    Label("Übersprungen", systemImage: "forward.circle").foregroundStyle(.orange)
                }
            }

            if let steps = workout.steps, !steps.isEmpty {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        StepRow(step: step)
                    }
                } header: {
                    Text("Ablauf")
                } footer: {
                    Text("Beim Laufen sagt dir die App jeden Abschnitt an und meldet sich, wenn du zu schnell oder zu langsam bist.")
                }
                Section("Hinweise") {
                    Text(workout.details)
                }
            } else {
                Section("Ablauf") {
                    Text(workout.details)
                }
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
                        // Die Liste ordnet sich neu (nächste Einheit), daher zurück zur Übersicht
                        if plan.completedIDs.contains(workout.id) { dismiss() }
                    }
                    Button(skipped ? "Doch nicht überspringen" : "Überspringen",
                           systemImage: skipped ? "arrow.uturn.backward.circle" : "forward.circle") {
                        plan.toggleSkipped(workout)
                        CalendarExport.resyncIfNeeded(plan)
                        if plan.isSkipped(workout) { dismiss() }
                    }
                    Button("Auf anderen Tag verschieben", systemImage: "calendar") {
                        moveDate = workout.date
                        showMove = true
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
        .sheet(isPresented: $showMove) { moveSheet }
    }

    private var moveRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = max(cal.startOfDay(for: .now), plan.weeks.first?.startDate ?? .now)
        let end = max(start, cal.startOfDay(for: plan.raceDate))
        return start...end
    }

    private var moveSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Neuer Tag", selection: $moveDate, in: moveRange, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                if let other = plan.workout(on: moveDate), other.id != workout.id {
                    Label("An diesem Tag ist schon „\(other.title)“ geplant. Zwei Einheiten am selben Tag sind möglich, aber selten sinnvoll.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
            .navigationTitle("Verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showMove = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verschieben") {
                        plan.move(workout, to: moveDate)
                        CalendarExport.resyncIfNeeded(plan)
                        showMove = false
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.large])
    }
}

struct StepRow: View {
    let step: WorkoutStep

    private var color: Color {
        switch step.kind {
        case .warmup, .cooldown: .green
        case .recovery: .gray
        case .run:
            if let fast = step.paceFast, let slow = step.paceSlow { slow - fast >= 15 ? .green : .orange } else { .accentColor }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label).font(.subheadline.weight(.semibold))
                Text(step.amountText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let pace = step.paceText {
                Text(pace).font(.subheadline.monospacedDigit())
            }
        }
    }
}
