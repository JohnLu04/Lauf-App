import SwiftUI
import SwiftData

/// Einheit eintragen oder bearbeiten: Sätze mit Wiederholungen, Gewicht bzw. Haltezeit.
/// Neue Einheiten werden mit den Werten der letzten Einheit vorbelegt.
struct StrengthLogView: View {
    var program: StrengthProgram?
    var session: StrengthSession?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]

    @State private var date = Date.now
    @State private var entries: [StrengthEntry] = []
    @State private var notes = ""
    @State private var effort = 0
    @State private var duration = 0
    @State private var didLoad = false
    @State private var showAddExercise = false
    @FocusState private var focused: Bool

    init(program: StrengthProgram?) {
        self.program = program
    }

    init(session: StrengthSession) {
        self.session = session
        self.program = session.program
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date)
                    if let program {
                        LabeledContent("Programm", value: program.name)
                    }
                }

                ForEach($entries) { $entry in
                    if let exercise = entry.exercise {
                        EntrySection(entry: $entry, exercise: exercise,
                                     previous: StrengthHistory.previousEntries(for: exercise.id, before: date,
                                                                               in: sessions, excluding: session),
                                     focused: $focused,
                                     onRemove: { entries.removeAll { $0.id == entry.id } })
                    }
                }

                Section {
                    Button("Übung hinzufügen", systemImage: "plus.circle") { showAddExercise = true }
                }

                Section("Wie war es?") {
                    Stepper(value: $duration, in: 0...240, step: 5) {
                        LabeledContent("Dauer", value: duration > 0 ? "\(duration) min" : "–")
                    }
                    Stepper(value: $effort, in: 0...10) {
                        LabeledContent("Anstrengung", value: effort > 0 ? "\(effort)/10" : "–")
                    }
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focused)
                }
            }
            .navigationTitle(session == nil ? "Training eintragen" : "Einheit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!entries.contains { !$0.sets.isEmpty })
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focused = false }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                ExercisePicker { exercise in
                    entries.append(StrengthEntry(exerciseID: exercise.id, sets: initialSets(for: exercise, item: nil)))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let session {
            date = session.date
            entries = session.entries
            notes = session.notes
            effort = session.effort
            duration = session.durationMinutes
        } else if let program {
            entries = program.items.compactMap { item in
                item.exercise.map { StrengthEntry(exerciseID: $0.id, sets: initialSets(for: $0, item: item)) }
            }
        }
    }

    /// Sätze der letzten Einheit übernehmen, sonst die Vorgabe des Programms
    private func initialSets(for exercise: StrengthExercise, item: ProgramItem?) -> [StrengthSet] {
        let count = item?.sets ?? 3
        let last = StrengthHistory.previousEntries(for: exercise.id, before: .distantFuture, in: sessions, excluding: nil).first
        return (0..<count).map { index in
            if let sets = last?.entry.sets, !sets.isEmpty {
                var set = sets[min(index, sets.count - 1)]
                set.id = UUID()
                return set
            }
            let target = item?.target ?? (exercise.measure == .seconds ? 30 : 10)
            return exercise.measure == .seconds ? StrengthSet(seconds: target) : StrengthSet(reps: target)
        }
    }

    private func save() {
        let cleaned = entries.compactMap { entry -> StrengthEntry? in
            var entry = entry
            entry.sets = entry.sets.filter { $0.reps > 0 || $0.seconds > 0 }
            return entry.sets.isEmpty ? nil : entry
        }
        let target = session ?? StrengthSession(date: date, programID: program?.id ?? "")
        target.date = date
        target.entries = cleaned
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.effort = effort
        target.durationMinutes = duration
        if session == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}

/// Abschnitt einer Übung im Eintragen-Formular.
private struct EntrySection: View {
    @Binding var entry: StrengthEntry
    let exercise: StrengthExercise
    let previous: [(date: Date, entry: StrengthEntry)]
    var focused: FocusState<Bool>.Binding
    let onRemove: () -> Void
    @State private var showInfo = false

    var body: some View {
        Section {
            ForEach($entry.sets) { $set in
                let index = entry.sets.firstIndex { $0.id == set.id } ?? 0
                SetRow(index: index, set: $set, exercise: exercise, focused: focused)
            }
            .onDelete { entry.sets.remove(atOffsets: $0) }

            Button {
                var copy = entry.sets.last ?? (exercise.measure == .seconds ? StrengthSet(seconds: 30) : StrengthSet(reps: 10))
                copy.id = UUID()
                entry.sets.append(copy)
            } label: {
                Label("Satz hinzufügen", systemImage: "plus")
            }
            .font(.subheadline)
        } header: {
            HStack(spacing: 10) {
                Button { showInfo = true } label: {
                    ExerciseThumbnail(exercise: exercise, animating: false, cornerRadius: 6)
                        .frame(width: 54, height: 36)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    if exercise.perSide {
                        Text("je Seite").font(.caption2).textCase(nil)
                    }
                }
                Spacer()
                Menu {
                    Button("Übung erklären", systemImage: "info.circle") { showInfo = true }
                    Button("Übung entfernen", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body)
                }
            }
        } footer: {
            if !previous.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(previous.prefix(3), id: \.date) { item in
                        Text("\(item.date.formatted(.dateTime.day().month(.abbreviated))): \(StrengthFormat.summary(item.entry))")
                    }
                }
                .font(.caption.monospacedDigit())
            }
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showInfo = false } }
                    }
            }
        }
    }
}

/// Eingabezeile für einen Satz.
private struct SetRow: View {
    let index: Int
    @Binding var set: StrengthSet
    let exercise: StrengthExercise
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.secondary, in: Circle())
            if exercise.measure == .seconds {
                field(value: $set.seconds, unit: "s")
            } else {
                field(value: $set.reps, unit: "Wdh.")
            }
            if exercise.usesWeight || set.weight > 0 {
                Text("×").foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    NumberField(value: $set.weight, decimals: true)
                        .frame(width: 56)
                        .focused(focused)
                    Text("kg").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Wiederholungen in Reserve", selection: $set.reserve) {
                    Text("Keine Angabe").tag(Int?.none)
                    ForEach(0...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
            } label: {
                Text(set.reserve.map { "RIR \($0)" } ?? "RIR")
                    .font(.caption)
                    .foregroundStyle(set.reserve == nil ? .secondary : .primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .font(.body.monospacedDigit())
    }

    private func field(value: Binding<Int>, unit: String) -> some View {
        HStack(spacing: 3) {
            NumberField(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                        decimals: false)
                .frame(width: 44)
                .focused(focused)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// Zahlenfeld, das jede Eingabe sofort übernimmt (ein Feld mit `value:format:` übernimmt den Wert
/// erst beim Verlassen – tippt man direkt auf „Sichern“, ginge die letzte Eingabe verloren).
private struct NumberField: View {
    @Binding var value: Double
    let decimals: Bool
    @State private var text = ""

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Double(newText.replacingOccurrences(of: ",", with: ".")) ?? 0
                if parsed != value { value = decimals ? parsed : parsed.rounded(.down) }
            }
            .onChange(of: value) { _, newValue in
                // Änderungen von außen (z. B. Satz kopiert) übernehmen, ohne die Eingabe zu stören
                let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
                if parsed != newValue { text = Self.format(newValue) }
            }
    }

    static func format(_ value: Double) -> String {
        value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// Übung aus dem Katalog auswählen.
struct ExercisePicker: View {
    var onPick: (StrengthExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(StrengthExercise.all) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ExerciseThumbnail(exercise: exercise, animating: false, cornerRadius: 6)
                            .frame(width: 66, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.primary.map(\.name).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Übung hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}
