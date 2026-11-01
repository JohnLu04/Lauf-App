import SwiftUI
import SwiftData
import Charts

struct PlanOverviewView: View {
    let plan: TrainingPlan
    var onNewPlan: () -> Void
    @Query private var runs: [Run]
    @Environment(\.modelContext) private var context
    @State private var confirmDelete = false

    var body: some View {
        let weeks = plan.weeks
        let currentIndex = plan.currentWeek()?.index

        ScrollViewReader { proxy in
            List {
                Section { header(weeks: weeks) }

                Section {
                    PacesView(paces: VDOT.paces(vdot: plan.startVDOT))
                } header: {
                    Text("Deine Trainingspaces")
                } footer: {
                    Text("Basierend auf VDOT \(plan.startVDOT.formatted(.number.precision(.fractionLength(1)))). Die Paces in den einzelnen Einheiten steigen im Laufe des Plans langsam an.")
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
                                WorkoutRow(workout: workout, done: plan.isCompleted(workout, runs: runs))
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
                Button("Neuen Plan erstellen", systemImage: "plus", action: onNewPlan)
                Button("Plan löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .confirmationDialog("Trainingsplan löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { context.delete(plan) }
        }
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
                StatView(label: "Wochen", value: "\(weeks.count)")
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

    private var isPast: Bool { workout.date < Calendar.current.startOfDay(for: .now) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(workout.kind.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.subheadline.weight(.semibold))
                Text(workout.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Calendar.current.isDateInToday(workout.date) ? Color.accentColor : .secondary)
            }
            Spacer()
            Text(Format.distance(workout.distance, decimals: 1))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : Color(.tertiaryLabel))
        }
        .opacity(isPast && !done ? 0.5 : 1)
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
