import SwiftUI
import SwiftData

/// Krafttraining im Trainingstab: aktives Programm, Tagebuch, Fortschritt und alle Programme.
struct StrengthHomeView: View {
    @AppStorage("strengthProgramID") private var programID = ""
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]
    @State private var logProgram: StrengthProgram?
    @State private var showFreeLog = false

    private var activeProgram: StrengthProgram? { StrengthProgram.with(id: programID) }

    var body: some View {
        List {
            if let program = activeProgram {
                Section("Dein Programm") {
                    NavigationLink {
                        StrengthProgramDetailView(program: program)
                    } label: {
                        ProgramRow(program: program, isActive: false)
                    }
                    weekProgress(program)
                    Button {
                        logProgram = program
                    } label: {
                        Label("Training eintragen", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Krafttraining für Läufer", systemImage: "figure.strengthtraining.functional")
                            .font(.headline)
                        Text("Wähle unten ein Programm, das zu deinem Ziel passt. Danach kannst du jede Einheit mit Sätzen, Wiederholungen und Gewichten im Tagebuch festhalten und deine Leistungen vergleichen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if sessions.isEmpty {
                    Text("Noch keine Einheiten eingetragen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions.prefix(4)) { session in
                        NavigationLink {
                            StrengthSessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                    if sessions.count > 4 {
                        NavigationLink("Alle \(sessions.count) Einheiten") { StrengthDiaryView() }
                    }
                }
                Button("Freies Training eintragen", systemImage: "plus") { showFreeLog = true }
            } header: {
                Text("Tagebuch")
            }

            if !sessions.isEmpty {
                Section {
                    NavigationLink {
                        StrengthProgressListView()
                    } label: {
                        Label("Fortschritt je Übung", systemImage: "chart.xyaxis.line")
                    }
                }
            }

            Section {
                ForEach(StrengthProgram.all) { program in
                    NavigationLink {
                        StrengthProgramDetailView(program: program)
                    } label: {
                        ProgramRow(program: program, isActive: program.id == programID)
                    }
                }
            } header: {
                Text("Programme für Läufer")
            } footer: {
                Text("Alle Programme stützen sich auf Studien mit Läufern bzw. Sportlern. Bei Schmerzen oder Verletzungen lass dich ärztlich oder physiotherapeutisch beraten.")
            }

            Section {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Label("Alle Übungen (\(StrengthExercise.all.count))", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .sheet(item: $logProgram) { program in
            StrengthLogView(program: program)
        }
        .sheet(isPresented: $showFreeLog) {
            StrengthLogView(program: nil)
        }
    }

    private func weekProgress(_ program: StrengthProgram) -> some View {
        let start = Calendar.current.startOfWeek(for: .now)
        let count = sessions.filter { $0.programID == program.id && $0.date >= start }.count
        return HStack {
            Label("Diese Woche", systemImage: "calendar")
                .font(.subheadline)
            Spacer()
            Text("\(count) · Ziel \(program.frequency.replacingOccurrences(of: " pro Woche", with: "/Woche"))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Zeile für ein Programm in Listen.
struct ProgramRow: View {
    let program: StrengthProgram
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: program.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(program.name).font(.headline)
                    if isActive {
                        Text("Aktiv")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(program.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text("\(program.level) · \(program.frequency) · \(program.duration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Zeile für eine Einheit im Tagebuch.
struct SessionRow: View {
    let session: StrengthSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(session.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var details: String {
        var parts = ["\(session.entries.count) Übungen", "\(session.totalSets) Sätze"]
        if session.totalVolume > 0 { parts.append(StrengthFormat.weight(session.totalVolume) + " bewegt") }
        if session.durationMinutes > 0 { parts.append("\(session.durationMinutes) min") }
        return parts.joined(separator: " · ")
    }
}

/// Übungsfigur auf hellem Hintergrund (wie eine Illustration, auch im Dunkelmodus):
/// animiert in 3D oder als Standbild für Listen.
struct ExerciseThumbnail: View {
    let exercise: StrengthExercise
    var animating = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if animating {
                Exercise3DView(exercise: exercise)
            } else {
                ExerciseSnapshotView(exercise: exercise)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.965))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

enum StrengthFormat {
    static func weight(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0...2))) + " kg"
    }

    /// Kurzfassung der Sätze, z. B. „3 × 10 × 24 kg“ oder „10×24 · 8×22 kg“
    static func summary(_ entry: StrengthEntry) -> String {
        let sets = entry.sets
        guard let first = sets.first else { return "–" }
        let timed = entry.exercise?.measure == .seconds
        func one(_ s: StrengthSet) -> String {
            if timed { return "\(s.seconds) s" + (s.weight > 0 ? " · " + weight(s.weight) : "") }
            return s.weight > 0 ? "\(s.reps)×\(s.weight.formatted(.number.precision(.fractionLength(0...2))))" : "\(s.reps)"
        }
        if sets.allSatisfy({ $0.reps == first.reps && $0.weight == first.weight && $0.seconds == first.seconds }) {
            if timed { return "\(sets.count) × " + one(first) }
            return first.weight > 0 ? "\(sets.count) × \(first.reps) × \(weight(first.weight))" : "\(sets.count) × \(first.reps)"
        }
        let joined = sets.map(one).joined(separator: " · ")
        return (!timed && sets.contains { $0.weight > 0 }) ? joined + " kg" : joined
    }
}
