import SwiftUI

/// Beim Speichern eines Laufs: zu Strava hochladen und/oder in Apple Health speichern.
/// Die Auswahl wird für den nächsten Lauf gemerkt.
struct RunExportSection: View {
    @AppStorage("export.strava") private var toStrava = false
    @AppStorage("export.health") private var toHealth = false

    /// Aktuelle Auswahl (nur, was gerade möglich ist)
    @MainActor static var selection: (strava: Bool, health: Bool) {
        let defaults = UserDefaults.standard
        return (defaults.bool(forKey: "export.strava") && StravaSync.shared.canUpload,
                defaults.bool(forKey: "export.health") && HealthSync.isAvailable)
    }

    var body: some View {
        let strava = StravaSync.shared
        if strava.isConnected || HealthSync.isAvailable {
            Section {
                if strava.isConnected {
                    Toggle(isOn: Binding(get: { toStrava && strava.canUpload }, set: { toStrava = $0 })) {
                        Label("Zu Strava hochladen", systemImage: "arrow.up.circle")
                    }
                    .disabled(!strava.canUpload)
                }
                if HealthSync.isAvailable {
                    Toggle(isOn: $toHealth) {
                        Label("In Apple Health speichern", systemImage: "heart")
                    }
                }
            } header: {
                Text("Teilen")
            } footer: {
                if strava.isConnected && !strava.canUpload {
                    Text("Zum Hochladen einmal unter Du → Strava & Garmin auf „Hochladen erlauben“ tippen.")
                } else {
                    Text("Der Lauf erscheint danach dort und wird nicht doppelt zurück importiert.")
                }
            }
        }
    }
}

/// Kurzer Hinweis zum Ergebnis des Hochladens bzw. Speicherns.
struct RunExportToast: View {
    var body: some View {
        if let message = RunExporter.shared.message {
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { RunExporter.shared.message = nil }
        }
    }
}
