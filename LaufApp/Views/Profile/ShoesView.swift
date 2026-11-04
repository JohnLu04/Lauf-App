import SwiftUI
import SwiftData

/// Laufschuhe mit Kilometerstand; eigene Schuhe anlegen, Strava-Schuhe werden übernommen.
struct ShoesView: View {
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @Query private var runs: [Run]
    @State private var editing: Shoe?
    @State private var showNew = false

    private var active: [Shoe] {
        shoes.filter { !$0.isRetired }.sorted { ($0.isDefault ? 0 : 1, $0.createdAt) < ($1.isDefault ? 0 : 1, $1.createdAt) }
    }
    private var retired: [Shoe] { shoes.filter(\.isRetired) }

    var body: some View {
        Group {
            if shoes.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Schuhe", systemImage: "shoe.fill")
                } description: {
                    Text("Leg deine Laufschuhe an, um ihre Kilometer zu zählen. Die App erinnert dich, wenn ein Paar ausgetauscht werden sollte."
                         + (StravaSync.shared.isConnected ? " Schuhe aus Strava werden beim nächsten Synchronisieren übernommen." : ""))
                } actions: {
                    Button("Schuh hinzufügen", systemImage: "plus") { showNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(active) { row($0) }
                    } footer: {
                        Text("Laufschuhe halten meist 500–800 km, je nach Modell, Körpergewicht und Untergrund. Ist die empfohlene Laufleistung erreicht, erscheint ein Hinweis auf der Startseite."
                             + (StravaSync.shared.isConnected ? " Schuhe aus Strava werden mit Kilometerstand übernommen und ihren Läufen zugeordnet." : ""))
                    }
                    if !retired.isEmpty {
                        Section("Ausgemustert") {
                            ForEach(retired) { row($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Schuhe")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Schuh hinzufügen", systemImage: "plus") { showNew = true }
            }
        }
        .sheet(isPresented: $showNew) { ShoeEditorView(shoe: nil) }
        .sheet(item: $editing) { ShoeEditorView(shoe: $0) }
    }

    private func row(_ shoe: Shoe) -> some View {
        Button {
            editing = shoe
        } label: {
            ShoeRow(shoe: shoe, distance: shoe.distance(in: runs), runCount: runs.filter { $0.shoeID == shoe.id }.count)
        }
        .buttonStyle(.plain)
    }
}

/// Zeile mit Name, Kilometerstand und Fortschritt bis zur empfohlenen Laufleistung.
struct ShoeRow: View {
    let shoe: Shoe
    let distance: Double
    var runCount: Int?

    var body: some View {
        let status = shoe.status(distance: distance)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shoe.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(shoe.isRetired ? Color.gray : Color.accentColor, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(shoe.displayName).font(.headline)
                    HStack(spacing: 6) {
                        if let detail = shoe.detailName { Text(detail) }
                        if shoe.isDefault { badge("Standard", color: .accentColor) }
                        if shoe.isFromStrava { badge("Strava", color: .orange) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.distance(distance, decimals: 0)).font(.headline.monospacedDigit())
                    if let runCount {
                        Text(runCount == 1 ? "1 Lauf" : "\(runCount) Läufe").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !shoe.isRetired {
                ProgressView(value: min(distance, shoe.limit), total: max(shoe.limit, 1))
                    .tint(color(for: status))
                HStack {
                    if let label = status.label {
                        Label(label, systemImage: status == .replace ? "exclamationmark.triangle.fill" : "clock")
                            .foregroundStyle(color(for: status))
                    }
                    Spacer()
                    Text("Empfohlen bis \(Format.distance(shoe.limit, decimals: 0))").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func color(for status: ShoeStatus) -> Color {
        switch status {
        case .fine: .green
        case .soon: .orange
        case .replace: .red
        }
    }
}

/// Schuh anlegen oder bearbeiten.
struct ShoeEditorView: View {
    let shoe: Shoe?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var shoes: [Shoe]
    @Query private var runs: [Run]

    @State private var brand = ""
    @State private var model = ""
    @State private var nickname = ""
    @State private var startDate = Date.now
    @State private var initialKm = ""
    @State private var limitKm = Shoe.defaultLimit / 1000
    @State private var isDefault = false
    @State private var isRetired = false
    @State private var assignPastRuns = true
    @State private var confirmDelete = false
    @State private var loaded = false

    private static let brands = ["Adidas", "Altra", "Asics", "Brooks", "Hoka", "Mizuno", "New Balance", "Nike",
                                 "On", "Puma", "Salomon", "Saucony"]

    private var fromStrava: Bool { shoe?.isFromStrava ?? false }

    /// Läufe ohne Schuh ab dem Startdatum (für neue Schuhe)
    private var unassignedRuns: [Run] {
        let start = Calendar.current.startOfDay(for: startDate)
        return runs.filter { $0.shoeID == nil && $0.startDate >= start }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Marke", text: $brand)
                        Menu {
                            ForEach(Self.brands, id: \.self) { name in Button(name) { brand = name } }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                        .accessibilityLabel("Marke auswählen")
                    }
                    TextField("Modell, z. B. Pegasus 41", text: $model)
                    TextField("Eigener Name (optional)", text: $nickname)
                } header: {
                    Text("Schuh")
                } footer: {
                    if fromStrava { Text("Name, Kilometerstand und Status kommen von Strava und werden beim Synchronisieren aktualisiert.") }
                }
                .disabled(fromStrava)

                Section {
                    DatePicker("In Gebrauch seit", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                    if !fromStrava {
                        HStack {
                            Text("Schon gelaufen")
                            Spacer()
                            TextField("0", text: $initialKm)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("km").foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $limitKm, in: 300...1500, step: 50) {
                        LabeledContent("Austauschen nach", value: "\(Int(limitKm)) km")
                    }
                } header: {
                    Text("Kilometer")
                } footer: {
                    Text(fromStrava
                         ? "Kilometer, die du in der App ohne Strava läufst, kommen zum Strava-Stand hinzu."
                         : "„Schon gelaufen“: Kilometer, die du vor der App mit diesem Schuh gelaufen bist. Üblich sind 500–800 km bis zum Austauschen.")
                }

                Section {
                    Toggle("Standardschuh", isOn: $isDefault)
                    if shoe == nil, !unassignedRuns.isEmpty {
                        Toggle(isOn: $assignPastRuns) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bisherige Läufe zuordnen")
                                Text("\(unassignedRuns.count) \(unassignedRuns.count == 1 ? "Lauf" : "Läufe") seit \(startDate.formatted(date: .abbreviated, time: .omitted)) ohne Schuh")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if shoe != nil {
                        Toggle("Ausgemustert", isOn: $isRetired).disabled(fromStrava)
                    }
                } footer: {
                    Text("Der Standardschuh wird neuen Läufen automatisch zugeordnet – beim Aufzeichnen, Eintragen und beim Import aus Apple Health. Ändern kannst du ihn in der Laufansicht.")
                }

                if shoe != nil {
                    Section {
                        Button("Schuh löschen", role: .destructive) { confirmDelete = true }
                    } footer: {
                        if fromStrava { Text("Solange der Schuh in Strava existiert, wird er beim nächsten Synchronisieren wieder übernommen.") }
                    }
                }
            }
            .navigationTitle(shoe == nil ? "Neuer Schuh" : "Schuh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(brand.trimmingCharacters(in: .whitespaces).isEmpty
                                  && model.trimmingCharacters(in: .whitespaces).isEmpty
                                  && nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Schuh löschen?", isPresented: $confirmDelete) {
                Button("Löschen", role: .destructive) { delete() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Läufe bleiben erhalten, sind aber keinem Schuh mehr zugeordnet.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let shoe else {
            // Erster Schuh wird Standardschuh
            isDefault = !shoes.contains { $0.isDefault && !$0.isRetired }
            return
        }
        brand = shoe.brand
        model = shoe.model
        nickname = shoe.nickname
        startDate = shoe.startDate
        initialKm = shoe.initialDistance > 0 ? ManualRunView.format(shoe.initialDistance / 1000, decimals: 0) : ""
        limitKm = shoe.limit / 1000
        isDefault = shoe.isDefault
        isRetired = shoe.isRetired
    }

    private func save() {
        let target = shoe ?? Shoe(brand: "", model: "")
        if !fromStrava {
            target.brand = brand.trimmingCharacters(in: .whitespaces)
            target.model = model.trimmingCharacters(in: .whitespaces)
            target.nickname = nickname.trimmingCharacters(in: .whitespaces)
            target.initialDistance = (ManualRunView.number(initialKm) ?? 0) * 1000
            target.isRetired = isRetired
        }
        target.startDate = startDate
        if target.limit != limitKm * 1000 {
            target.limit = limitKm * 1000
            target.hintDismissedAt = 0
        }
        target.isDefault = isDefault && !target.isRetired
        if target.isDefault {
            for other in shoes where other.id != target.id { other.isDefault = false }
        }
        if shoe == nil {
            context.insert(target)
            if assignPastRuns { unassignedRuns.forEach { $0.shoeID = target.id } }
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let shoe else { return }
        for run in runs where run.shoeID == shoe.id { run.shoeID = nil }
        context.delete(shoe)
        try? context.save()
        dismiss()
    }
}

/// Hinweis auf der Startseite, wenn Schuhe die empfohlene Laufleistung erreicht haben.
struct ShoeReplaceCard: View {
    let shoe: Shoe
    let distance: Double
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zeit für neue Laufschuhe", systemImage: "shoe.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Deine \(shoe.displayName) haben \(Format.distance(distance, decimals: 0)) hinter sich – empfohlen sind bis zu \(Format.distance(shoe.limit, decimals: 0)). Dämpfung und Stabilität lassen mit der Zeit nach.")
                .font(.subheadline)
            HStack {
                Button("Ausmustern") {
                    shoe.isRetired = true
                    shoe.isDefault = false
                    try? context.save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(shoe.isFromStrava)
                Button("Später erinnern") {
                    shoe.hintDismissedAt = distance
                    try? context.save()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
            if shoe.isFromStrava {
                Text("Diesen Schuh musterst du in Strava aus; die App übernimmt das beim nächsten Synchronisieren.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Auswahl des Schuhs in Formularen (Lauf speichern, eintragen).
struct ShoePickerRow: View {
    @Binding var selection: UUID?
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]

    var body: some View {
        Picker(selection: $selection) {
            Text("Kein Schuh").tag(UUID?.none)
            ForEach(shoes.filter { !$0.isRetired || $0.id == selection }) { shoe in
                Text(shoe.displayName).tag(UUID?.some(shoe.id))
            }
        } label: {
            Label("Schuh", systemImage: "shoe.fill")
        }
    }
}
