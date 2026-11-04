import SwiftUI
import SwiftData
import Charts

struct ProfileView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage("voiceFeedback") private var voiceFeedback = true
    @AppStorage("liveActivity") private var liveActivity = true
    @AppStorage(HeartRateZones.maxHeartRateKey) private var storedMaxHeartRate = 0.0
    @Environment(\.modelContext) private var context

    private let cal = Calendar.mondayFirst

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weeklyChart
                } header: {
                    Text("Letzte 12 Wochen")
                }

                Section("Statistik") {
                    totalsRow("Diese Woche", since: cal.startOfWeek(for: .now))
                    totalsRow("Dieser Monat", since: cal.dateInterval(of: .month, for: .now)?.start ?? .now)
                    totalsRow("Dieses Jahr", since: cal.dateInterval(of: .year, for: .now)?.start ?? .now)
                    totalsRow("Gesamt", since: .distantPast)
                }

                Section("Bestleistungen") {
                    let records = personalRecords
                    if records.isEmpty {
                        Text("Lauf mindestens 400 m, um deine ersten Bestleistungen zu sehen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(records, id: \.distance.meters) { record in
                        NavigationLink {
                            RunDetailView(run: record.run)
                        } label: {
                            HStack {
                                Image(systemName: "medal.fill").foregroundStyle(.yellow)
                                VStack(alignment: .leading) {
                                    Text(record.distance.name).font(.subheadline.weight(.semibold))
                                    Text(record.run.startDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(Format.duration(record.time)).font(.subheadline.bold()).monospacedDigit()
                                    Text(Format.paceUnit(record.time / (Double(record.distance.meters) / 1000)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ShoesView()
                    } label: {
                        LabeledContent {
                            if let shoe = shoes.first(where: { $0.isDefault && !$0.isRetired }) {
                                Text("\(shoe.displayName) · \(Format.distance(shoe.distance(in: runs), decimals: 0))")
                            } else {
                                let count = shoes.filter { !$0.isRetired }.count
                                Text(count == 0 ? "Keine" : "\(count) aktiv")
                            }
                        } label: {
                            Label("Schuhe", systemImage: "shoe.fill")
                        }
                    }
                } header: {
                    Text("Ausrüstung")
                }

                Section {
                    NavigationLink {
                        StravaSettingsView()
                    } label: {
                        LabeledContent {
                            Text(StravaSync.shared.isConnected ? "Verbunden" : "Nicht verbunden")
                        } label: {
                            Label("Strava & Garmin", systemImage: "applewatch")
                        }
                    }
                    NavigationLink {
                        HealthSettingsView()
                    } label: {
                        LabeledContent {
                            Text(HealthSync.shared.isEnabled ? "Aktiv" : "Aus")
                        } label: {
                            Label("Apple Health", systemImage: "heart.fill")
                        }
                    }
                } header: {
                    Text("Verbindungen")
                } footer: {
                    Text("Läufe deiner Garmin-Uhr oder Apple Watch automatisch übernehmen, mit Herzfrequenz und Schrittfrequenz.")
                }

                Section {
                    Toggle("Sprachansagen (jeder km)", isOn: $voiceFeedback)
                    Toggle("Live-Aktivität auf dem Sperrbildschirm", isOn: $liveActivity)
                    Stepper(value: Binding(get: { HeartRateZones.maxHeartRate(runs: runs) },
                                           set: { storedMaxHeartRate = $0 }),
                            in: 140...220) {
                        LabeledContent("Max. Herzfrequenz", value: "\(Int(HeartRateZones.maxHeartRate(runs: runs))) bpm")
                    }
                } header: {
                    Text("Einstellungen")
                } footer: {
                    Text("Sprachansagen: Zeit und Kilometer-Split nach jedem Kilometer, beim Folgen einer Route auch die Abzweigungen; Musik wird kurz leiser. Die Live-Aktivität zeigt Zeit, Distanz, Pace und die nächste Abzweigung auf dem Sperrbildschirm. Die maximale Herzfrequenz bestimmt deine Herzfrequenzzonen; ohne Angabe wird der höchste gemessene Wert verwendet.")
                }

                #if DEBUG
                Section {
                    Button("Demo-Lauf hinzufügen") { context.insert(DemoData.makeRun()) }
                    Button("Demo-Krafttraining hinzufügen") { DemoData.makeStrengthSessions().forEach(context.insert) }
                    Button("Demo-Route (hin und zurück) hinzufügen") { context.insert(DemoData.makeOutAndBackRoute()) }
                    Button("Demo-Schuhe hinzufügen") { DemoData.makeShoes(runs: runs).forEach(context.insert) }
                } header: {
                    Text("Entwickler")
                } footer: {
                    Text("Nur in Debug-Builds sichtbar. Erzeugt Testdaten (zufälliger Lauf, sechs Krafteinheiten der letzten Wochen bzw. eine Route mit Hin- und Rückweg bzw. zwei Schuhe, einer davon fast abgelaufen).")
                }
                #endif
            }
            .navigationTitle("Du")
        }
    }

    // MARK: - Wochen-Chart

    private struct WeekTotal: Identifiable {
        let start: Date
        let km: Double
        var id: Date { start }
    }

    private var weeklyTotals: [WeekTotal] {
        let thisWeek = cal.startOfWeek(for: .now)
        return (0..<12).reversed().map { offset in
            let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            let km = runs.filter { $0.startDate >= start && $0.startDate < end }.reduce(0) { $0 + $1.distance } / 1000
            return WeekTotal(start: start, km: km)
        }
    }

    private var weeklyChart: some View {
        let totals = weeklyTotals
        let average = totals.map(\.km).reduce(0, +) / Double(totals.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatView(label: "Ø pro Woche", value: average.formatted(.number.precision(.fractionLength(1))), unit: "km")
                StatView(label: "Diese Woche", value: (totals.last?.km ?? 0).formatted(.number.precision(.fractionLength(1))), unit: "km")
            }
            Chart(totals) { week in
                BarMark(x: .value("Woche", week.start, unit: .weekOfYear), y: .value("km", week.km))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 160)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Summen

    private func totalsRow(_ title: String, since start: Date) -> some View {
        let filtered = runs.filter { $0.startDate >= start }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack {
                StatView(label: "Distanz", value: Format.kilometers(filtered.reduce(0) { $0 + $1.distance }, decimals: 1), unit: "km")
                StatView(label: "Zeit", value: Format.duration(filtered.reduce(0) { $0 + $1.movingTime }))
                StatView(label: "Läufe", value: "\(filtered.count)")
                StatView(label: "Höhe", value: "\(Int(filtered.reduce(0) { $0 + $1.elevationGain }))", unit: "m")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bestleistungen

    private struct Record {
        let distance: RunAnalysis.BestEffortDistance
        let time: Double
        let run: Run
    }

    private var personalRecords: [Record] {
        RunAnalysis.bestEffortDistances.compactMap { d in
            var best: Record?
            for run in runs {
                if let t = run.bestEfforts[d.meters], t < (best?.time ?? .infinity) {
                    best = Record(distance: d, time: t, run: run)
                }
            }
            return best
        }
    }
}
