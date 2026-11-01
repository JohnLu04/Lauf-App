import SwiftUI
import SwiftData

/// Laufenden Plan anpassen: Trainingstage, Umfang und aktuelle Form ändern.
/// Vergangene Tage bleiben unverändert, ab heute wird der Plan neu berechnet.
struct PlanAdjustView: View {
    let plan: TrainingPlan
    /// Aus den letzten Läufen geschätzte Form (optional vorgeschlagen)
    var suggestedVDOT: Double?

    @Environment(\.dismiss) private var dismiss
    @State private var runsPerWeek = 4
    @State private var trainingDays: Set<Int> = []
    @State private var longRunDay = 6
    @State private var currentKm = 20.0
    @State private var targetKm = 30.0
    @State private var vdot = 40.0
    @State private var errorMessage: String?
    @State private var loaded = false

    private var currentWeekIndex: Int { plan.currentWeek()?.index ?? 1 }

    private var input: PlanInput {
        PlanInput(goal: plan.goal, raceDate: plan.raceDate, currentWeeklyKm: currentKm, targetWeeklyKm: targetKm,
                  runsPerWeek: runsPerWeek, trainingDays: trainingDays, longRunDay: longRunDay,
                  currentVDOT: vdot, goalTime: plan.goalTime,
                  today: plan.weeks.first?.startDate ?? .now,
                  formWeekIndex: currentWeekIndex - 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("VDOT", value: vdot.formatted(.number.precision(.fractionLength(1))))
                    Stepper("Form anpassen", value: $vdot, in: 20...85, step: 0.5)
                    LabeledContent("Prognose \(plan.goal.name)",
                                   value: Format.duration(VDOT.predictTime(distance: plan.goal.distance, vdot: vdot)))
                    if let suggestedVDOT, abs(suggestedVDOT - vdot) >= 0.5 {
                        Button("Form aus deinen Läufen übernehmen (VDOT \(suggestedVDOT.formatted(.number.precision(.fractionLength(1)))))",
                               systemImage: "wand.and.stars") {
                            vdot = (suggestedVDOT * 2).rounded() / 2
                        }
                    }
                } header: {
                    Text("Aktuelle Form")
                } footer: {
                    Text("Aus der Form werden deine Trainingspaces berechnet. Bist du schneller geworden, steigen die Paces für die restlichen Wochen.")
                }

                TrainingScheduleSection(runsPerWeek: $runsPerWeek, trainingDays: $trainingDays, longRunDay: $longRunDay)

                WeeklyVolumeSection(currentKm: $currentKm, targetKm: $targetKm,
                                    recommendedKm: plan.goal.recommendedMinWeeklyKm,
                                    warnings: PlanGenerator.warnings(for: input))

                Section {
                    Text("Ab heute wird der Plan mit den neuen Einstellungen neu berechnet. Bereits gelaufene Einheiten bleiben erhalten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { apply() }
                        .bold()
                        .disabled(trainingDays.count < runsPerWeek)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let weeks = plan.weeks
        runsPerWeek = plan.runsPerWeek
        trainingDays = plan.trainingDays.isEmpty ? [1, 3, 5, 6] : plan.trainingDays
        longRunDay = plan.trainingDaysRaw.isEmpty
            ? (weeks.first?.workouts.first { $0.kind == .long }.map { Calendar.mondayFirst.weekdayIndex(of: $0.date) } ?? 6)
            : plan.longRunDay
        currentKm = plan.currentWeeklyKm > 0 ? plan.currentWeeklyKm : ((weeks.first?.volume ?? 20000) / 1000 / 5).rounded() * 5
        targetKm = plan.targetWeeklyKm > 0
            ? plan.targetWeeklyKm
            : ((weeks.dropLast().map(\.volume).max() ?? 30000) / 1000 / 5).rounded() * 5
        vdot = suggestedVDOT.map { max($0, plan.formVDOT) } ?? plan.formVDOT
    }

    private func apply() {
        let input = input
        do {
            let generated = try PlanGenerator.generate(input)
            plan.replaceWeeks(from: currentWeekIndex, with: generated.weeks, keepingBefore: .now)
            plan.runsPerWeek = input.runsPerWeek
            plan.trainingDays = input.trainingDays
            plan.longRunDay = input.longRunDay
            plan.currentWeeklyKm = input.currentWeeklyKm
            plan.targetWeeklyKm = input.targetWeeklyKm
            plan.currentVDOT = input.currentVDOT
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
