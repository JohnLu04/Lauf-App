import SwiftUI
import SwiftData

struct TrainingView: View {
    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true },
           sort: \TrainingPlan.createdAt, order: .reverse)
    private var plans: [TrainingPlan]
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.first {
                    PlanOverviewView(plan: plan, onNewPlan: { showSetup = true })
                } else {
                    ContentUnavailableView {
                        Label("Kein Trainingsplan", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Erstelle einen Plan für 5 km, 10 km, Halbmarathon oder Marathon – mit Trainingspaces, die zu deiner aktuellen Form passen.")
                    } actions: {
                        Button("Plan erstellen") { showSetup = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Training")
            .sheet(isPresented: $showSetup) { PlanSetupView() }
        }
    }
}
