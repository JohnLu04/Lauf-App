import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    var body: some View {
        NavigationStack {
            ScrollView {
                if runs.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Läufe", systemImage: "figure.run")
                    } description: {
                        Text("Starte deinen ersten Lauf im Tab „Aufnehmen“. Er erscheint danach hier.")
                    }
                    .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 12) {
                        WeekSummaryCard(runs: runs)
                        ForEach(runs) { run in
                            NavigationLink(value: run) {
                                RunCardView(run: run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aktivitäten")
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
        }
    }
}

/// Wochenübersicht oben im Feed: km pro Tag und Summen.
struct WeekSummaryCard: View {
    let runs: [Run]
    private let cal = Calendar.mondayFirst

    var body: some View {
        let weekStart = cal.startOfWeek(for: .now)
        let thisWeek = runs.filter { $0.startDate >= weekStart }
        let perDay: [Double] = (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: weekStart)!
            return thisWeek.filter { cal.isDate($0.startDate, inSameDayAs: day) }.reduce(0) { $0 + $1.distance }
        }
        let maxDay = max(perDay.max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 12) {
            Text("Diese Woche").font(.headline)
            HStack {
                StatView(label: "Distanz", value: Format.kilometers(thisWeek.reduce(0) { $0 + $1.distance }, decimals: 1), unit: "km", large: true)
                StatView(label: "Zeit", value: Format.duration(thisWeek.reduce(0) { $0 + $1.movingTime }), large: true)
                StatView(label: "Läufe", value: "\(thisWeek.count)", large: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(perDay[i] > 0 ? Color.accentColor : Color(.tertiarySystemFill))
                            .frame(height: max(4, 40 * perDay[i] / maxDay))
                        Text(["M", "D", "M", "D", "F", "S", "S"][i])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
        .card()
    }
}

struct RunCardView: View {
    let run: Run

    private var date: some View {
        Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.title).font(.headline)
                    // Herkunft neben dem Datum, bei wenig Platz darunter
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            date
                            RunSourceBadges(run: run)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            date
                            RunSourceBadges(run: run)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HStack {
                StatView(label: "Distanz", value: Format.kilometers(run.distance), unit: "km")
                StatView(label: "Pace", value: Format.pace(run.averagePace), unit: "/km")
                StatView(label: "Zeit", value: Format.duration(run.movingTime))
            }
            let photos = run.photos
            HStack(spacing: 6) {
                RouteMapView(points: run.route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let first = photos.first {
                    LocalPhotoView(url: run.photoURL(first), maxPixelSize: 500)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay { if first.video { VideoBadge(size: 38) } }
                        .overlay(alignment: .bottomTrailing) {
                            if photos.count > 1 {
                                Label("\(photos.count)", systemImage: "photo.on.rectangle")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(6)
                            }
                        }
                        .clipped()
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if run.kudosCount > 0 || run.commentCount > 0 {
                SocialCountsView(kudos: run.kudosCount, comments: run.commentCount)
            }
        }
        .card()
    }
}
