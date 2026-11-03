import SwiftUI
import SwiftData

/// Erklärung einer Übung mit Animation, beanspruchten Muskeln und Ausführung.
struct ExerciseDetailView: View {
    let exercise: StrengthExercise
    var item: ProgramItem?
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]

    private var history: [StrengthHistory.Point] { StrengthHistory.points(for: exercise, in: sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    ExerciseThumbnail(exercise: exercise, animating: true, cornerRadius: 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                    VStack(spacing: 0) {
                        InfoRow(icon: "figure.strengthtraining.traditional",
                                title: exercise.primary.map(\.name).joined(separator: ", "),
                                subtitle: muscleDetail)
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "hand.point.up.left", title: exercise.cue)
                        Divider().padding(.leading, 44)
                        InfoRow(icon: "dumbbell", title: exercise.equipment)
                        if let item {
                            Divider().padding(.leading, 44)
                            InfoRow(icon: "list.number", title: item.prescription,
                                    subtitle: "\(item.intensity) · Pause \(item.rest)")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 16) {
                    legend(color: Color(red: 0.85, green: 0.18, blue: 0.15), text: "Hauptmuskeln")
                    legend(color: Color(red: 0.85, green: 0.18, blue: 0.15).opacity(0.4), text: "Unterstützend")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ausführung").font(.headline)
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor, in: Circle())
                            Text(step).font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Häufige Fehler").font(.headline)
                    ForEach(exercise.mistakes, id: \.self) { mistake in
                        Label(mistake, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .labelStyle(BulletLabelStyle(color: .orange))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Warum für Läufer", systemImage: "figure.run").font(.headline)
                    Text(exercise.benefit).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if !history.isEmpty {
                    NavigationLink {
                        ExerciseProgressView(exercise: exercise)
                    } label: {
                        HStack {
                            Label("Dein Verlauf", systemImage: "chart.xyaxis.line").font(.headline)
                            Spacer()
                            Text("\(history.count) Einheiten").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var muscleDetail: String {
        let main = exercise.primary.map(\.detail).joined(separator: ", ")
        guard !exercise.secondary.isEmpty else { return main }
        return main + " (" + exercise.secondary.map(\.name).joined(separator: ", ") + ")"
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

/// Zeile mit Symbol, Titel und Untertitel (wie in Trainings-Apps üblich).
struct InfoRow: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

/// Alle Übungen zum Durchstöbern, gruppiert nach Hauptmuskel.
struct ExerciseLibraryView: View {
    var body: some View {
        List {
            ForEach(groups, id: \.0) { group, exercises in
                Section(group) {
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseThumbnail(exercise: exercise, animating: false)
                                    .frame(width: 84, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(.subheadline.weight(.semibold))
                                    Text(exercise.primary.map(\.name).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Übungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groups: [(String, [StrengthExercise])] {
        let order: [(String, Set<MuscleGroup>)] = [
            ("Beine & Gesäß", [.quads, .glutes]),
            ("Oberschenkelrückseite", [.hamstrings]),
            ("Waden & Sehnen", [.calves]),
            ("Hüfte", [.hipAbductors, .adductors]),
            ("Rumpf", [.core, .obliques]),
        ]
        var used = Set<String>()
        return order.compactMap { name, muscles in
            let list = StrengthExercise.all.filter { !used.contains($0.id) && muscles.contains($0.primary[0]) }
            list.forEach { used.insert($0.id) }
            return list.isEmpty ? nil : (name, list)
        }
    }
}
