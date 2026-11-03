import SwiftUI
import SwiftData

/// Nach dem Beenden: Titel, Notizen, Anstrengung und Fotos eintragen, dann speichern oder verwerfen.
struct SaveRunView: View {
    let draft: RunDraft
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.modelContext) private var context
    @State private var title: String
    @State private var notes = ""
    @State private var effort = 0
    @State private var photos: [PendingPhoto] = []
    @State private var confirmDiscard = false

    init(draft: RunDraft) {
        self.draft = draft
        _title = State(initialValue: RunAnalysis.defaultTitle(for: draft.startDate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RouteMapView(points: draft.points)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                    HStack {
                        StatView(label: "Distanz", value: Format.kilometers(draft.distance), unit: "km")
                        StatView(label: "Zeit", value: Format.duration(draft.movingTime))
                        StatView(label: "Ø Pace",
                                 value: Format.pace(draft.distance > 10 ? draft.movingTime / (draft.distance / 1000) : 0),
                                 unit: "/km")
                    }
                    if draft.points.count < 2 {
                        Label("Es wurde keine GPS-Strecke aufgezeichnet.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Titel") {
                    TextField("Titel", text: $title)
                }
                Section("Notizen") {
                    TextField("Wie lief's?", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Gefühlte Anstrengung") {
                    EffortSlider(effort: $effort)
                }
                PendingPhotosSection(photos: $photos)
                Section {
                    Button("Lauf verwerfen", role: .destructive) { confirmDiscard = true }
                }
            }
            .navigationTitle("Lauf speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }.bold()
                }
            }
            .confirmationDialog("Lauf wirklich verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) {
                    photos.forEach { $0.discard() }
                    recorder.clearDraft()
                }
            }
        }
    }

    private func save() {
        let run = RunAnalysis.makeRun(from: draft,
                                      title: title.isEmpty ? RunAnalysis.defaultTitle(for: draft.startDate) : title,
                                      notes: notes, effort: effort)
        PhotoAttachment.attach(photos, to: run)
        context.insert(run)
        try? context.save()
        recorder.clearDraft()
    }
}
