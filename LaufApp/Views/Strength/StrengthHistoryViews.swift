import SwiftUI
import SwiftData
import Charts

/// Auswertungen über alle eingetragenen Einheiten.
enum StrengthHistory {
    struct Point: Identifiable {
        let date: Date
        let entry: StrengthEntry
        var id: Date { date }

        var topWeight: Double { entry.sets.map(\.weight).max() ?? 0 }
        var bestOneRepMax: Double { entry.sets.map(\.estimatedOneRepMax).max() ?? 0 }
        var volume: Double { entry.sets.reduce(0) { $0 + $1.volume } }
        var totalReps: Int { entry.sets.reduce(0) { $0 + $1.reps } }
        var bestSeconds: Int { entry.sets.map(\.seconds).max() ?? 0 }
    }

    /// Alle Einheiten mit dieser Übung, älteste zuerst
    static func points(for exercise: StrengthExercise, in sessions: [StrengthSession]) -> [Point] {
        sessions.flatMap { session in
            session.entries.filter { $0.exerciseID == exercise.id && !$0.sets.isEmpty }.map { Point(date: session.date, entry: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Frühere Einträge einer Übung vor einem Datum, neueste zuerst
    static func previousEntries(for exerciseID: String, before date: Date, in sessions: [StrengthSession],
                                excluding: StrengthSession?) -> [(date: Date, entry: StrengthEntry)] {
        sessions
            .filter { $0.date < date && $0.id != excluding?.id }
            .sorted { $0.date > $1.date }
            .compactMap { session in
                session.entries.first { $0.exerciseID == exerciseID && !$0.sets.isEmpty }.map { (session.date, $0) }
            }
    }
}

/// Einzelne Einheit im Tagebuch.
struct StrengthSessionDetailView: View {
    let session: StrengthSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.title3.bold())
                    Text(session.date.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        StatView(label: "Sätze", value: "\(session.totalSets)")
                        StatView(label: "Bewegte Last", value: session.totalVolume > 0 ? StrengthFormat.weight(session.totalVolume) : "–")
                    }
                    GridRow {
                        StatView(label: "Dauer", value: session.durationMinutes > 0 ? "\(session.durationMinutes) min" : "–")
                        StatView(label: "Anstrengung", value: session.effort > 0 ? "\(session.effort)/10" : "–")
                    }
                }
            }

            ForEach(session.entries) { entry in
                if let exercise = entry.exercise {
                    Section {
                        ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                            HStack {
                                Text("Satz \(index + 1)").foregroundStyle(.secondary)
                                Spacer()
                                Text(setText(set, exercise: exercise)).monospacedDigit()
                            }
                        }
                        NavigationLink("Verlauf ansehen") { ExerciseProgressView(exercise: exercise) }
                            .font(.subheadline)
                    } header: {
                        HStack(spacing: 10) {
                            ExerciseThumbnail(exercise: exercise, animating: false, cornerRadius: 6)
                                .frame(width: 54, height: 36)
                            Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                        }
                    }
                }
            }

            if !session.notes.isEmpty {
                Section("Notizen") { Text(session.notes) }
            }
        }
        .navigationTitle("Einheit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Bearbeiten", systemImage: "pencil") { showEdit = true }
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showEdit) { StrengthLogView(session: session) }
        .confirmationDialog("Einheit löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(session)
                }
            }
        }
    }

    private func setText(_ set: StrengthSet, exercise: StrengthExercise) -> String {
        var text = exercise.measure == .seconds ? "\(set.seconds) s" : "\(set.reps) Wdh."
        if set.weight > 0 { text += " × " + StrengthFormat.weight(set.weight) }
        if let reserve = set.reserve { text += " · RIR \(reserve)" }
        return text
    }
}

/// Alle Einheiten, nach Monaten gruppiert.
struct StrengthDiaryView: View {
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(months, id: \.0) { month, items in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(items) { session in
                        NavigationLink {
                            StrengthSessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete { offsets in offsets.map { items[$0] }.forEach(context.delete) }
                }
            }
        }
        .navigationTitle("Tagebuch")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var months: [(Date, [StrengthSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }
}

/// Übungen, zu denen es Einträge gibt.
struct StrengthProgressListView: View {
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                let points = StrengthHistory.points(for: exercise, in: sessions)
                NavigationLink {
                    ExerciseProgressView(exercise: exercise)
                } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnail(exercise: exercise, animating: false, cornerRadius: 6)
                            .frame(width: 66, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).font(.subheadline.weight(.semibold))
                            if let last = points.last {
                                Text("Zuletzt: \(StrengthFormat.summary(last.entry))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fortschritt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var exercises: [StrengthExercise] {
        let ids = Set(sessions.flatMap { $0.entries.map(\.exerciseID) })
        return StrengthExercise.all.filter { ids.contains($0.id) }
    }
}

/// Verlauf einer Übung: Diagramm und alle bisherigen Einträge.
struct ExerciseProgressView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case oneRepMax = "1RM (geschätzt)", topWeight = "Gewicht", volume = "Volumen", reps = "Wiederholungen", seconds = "Zeit"
        var id: String { rawValue }
    }

    let exercise: StrengthExercise
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]
    @State private var metric: Metric?

    private var points: [StrengthHistory.Point] { StrengthHistory.points(for: exercise, in: sessions) }

    private var metrics: [Metric] {
        if exercise.measure == .seconds { return [.seconds] }
        return points.contains { $0.topWeight > 0 } ? [.oneRepMax, .topWeight, .volume] : [.reps]
    }

    var body: some View {
        let points = points
        let current = metric ?? metrics[0]
        List {
            Section {
                ExerciseThumbnail(exercise: exercise, animating: true)
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
            }

            if points.isEmpty {
                Text("Noch keine Einträge für diese Übung.").foregroundStyle(.secondary)
            } else {
                Section {
                    if metrics.count > 1 {
                        Picker("Wert", selection: Binding(get: { current }, set: { metric = $0 })) {
                            ForEach(metrics) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    // Einheiten ohne Gewicht (bzw. ohne Wert) nicht als 0 einzeichnen
                    let charted = points.filter { value($0, current) > 0 }
                    chart(charted, metric: current)
                        .frame(height: 200)
                    if let best = charted.map({ value($0, current) }).max() {
                        LabeledContent("Bestwert", value: format(best, current))
                    }
                } footer: {
                    if current == .oneRepMax {
                        Text("Geschätzt aus dem besten Satz mit der Epley-Formel (Gewicht × (1 + Wiederholungen / 30)).")
                    }
                }

                Section("Einträge") {
                    ForEach(points.reversed()) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(StrengthFormat.summary(point.entry)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func value(_ point: StrengthHistory.Point, _ metric: Metric) -> Double {
        switch metric {
        case .oneRepMax: point.bestOneRepMax
        case .topWeight: point.topWeight
        case .volume: point.volume
        case .reps: Double(point.totalReps)
        case .seconds: Double(point.bestSeconds)
        }
    }

    private func format(_ value: Double, _ metric: Metric) -> String {
        switch metric {
        case .oneRepMax, .topWeight, .volume: StrengthFormat.weight(value)
        case .reps: "\(Int(value)) Wdh."
        case .seconds: "\(Int(value)) s"
        }
    }

    private func chart(_ points: [StrengthHistory.Point], metric: Metric) -> some View {
        Chart(points) { point in
            LineMark(x: .value("Datum", point.date), y: .value(metric.rawValue, value(point, metric)))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("Datum", point.date), y: .value(metric.rawValue, value(point, metric)))
                .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
