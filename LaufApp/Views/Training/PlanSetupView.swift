import SwiftUI
import SwiftData

/// Formular zum Erstellen eines neuen Trainingsplans.
struct PlanSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true }) private var activePlans: [TrainingPlan]

    @State private var goal: RaceGoal = .tenK
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    @State private var runsPerWeek = 4
    @State private var trainingDays: Set<Int> = [1, 3, 5, 6]
    @State private var longRunDay = 6
    @State private var weeklyKm = 20.0
    @State private var targetKm = 30.0
    @State private var targetEdited = false
    @State private var refDistance: RaceGoal = .fiveK
    @State private var refTime: TimeInterval = 30 * 60
    @State private var useGoalTime = false
    @State private var goalTime: TimeInterval = 60 * 60
    @State private var errorMessage: String?
    @State private var didPrefill = false

    private var currentVDOT: Double { VDOT.vdot(distance: refDistance.distance, time: refTime) }
    private var predictedTime: TimeInterval { VDOT.predictTime(distance: goal.distance, vdot: currentVDOT) }

    private var weeksUntilRace: Int {
        max(0, (Calendar.current.dateComponents([.day], from: .now, to: raceDate).day ?? 0) / 7)
    }

    /// Realistische Verbesserung ohne eigene Zielzeit: ca. +1 VDOT pro 6 Wochen, höchstens +3.
    private var recommendedGoalTime: TimeInterval {
        VDOT.predictTime(distance: goal.distance, vdot: currentVDOT + min(3, Double(weeksUntilRace) / 6))
    }

    private var effectiveGoalTime: TimeInterval { useGoalTime ? goalTime : recommendedGoalTime }
    private var goalVDOT: Double { VDOT.vdot(distance: goal.distance, time: effectiveGoalTime) }

    /// Vorschlag für den Wochenumfang: typischer Umfang für Ziel und Läufe pro Woche, mindestens die Empfehlung.
    private var suggestedTargetKm: Double {
        let typical = goal.typicalPeakKm * Double(runsPerWeek) / 5
        return (max(goal.recommendedMinWeeklyKm, typical, weeklyKm) / 5).rounded() * 5
    }

    private var input: PlanInput {
        PlanInput(goal: goal, raceDate: raceDate, currentWeeklyKm: weeklyKm, targetWeeklyKm: targetKm,
                  runsPerWeek: runsPerWeek, trainingDays: trainingDays, longRunDay: longRunDay,
                  currentVDOT: currentVDOT, goalTime: effectiveGoalTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ziel") {
                    Picker("Distanz", selection: $goal) {
                        ForEach(RaceGoal.allCases) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Wettkampftag", selection: $raceDate, in: Date.now..., displayedComponents: .date)
                    LabeledContent("Vorbereitung", value: "\(weeksUntilRace) Wochen")
                }

                Section {
                    Picker("Referenzstrecke", selection: $refDistance) {
                        ForEach(RaceGoal.allCases) { Text($0.name).tag($0) }
                    }
                    DurationPicker("Deine Zeit", duration: $refTime)
                    LabeledContent("VDOT (Leistungswert)", value: currentVDOT.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Aktuelle Prognose \(goal.name)", value: Format.duration(predictedTime))
                } header: {
                    Text("Aktuelle Form")
                } footer: {
                    Text("Eine aktuelle Wettkampf- oder Bestzeit (nicht älter als ca. 6 Wochen) oder eine ehrliche Schätzung. Daraus werden deine Trainingspaces berechnet.")
                }

                TrainingScheduleSection(runsPerWeek: $runsPerWeek, trainingDays: $trainingDays, longRunDay: $longRunDay)

                WeeklyVolumeSection(currentKm: $weeklyKm, targetKm: $targetKm,
                                    recommendedKm: goal.recommendedMinWeeklyKm,
                                    warnings: PlanGenerator.warnings(for: input),
                                    onTargetEdited: { targetEdited = true })

                Section {
                    Toggle("Eigene Zielzeit festlegen", isOn: $useGoalTime)
                    if useGoalTime {
                        DurationPicker("Zielzeit", duration: $goalTime)
                    } else {
                        LabeledContent("Empfohlene Zielzeit", value: Format.duration(recommendedGoalTime))
                    }
                    LabeledContent("Zielpace", value: Format.paceUnit(effectiveGoalTime / (goal.distance / 1000)))
                } header: {
                    Text("Zielzeit")
                } footer: {
                    if goalVDOT - currentVDOT > 4 {
                        Label("Sehr ambitioniert: Das Ziel liegt deutlich über deiner aktuellen Form. Die Trainingspaces steigen trotzdem nur langsam, um Verletzungen zu vermeiden.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neuer Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") { create() }
                        .bold()
                        .disabled(trainingDays.count < runsPerWeek)
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: useGoalTime) { _, on in
                if on { goalTime = recommendedGoalTime.rounded() }
            }
            .onChange(of: goal) { _, _ in
                if useGoalTime { goalTime = recommendedGoalTime.rounded() }
                if !targetEdited { targetKm = suggestedTargetKm }
            }
            .onChange(of: runsPerWeek) { _, _ in
                if !targetEdited { targetKm = suggestedTargetKm }
            }
            .onChange(of: weeklyKm) { _, _ in
                if !targetEdited { targetKm = suggestedTargetKm }
            }
        }
    }

    /// Werte aus bisherigen Läufen vorbelegen (Bestzeit & Wochenumfang).
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true

        let recent = runs.filter { $0.startDate > Calendar.current.date(byAdding: .day, value: -60, to: .now)! }
        let candidates: [(RaceGoal, Int)] = [(.tenK, 10000), (.fiveK, 5000)]
        for (distance, meters) in candidates {
            if let best = recent.compactMap({ $0.bestEfforts[meters] }).min() {
                refDistance = distance
                refTime = best.rounded()
                break
            }
        }

        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: .now)!
        let km = runs.filter { $0.startDate > fourWeeksAgo }.reduce(0) { $0 + $1.distance } / 1000 / 4
        if km > 0 { weeklyKm = min(120, (km / 5).rounded() * 5) }
        targetKm = suggestedTargetKm
    }

    private func create() {
        let input = input
        do {
            let result = try PlanGenerator.generate(input)
            let plan = TrainingPlan(input: input, generated: result)
            CalendarExport.replaceSyncedPlan(with: plan, previous: activePlans)
            activePlans.forEach { $0.isActive = false }
            context.insert(plan)
            try? context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
