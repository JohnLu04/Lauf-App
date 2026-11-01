import SwiftUI

/// Trainingsplan in die Kalender-App exportieren.
struct CalendarExportView: View {
    let plan: TrainingPlan

    @Environment(\.dismiss) private var dismiss
    @State private var options = CalendarExport.options
    @State private var time = Date()
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    private var isSynced: Bool { CalendarExport.isSynced(plan) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ganztägige Einträge", isOn: $options.allDay)
                    if !options.allDay {
                        DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Erinnerung", isOn: $options.reminder)
                } footer: {
                    Text(options.allDay
                         ? "Jede Einheit erscheint als ganztägiger Eintrag. Die Erinnerung kommt am Trainingstag um 8 Uhr."
                         : "Die Dauer wird aus Distanz und lockerer Pace geschätzt. Die Erinnerung kommt 1 Stunde vorher.")
                }

                Section {
                    Button {
                        Task { await export() }
                    } label: {
                        HStack {
                            Label(isSynced ? "Kalender aktualisieren" : "In Kalender exportieren", systemImage: "calendar.badge.plus")
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(isWorking)
                    if isSynced {
                        Button("Aus Kalender entfernen", systemImage: "calendar.badge.minus", role: .destructive) {
                            remove()
                        }
                        .disabled(isWorking)
                    }
                } footer: {
                    Text("Die Einheiten landen in einem eigenen Kalender „\(CalendarExport.calendarTitle)“. Verschiebst oder überspringst du Einheiten oder passt den Plan an, wird der Kalender automatisch aktualisiert. Deine anderen Termine bleiben unberührt.")
                }

                if let message {
                    Section {
                        Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Kalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear {
                time = Calendar.current.date(bySettingHour: options.hour, minute: options.minute, second: 0, of: .now) ?? .now
            }
        }
    }

    private func export() async {
        isWorking = true
        message = nil
        errorMessage = nil
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        options.hour = parts.hour ?? 18
        options.minute = parts.minute ?? 0
        do {
            let count = try await CalendarExport.export(plan, options: options)
            message = "\(count) Einheiten im Kalender „\(CalendarExport.calendarTitle)“ eingetragen."
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func remove() {
        message = nil
        errorMessage = nil
        do {
            try CalendarExport.remove(plan)
            message = "Der Trainingsplan wurde aus dem Kalender entfernt."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
