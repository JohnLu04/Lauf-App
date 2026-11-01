import SwiftUI
import SwiftData
import Charts

struct PlanOverviewView: View {
    let plan: TrainingPlan
    var onNewPlan: () -> Void
    @Query private var runs: [Run]
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false
    @State private var showAdjust = false
    @State private var showCalendar = false

    /// Form aus den letzten Läufen, wenn sie spürbar besser ist als die des Plans.
    private var improvedVDOT: Double? {
        guard let estimate = VDOT.estimate(from: runs), estimate >= plan.formVDOT + 0.5 else { return nil }
        return estimate
    }

    var body: some View {
        let weeks = plan.weeks
        let currentIndex = plan.currentWeek()?.index

        ScrollViewReader { proxy in
            List {
                Section { header(weeks: weeks) }

                if let improvedVDOT {
                    Section { formBanner(improvedVDOT) }
                }

                if let next = plan.nextWorkout(runs: runs) {
                    Section(Calendar.current.isDateInToday(next.date) ? "Heute" : "Nächste Einheit") {
                        NavigationLink {
                            WorkoutDetailView(plan: plan, workout: next)
                        } label: {
                            NextWorkoutCard(workout: next)
                        }
                    }
                }

                Section {
                    PacesView(paces: VDOT.paces(vdot: plan.formVDOT))
                } header: {
                    Text("Deine Trainingspaces")
                } footer: {
                    Text("Basierend auf VDOT \(plan.formVDOT.formatted(.number.precision(.fractionLength(1)))). Die Paces in den einzelnen Einheiten steigen im Laufe des Plans langsam an.")
                }

                Section("Umfang pro Woche") {
                    volumeChart(weeks: weeks, current: currentIndex)
                }

                ForEach(weeks) { week in
                    Section {
                        ForEach(week.workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(plan: plan, workout: workout)
                            } label: {
                                WorkoutRow(workout: workout, done: plan.isCompleted(workout, runs: runs),
                                           skipped: plan.isSkipped(workout))
                            }
                        }
                    } header: {
                        weekHeader(week, isCurrent: week.index == currentIndex)
                    }
                    .id(week.index)
                }
            }
            .onAppear {
                if let currentIndex { proxy.scrollTo(currentIndex, anchor: .top) }
            }
        }
        .toolbar {
            Menu {
                Button("Plan anpassen", systemImage: "slider.horizontal.3") { showAdjust = true }
                Button(CalendarExport.isSynced(plan) ? "Kalender aktualisieren" : "In Kalender exportieren",
                       systemImage: "calendar.badge.plus") { showCalendar = true }
                Button("Neuen Plan erstellen", systemImage: "plus", action: onNewPlan)
                Button("Plan löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog("Trainingsplan löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                try? CalendarExport.remove(plan)
                context.delete(plan)
            }
        }
        .sheet(isPresented: $showAdjust) {
            PlanAdjustView(plan: plan, suggestedVDOT: VDOT.estimate(from: runs))
        }
        .sheet(isPresented: $showCalendar) {
            CalendarExportView(plan: plan)
        }
    }

