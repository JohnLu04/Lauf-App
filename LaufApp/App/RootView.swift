import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext

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
        // Während einer Aufzeichnung liegt der Aufnahmebildschirm über allem.
        .fullScreenCover(isPresented: Binding(get: { recorder.isSessionActive }, set: { _ in })) {
            RecordingSessionView()
                .environment(recorder)
                .modelContext(modelContext)
        }
    }
}
