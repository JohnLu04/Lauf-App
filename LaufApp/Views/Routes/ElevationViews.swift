import SwiftUI
import Charts

/// „↑ 120 m ↓ 118 m“
struct ElevationLabel: View {
    let gain: Double
    var loss: Double?

    var body: some View {
        HStack(spacing: 6) {
            Label("\(Int(gain.rounded())) m", systemImage: "arrow.up.right")
            if let loss { Label("\(Int(loss.rounded())) m", systemImage: "arrow.down.right") }
        }
        .labelStyle(CompactLabelStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(gain.rounded())) Höhenmeter bergauf" + (loss.map { ", \(Int($0.rounded())) bergab" } ?? ""))
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Kleines Höhenprofil ohne Achsen, mit tiefster und höchster Höhe.
struct ElevationMiniChart: View {
    let profile: ElevationProfile

    var body: some View {
        let low = profile.elevations.min() ?? 0, high = profile.elevations.max() ?? 0
        HStack(alignment: .center, spacing: 6) {
            Chart(profile.series) { p in
                AreaMark(x: .value("km", p.km), yStart: .value("Basis", low - 5), yEnd: .value("Höhe", p.value))
                    .foregroundStyle(.linearGradient(colors: [.green.opacity(0.45), .green.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("km", p.km), y: .value("Höhe", p.value))
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - 5)...(max(high, low + 20)))
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(high)) m")
                Spacer(minLength: 0)
                Text("\(Int(low)) m")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Höhenprofil von \(Int(low)) bis \(Int(high)) Meter")
    }
}
