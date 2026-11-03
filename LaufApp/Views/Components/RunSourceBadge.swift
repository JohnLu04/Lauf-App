import SwiftUI

/// Kleine Plakette, die zeigt, woher ein Lauf stammt (LaufApp, Strava, Apple Health).
struct RunSourceBadge: View {
    let source: RunSource

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(source.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .fixedSize()
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
        .accessibilityLabel(source == .app ? "Mit LaufApp aufgezeichnet" : "Importiert aus \(source.name)")
    }

    private var icon: String {
        switch source {
        case .app: "record.circle"
        case .strava: "arrow.triangle.2.circlepath"
        case .health: "heart.fill"
        }
    }

    private var color: Color {
        switch source {
        case .app: .accentColor
        case .strava: Color(red: 0.99, green: 0.30, blue: 0.01)   // Strava-Orange
        case .health: Color(red: 0.98, green: 0.17, blue: 0.33)   // Health-Rot
        }
    }
}

/// Alle Herkünfte eines Laufs nebeneinander.
struct RunSourceBadges: View {
    let run: Run

    var body: some View {
        HStack(spacing: 4) {
            ForEach(run.sources) { RunSourceBadge(source: $0) }
        }
    }
}
