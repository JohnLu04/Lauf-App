import SwiftUI
import SwiftData
import Charts

struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var points: [RoutePoint] = []
    @State private var paceSeries: [RunAnalysis.SeriesPoint] = []
    @State private var elevationSeries: [RunAnalysis.SeriesPoint] = []
    @State private var heartRateSeries: [RunAnalysis.SeriesPoint] = []
    @State private var cadenceSeries: [RunAnalysis.SeriesPoint] = []
    @State private var zoneTimes: [TimeInterval] = []
    @State private var photos: [RunPhoto] = []
    /// Wird nach dem Neuladen von Dateien erhöht, damit die Galerie die Bilder neu liest
    @State private var photoRevision = 0
    @State private var isRefreshingPhotos = false
    @State private var photoMessage: String?
    @Query private var allRuns: [Run]
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RouteMapView(points: points, interactive: true)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title).font(.title2.bold())
                    Text(run.startDate.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if run.isFromStrava {
                        Label("Von Strava importiert", systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !run.notes.isEmpty {
                        Text(run.notes).padding(.top, 4)
                    }
                }

                statsGrid.card()

                if !photos.isEmpty {
                    RunPhotoGallery(run: run, photos: photos)
                        .id(photoRevision)
                        .card()
                }

                if !run.splits.isEmpty {
                    SplitsView(splits: run.splits).card()
                }
                if !paceSeries.isEmpty {
                    PaceChart(series: paceSeries, average: run.averagePace).card()
                }
                if heartRateSeries.count > 2 {
                    HeartRateCard(series: heartRateSeries, average: run.averageHeartRate, maximum: run.maxHeartRate,
                                  zoneTimes: zoneTimes, maxHeartRate: HeartRateZones.maxHeartRate(runs: allRuns)).card()
                }
                if cadenceSeries.count > 2 {
                    CadenceChart(series: cadenceSeries, average: run.averageCadence).card()
                }
                if elevationSeries.count > 2 {
                    ElevationChart(series: elevationSeries).card()
                }
                if !run.bestEfforts.isEmpty {
                    bestEfforts.card()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Bearbeiten", systemImage: "pencil") { showEdit = true }
                if run.stravaID != nil && StravaSync.shared.isConnected {
                    Button("Fotos & Videos von Strava aktualisieren", systemImage: "photo.badge.arrow.down") {
                        Task { await refreshPhotos() }
                    }
                    .disabled(isRefreshingPhotos)
                }
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showEdit) { EditRunView(run: run) }
        .confirmationDialog("Lauf löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                // Erst zurücknavigieren, dann löschen, damit die Ansicht nicht auf ein gelöschtes Objekt zugreift.
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    RunPhotoStore.deleteAll(for: run.id)
                    context.delete(run)
                }
            }
        } message: {
            Text("Das kann nicht rückgängig gemacht werden.")
        }
        .overlay(alignment: .bottom) {
            if let photoMessage {
                Text(photoMessage)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            photos = run.photos
            // Fehlende Bilddateien (z. B. nach einer Neuinstallation) automatisch neu laden
            if run.stravaID != nil, StravaSync.shared.isConnected, run.hasMissingPhotoFiles {
                Task { await refreshPhotos(silentIfNothingChanged: true) }
            }
            let route = run.route
            points = route
            paceSeries = RunAnalysis.paceSeries(route)
            elevationSeries = RunAnalysis.elevationSeries(route)
            let sensors = run.sensorSamples
            heartRateSeries = RunAnalysis.sensorSeries(sensors) { $0.heartRate }
            cadenceSeries = RunAnalysis.sensorSeries(sensors) { $0.cadence }
            zoneTimes = HeartRateZones.timeInZones(sensors, maxHeartRate: HeartRateZones.maxHeartRate(runs: allRuns))
        }
    }

    private func refreshPhotos(silentIfNothingChanged: Bool = false) async {
        isRefreshingPhotos = true
        defer { isRefreshingPhotos = false }
        let message: String
        do {
            let added = try await StravaSync.shared.refreshPhotos(for: run, context: context)
            photos = run.photos
            photoRevision += 1
            if added == 0 && silentIfNothingChanged { return }
            if added == 0 {
                message = run.hasMissingPhotoFiles
                    ? "Einige Dateien konnten nicht von Strava geladen werden."
                    : "Keine neuen Fotos oder Videos."
            } else {
                message = added == 1 ? "1 Foto/Video aktualisiert." : "\(added) Fotos/Videos aktualisiert."
            }
        } catch {
            if silentIfNothingChanged { return }
            message = error.localizedDescription
        }
        withAnimation { photoMessage = message }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { photoMessage = nil }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                StatView(label: "Distanz", value: Format.kilometers(run.distance), unit: "km", large: true)
                StatView(label: "Ø Pace", value: Format.pace(run.averagePace), unit: "/km", large: true)
            }
            GridRow {
                StatView(label: "Bewegungszeit", value: Format.duration(run.movingTime), large: true)
                StatView(label: "Höhenmeter", value: "\(Int(run.elevationGain.rounded()))", unit: "m", large: true)
            }
            if run.averageHeartRate > 0 || run.averageCadence > 0 {
                GridRow {
                    StatView(label: "Ø Herzfrequenz", value: run.averageHeartRate > 0 ? "\(Int(run.averageHeartRate.rounded()))" : "–",
                             unit: "bpm", large: true)
                    StatView(label: "Ø Schrittfrequenz", value: run.averageCadence > 0 ? "\(Int(run.averageCadence.rounded()))" : "–",
                             unit: "spm", large: true)
                }
            }
            GridRow {
                StatView(label: "Gesamtzeit", value: Format.duration(run.elapsedTime))
                StatView(label: "Anstrengung", value: run.perceivedEffort > 0 ? "\(run.perceivedEffort)/10" : "–")
            }
        }
    }

    private var bestEfforts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bestleistungen in diesem Lauf").font(.headline)
            ForEach(RunAnalysis.bestEffortDistances) { d in
                if let time = run.bestEfforts[d.meters] {
                    HStack {
                        Text(d.name)
                        Spacer()
                        Text(Format.duration(time)).monospacedDigit().bold()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

struct SplitsView: View {
    let splits: [Split]

    var body: some View {
        let fastest = splits.filter { $0.distance >= 500 }.map(\.pace).min() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits").font(.headline)
            HStack {
                Text("km").frame(width: 36, alignment: .leading)
                Text("Pace").frame(width: 50, alignment: .leading)
                Spacer()
                Text("Hm").frame(width: 40, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(splits) { split in
                HStack {
                    Text(split.distance < 999 ? Format.kilometers(split.distance, decimals: 1) : "\(split.index)")
                        .frame(width: 36, alignment: .leading)
                    Text(Format.pace(split.pace))
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(split.pace <= fastest + 0.5 ? 1 : 0.6))
                            .frame(width: max(8, geo.size.width * min(1, fastest / max(split.pace, 1))))
                    }
                    .frame(height: 14)
                    Text("\(Int(split.elevationGain.rounded()))")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
    }
}

struct PaceChart: View {
    let series: [RunAnalysis.SeriesPoint]
    let average: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pace").font(.headline)
            Chart {
                ForEach(series) { p in
                    LineMark(x: .value("Distanz", p.km), y: .value("Pace", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)
                }
                if average > 0 {
                    RuleMark(y: .value("Ø", average))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ø \(Format.pace(average))").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Format.pace(v)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(v.formatted()) km") }
                    }
                }
            }
            .frame(height: 180)
        }
    }
}

struct HeartRateCard: View {
    let series: [RunAnalysis.SeriesPoint]
    let average: Double
    let maximum: Double
    let zoneTimes: [TimeInterval]
    let maxHeartRate: Double

    private static let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    var body: some View {
        let total = zoneTimes.reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Herzfrequenz").font(.headline)
                Spacer()
                if maximum > 0 {
                    Text("max. \(Int(maximum.rounded())) bpm").font(.caption).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(series) { p in
                    LineMark(x: .value("Distanz", p.km), y: .value("bpm", p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.red)
                }
                if average > 0 {
                    RuleMark(y: .value("Ø", average))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ø \(Int(average.rounded()))").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(v.formatted()) km") } }
                }
            }
            .frame(height: 160)

            if total > 0 {
                Text("Zeit in Zonen").font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(HeartRateZones.zones.reversed()) { zone in
                    let time = zoneTimes[zone.index - 1]
                    HStack(spacing: 8) {
                        Text("Z\(zone.index)").font(.caption.bold()).frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(zone.name).font(.caption)
                                Text("\(Int(zone.lower * maxHeartRate))–\(Int(zone.upper * maxHeartRate))")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.duration(time)).font(.caption.monospacedDigit())
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Self.zoneColors[zone.index - 1])
                                    .frame(width: max(4, geo.size.width * time / total))
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
    }
}

