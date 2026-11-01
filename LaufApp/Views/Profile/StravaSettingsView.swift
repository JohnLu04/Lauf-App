import SwiftUI
import SwiftData
import AuthenticationServices

/// Strava verbinden, mit Schritt-für-Schritt-Anleitung für die eigene API-Anwendung.
struct StravaSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var strava = StravaSync.shared
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var initialDays = 30
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var confirmDisconnect = false

    private let apiSettingsURL = URL(string: "https://www.strava.com/settings/api")!

    var body: some View {
        Form {
            if strava.isConnected {
                connectedSections
            } else {
                setupSections
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Strava & Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clientID = strava.clientID
            clientSecret = strava.clientSecret
            initialDays = strava.initialImportDays
        }
        .confirmationDialog("Verbindung zu Strava trennen?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Trennen", role: .destructive) { Task { await strava.disconnect() } }
        } message: {
            Text("Bereits importierte Läufe bleiben erhalten.")
        }
    }

    // MARK: - Verbunden

    @ViewBuilder
    private var connectedSections: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verbunden").font(.headline)
                    if let name = strava.athleteName { Text(name).font(.subheadline).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let last = strava.lastSyncDate {
                LabeledContent("Zuletzt synchronisiert", value: last.formatted(.relative(presentation: .named)))
            }
            if let result = strava.lastResult {
                Text(result).font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = strava.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
            }
            Button {
                Task { await strava.sync(context: context) }
            } label: {
                HStack {
                    Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if strava.isSyncing { ProgressView() }
                }
            }
            .disabled(strava.isSyncing)
        } footer: {
            Text("Neue Läufe werden beim Öffnen der App automatisch geholt. Läufe, die du schon mit LaufApp aufgezeichnet hast, werden nicht doppelt importiert.")
        }

        Section {
            Button("Verbindung trennen", role: .destructive) { confirmDisconnect = true }
        }
    }

    // MARK: - Einrichtung

    @ViewBuilder
    private var setupSections: some View {
        Section {
            Text("Deine Garmin-Uhr lädt jeden Lauf zu Strava hoch, LaufApp holt ihn dort ab – mit Herzfrequenz, Schrittfrequenz, Route und Höhe.")
                .font(.subheadline)
        }

        Section {
            step(1, "Garmin mit Strava verbinden",
                 "Garmin-Connect-App → Mehr → Einstellungen → Verbundene Apps → Strava → Verbinden.")
        } header: {
            Text("Schritt 1")
        }

        Section {
            step(2, "Strava-API-Anwendung anlegen",
                 "Öffne die Strava-Einstellungen (am besten am Computer), melde dich an und fülle das Formular so aus:")
            Link(destination: apiSettingsURL) {
                Label("strava.com/settings/api öffnen", systemImage: "safari")
            }
            copyRow("Anwendungsname", "LaufApp")
            copyRow("Kategorie", "Training")
            copyRow("Website", "https://github.com/JohnLu04/Lauf-App")
            copyRow("Autorisierungs-Callback-Domain", StravaSync.callbackDomain)
        } header: {
            Text("Schritt 2")
        } footer: {
            Text("Für das Symbol kannst du ein beliebiges Bild hochladen. Die Beschreibung ist optional.")
        }

        Section {
            step(3, "Zugangsdaten eintragen",
                 "Nach dem Speichern zeigt Strava „Client-ID“ und „Client-Secret“ (auf „Anzeigen“ tippen). Kopiere beide hierher:")
            TextField("Client-ID (Zahl)", text: $clientID)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            SecureField("Client-Secret", text: $clientSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Schritt 3")
        } footer: {
            Text("Das Secret wird nur im Schlüsselbund deines iPhones gespeichert.")
        }

        Section {
            step(4, "Verbinden", "Melde dich bei Strava an und tippe auf „Autorisieren“. Lass dabei das Häkchen für private Aktivitäten gesetzt.")
            Picker("Beim ersten Mal importieren", selection: $initialDays) {
                Text("Letzte 30 Tage").tag(30)
                Text("Letzte 90 Tage").tag(90)
                Text("Letztes Jahr").tag(365)
            }
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Label("Mit Strava verbinden", systemImage: "link")
                        .bold()
                    Spacer()
                    if isConnecting { ProgressView() }
                }
            }
            .disabled(clientID.isEmpty || clientSecret.isEmpty || isConnecting)
        } header: {
            Text("Schritt 4")
        }
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.monospaced()).textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(label) kopieren")
        }
    }

    private func connect() async {
        errorMessage = nil
        strava.clientID = clientID
        strava.clientSecret = clientSecret
        strava.initialImportDays = initialDays
        guard let url = strava.authorizeURL else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: url, callbackURLScheme: StravaSync.callbackScheme)
            try await strava.handleCallback(callback)
            await strava.sync(context: context)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Abgebrochen – nichts tun
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
