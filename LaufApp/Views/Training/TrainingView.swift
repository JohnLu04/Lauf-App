import SwiftUI
import SwiftData

struct TrainingView: View {
    enum Area: String { case run, strength }

    @Query(filter: #Predicate<TrainingPlan> { $0.isActive == true },
           sort: \TrainingPlan.createdAt, order: .reverse)
    private var plans: [TrainingPlan]
    @State private var showSetup = false
    @AppStorage("trainingSection") private var section = Area.run

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .run: runPlan
                case .strength: StrengthHomeView()
                }
            }
            .navigationTitle(section == .run ? "Laufplan" : "Krafttraining")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Bereich", selection: $section) {
                        Text("Laufplan").tag(Area.run)
                        Text("Krafttraining").tag(Area.strength)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }
            .sheet(isPresented: $showSetup) { PlanSetupView() }
        }
    }

    @ViewBuilder private var runPlan: some View {
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
}