struct CadenceChart: View {
    let series: [RunAnalysis.SeriesPoint]
    let average: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schrittfrequenz").font(.headline)
            Chart {
                ForEach(series) { p in
                    PointMark(x: .value("Distanz", p.km), y: .value("spm", p.value))
                        .symbolSize(12)
                        .foregroundStyle(.purple)
                }
                if average > 0 {
                    RuleMark(y: .value("Ø", average))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Ø \(Int(average.rounded())) spm").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(v.formatted()) km") } }
                }
            }
            .frame(height: 140)
        }
    }
}

struct ElevationChart: View {
    let series: [RunAnalysis.SeriesPoint]

    var body: some View {
        let minAlt = (series.map(\.value).min() ?? 0) - 5
        VStack(alignment: .leading, spacing: 8) {
            Text("Höhenprofil").font(.headline)
            Chart(series) { p in
                AreaMark(x: .value("Distanz", p.km),
                         yStart: .value("Basis", minAlt),
                         yEnd: .value("Höhe", p.value))
                    .foregroundStyle(.linearGradient(colors: [.green.opacity(0.5), .green.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Distanz", p.km), y: .value("Höhe", p.value))
                    .foregroundStyle(.green)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v)) m") }
                    }
                }
            }
            .frame(height: 140)
        }
    }
}

struct EditRunView: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") { TextField("Titel", text: $run.title) }
                Section("Notizen") {
                    TextField("Wie lief's?", text: $run.notes, axis: .vertical).lineLimit(3...8)
                }
                Section("Gefühlte Anstrengung") {
                    EffortSlider(effort: $run.perceivedEffort)
                }
            }
            .navigationTitle("Lauf bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

/// Anstrengung 0–10 (0 = keine Angabe).
struct EffortSlider: View {
    @Binding var effort: Int

    private var label: String {
        switch effort {
        case 0: "Keine Angabe"
        case 1...3: "Leicht"
        case 4...6: "Mittel"
        case 7...8: "Hart"
        default: "Maximal"
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Text(effort > 0 ? "\(effort)/10" : "–").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 0...10, step: 1)
        }
    }
}
