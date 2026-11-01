import SwiftUI
import SwiftData

@main
struct LaufAppApp: App {
    @State private var recorder = RunRecorder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
        }
        .modelContainer(for: [Run.self, TrainingPlan.self, PlannedRoute.self])
    }
}
