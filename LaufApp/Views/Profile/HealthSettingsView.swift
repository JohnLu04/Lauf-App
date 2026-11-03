import SwiftUI
import SwiftData

/// Import von Lauftrainings aus Apple Health ein- und ausschalten.
struct HealthSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var health = HealthSync.shared
    @State private var initialDays = 30
    @State private var isEnabling = false
    #if DEBUG
    @State private var demoMessage: String?
    #endif

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Läufe aus Apple Health").font(.headline)
                        Text("Übernimmt deine Lauftrainings automatisch – von der Apple Watch und von Apps, die in Apple Health schreiben (z. B. Garmin Connect, Nike Run Club). Mit Strecke, Herzfrequenz, Schrittfrequenz und Splits.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
                .padding(.vertical, 4)
            }

            if !HealthSync.isAvailable {
                Section {
                    Label("Apple Health ist auf diesem Gerät nicht verfügbar.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else if health.isEnabled {
                enabledSections
            } else {
                Section {
                    Picker("Beim ersten Import übernehmen", selection: $initialDays) {
                        Text("Letzte 7 Tage").tag(7)
                        Text("Letzte 30 Tage").tag(30)
                        Text("Letzte 90 Tage").tag(90)
                        Text("Letztes Jahr").tag(365)
                    }
                    Button {
                        health.initialImportDays = initialDays
                        isEnabling = true
                        Task {
                            await health.enable(context: context)
                            isEnabling = false
                        }
                    } label: {
                        HStack {
                            Label("Mit Apple Health verbinden", systemImage: "heart.text.square")
                            Spacer()
                            if isEnabling { ProgressView() }
                        }
                    }
                    .disabled(isEnabling)
                } footer: {
                    Text("Apple Health fragt danach, welche Daten LaufApp lesen darf. Bitte erlaube Trainings, Trainingsrouten, Herzfrequenz, Schritte und Gehen- und Laufstrecke. LaufApp schreibt nichts in Apple Health.")
                }
            }

            if let error = health.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }

            #if DEBUG
            Section {
                Button("Test-Lauf in Apple Health anlegen") {
                    Task {
                        do {
                            try await DemoData.writeHealthWorkout(to: health.store)
                            demoMessage = "Test-Lauf in Apple Health gespeichert."
                            await health.sync(context: context)
                        } catch {
                            demoMessage = error.localizedDescription
                        }
                    }
                }
                if let demoMessage { Text(demoMessage).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Entwickler")
            } footer: {
                Text("Nur in Debug-Builds: speichert einen Lauf mit Route, Herzfrequenz und Schritten in Apple Health.")
            }
            #endif
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialDays = health.initialImportDays }
    }

    @ViewBuilder
    private var enabledSections: some View {
        Section {
            Label {
                Text("Verbunden").font(.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let last = health.lastSyncDate {
                LabeledContent("Zuletzt abgefragt", value: last.formatted(.relative(presentation: .named)))
            }
            if let result = health.lastResult {
                Text(result).font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                Task { await health.sync(context: context) }
            } label: {
                HStack {
                    Label("Jetzt importieren", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if health.isSyncing { ProgressView() }
                }
            }
            .disabled(health.isSyncing)
        } footer: {
            Text("Neue Läufe werden automatisch übernommen, sobald du die App öffnest. Läufe, die schon von Strava importiert oder mit LaufApp aufgezeichnet wurden, werden nicht doppelt angelegt.")
        }

        Section {
            Picker("Zeitraum", selection: $initialDays) {
                Text("Letzte 7 Tage").tag(7)
                Text("Letzte 30 Tage").tag(30)
                Text("Letzte 90 Tage").tag(90)
                Text("Letztes Jahr").tag(365)
            }
            Button("Läufe aus diesem Zeitraum importieren", systemImage: "clock.arrow.circlepath") {
                health.initialImportDays = initialDays
                health.resetAnchor()
                Task { await health.sync(context: context) }
            }
            .disabled(health.isSyncing)
        } header: {
            Text("Ältere Läufe")
        }

        Section {
            Button("Import ausschalten", role: .destructive) { health.disable() }
        } footer: {
            Text("Bereits importierte Läufe bleiben erhalten. Falls keine Läufe erscheinen: Einstellungen › Apps › Health › Datenzugriff & Geräte › LaufApp – dort das Lesen erlauben.")
        }
    }
}