    private func formBanner(_ vdot: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Du bist in Form!", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Deine letzten Läufe deuten auf VDOT \(vdot.formatted(.number.precision(.fractionLength(1)))) hin (Plan: \(plan.formVDOT.formatted(.number.precision(.fractionLength(1))))). Neue Prognose für \(plan.goal.name): \(Format.duration(VDOT.predictTime(distance: plan.goal.distance, vdot: vdot))).")
                .font(.subheadline)
            Button("Paces aktualisieren") { showAdjust = true }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
        .padding(.vertical, 4)
    }

    private func header(weeks: [PlanWeek]) -> some View {
        let all = weeks.flatMap(\.workouts)
        let done = all.filter { plan.isCompleted($0, runs: runs) }.count
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                              to: Calendar.current.startOfDay(for: plan.raceDate)).day ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.goal.name).font(.title.bold())
                    Text(plan.raceDate.formatted(date: .long, time: .omitted)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(daysLeft)").font(.title.bold()).foregroundStyle(Color.accentColor)
                    Text("Tage").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                StatView(label: "Zielzeit", value: Format.duration(plan.goalTime))
                StatView(label: "Zielpace", value: Format.pace(plan.goalPace), unit: "/km")
                StatView(label: "Prognose", value: Format.duration(VDOT.predictTime(distance: plan.goal.distance, vdot: plan.formVDOT)))
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(done), total: Double(max(1, all.count)))
                Text("\(done) von \(all.count) Einheiten erledigt").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func volumeChart(weeks: [PlanWeek], current: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(weeks) { week in
                BarMark(x: .value("Woche", week.index), y: .value("km", week.volume / 1000))
                    .foregroundStyle(week.phase.color.opacity(week.index == current ? 1 : 0.55))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { value in
                    AxisValueLabel { if let v = value.as(Int.self) { Text("W\(v)") } }
                }
            }
            .frame(height: 140)
            HStack(spacing: 12) {
                ForEach([TrainingPhase.base, .build, .peak, .taper], id: \.self) { phase in
                    HStack(spacing: 4) {
                        Circle().fill(phase.color).frame(width: 8, height: 8)
                        Text(phase.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weekHeader(_ week: PlanWeek, isCurrent: Bool) -> some View {
        HStack {
            Text("Woche \(week.index)").fontWeight(isCurrent ? .bold : .regular)
            Text("· \(week.phase.name)\(week.isRecoveryWeek ? " · Entlastung" : "")")
            Spacer()
            Text("\(Format.kilometers(week.volume, decimals: 0)) km")
            if isCurrent {
                Text("AKTUELL")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: PlannedWorkout
    let done: Bool
    var skipped = false

    private var isPast: Bool { workout.date < Calendar.current.startOfDay(for: .now) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(workout.kind.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.subheadline.weight(.semibold)).strikethrough(skipped)
                Text(workout.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Calendar.current.isDateInToday(workout.date) ? Color.accentColor : .secondary)
            }
            Spacer()
            Text(Format.distance(workout.distance, decimals: 1))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: done ? "checkmark.circle.fill" : (skipped ? "forward.circle" : "circle"))
                .foregroundStyle(done ? .green : (skipped ? .orange : Color(.tertiaryLabel)))
        }
        .opacity((isPast && !done) || skipped ? 0.5 : 1)
    }
}

struct PacesView: View {
    let paces: TrainingPaces

    var body: some View {
        VStack(spacing: 10) {
            row("Locker (E)", "\(Format.pace(paces.easyFast))–\(Format.pace(paces.easySlow))", .green,
                "Grundlage, lange Läufe, Erholung")
            row("Marathon (M)", Format.pace(paces.marathon), .purple, "Marathon-Renntempo")
            row("Schwelle (T)", Format.pace(paces.threshold), .orange, "Tempodauerlauf, ca. 1 h Renntempo")
            row("Intervall (I)", Format.pace(paces.interval), .red, "VO2max, Intervalle 2–5 min")
            row("Wiederholung (R)", Format.pace(paces.repetition), .pink, "Kurze schnelle Abschnitte, Technik")
        }
        .padding(.vertical, 4)
    }

    private func row(_ name: String, _ pace: String, _ color: Color, _ info: String) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(info).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(pace) /km").font(.subheadline.monospacedDigit())
        }
    }
}


/// Hervorgehobene Karte für die nächste geplante Einheit.
struct NextWorkoutCard: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: workout.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(workout.kind.color, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title).font(.headline)
                    Text(workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.distance(workout.distance, decimals: 1))
                    .font(.headline.monospacedDigit())
            }
            if let steps = workout.steps, steps.count > 1 {
                Text(WorkoutStepSummary.text(steps))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

enum WorkoutStepSummary {
    /// Kurzfassung, z.B. "2,0 km Einlaufen · 5 × 1 km @ 4:30 · 2,0 km Auslaufen"
    static func text(_ steps: [WorkoutStep]) -> String {
        var parts: [String] = []
        var i = 0
        let main = steps.filter { $0.kind == .run }
        while i < steps.count {
            let step = steps[i]
            switch step.kind {
            case .warmup, .cooldown:
                parts.append("\(step.amountText) \(step.kind.name)")
            case .recovery:
                break
            case .run:
                // gleiche Wiederholungen zusammenfassen
                let same = main.filter { $0.distance == step.distance && $0.duration == step.duration && $0.paceFast == step.paceFast }
                if same.count > 1 {
                    parts.append("\(same.count) × \(step.amountText)" + (step.paceText.map { " @ \($0)" } ?? ""))
                    while i + 1 < steps.count, steps[i + 1].kind != .cooldown { i += 1 }
                } else {
                    parts.append("\(step.amountText) \(step.label)" + (step.paceText.map { " @ \($0)" } ?? ""))
                }
            }
            i += 1
        }
        return parts.joined(separator: " · ")
    }
}
