import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Start", systemImage: "house.fill") }
            RecordView()
                .tabItem { Label("Aufnehmen", systemImage: "record.circle") }
            TrainingView()
                .tabItem { Label("Training", systemImage: "calendar") }
            ProfileView()
                .tabItem { Label("Du", systemImage: "person.fill") }
        }
        // Neue Läufe aus Apple Health und von Strava (z. B. von der Garmin-Uhr) beim Öffnen der App holen
        .task {
            await HealthSync.shared.syncIfNeeded(context: modelContext)
            await StravaSync.shared.syncIfNeeded(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await HealthSync.shared.syncIfNeeded(context: modelContext)
                await StravaSync.shared.syncIfNeeded(context: modelContext)
            }
        }
        // Während einer Aufzeichnung liegt der Aufnahmebildschirm über allem.
        .fullScreenCover(isPresented: Binding(get: { recorder.isSessionActive }, set: { _ in })) {
            RecordingSessionView()
                .environment(recorder)
                .modelContext(modelContext)
        }
    }
}
