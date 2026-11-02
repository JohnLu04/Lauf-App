import SwiftUI

/// Kreis mit den Initialen einer Person (Strava liefert keine verlässlichen Profilbilder).
struct InitialsAvatar: View {
    let name: String
    let initials: String
    var size: CGFloat = 32

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }

    /// Feste Farbe je Name, damit dieselbe Person immer gleich aussieht
    private var color: Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.75)
    }
}

/// Kudos- und Kommentarzahl für die Karte im Feed.
struct SocialCountsView: View {
    let kudos: Int
    let comments: Int

    var body: some View {
        HStack(spacing: 14) {
            if kudos > 0 {
                Label("\(kudos)", systemImage: "hand.thumbsup.fill")
                    .accessibilityLabel(kudos == 1 ? "1 Kudo" : "\(kudos) Kudos")
            }
            if comments > 0 {
                Label("\(comments)", systemImage: "bubble.left.fill")
                    .accessibilityLabel(comments == 1 ? "1 Kommentar" : "\(comments) Kommentare")
            }
        }
        .font(.subheadline.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// Bereich „Kudos & Kommentare“ in der Laufansicht.
struct RunSocialCard: View {
    let run: Run
    var isLoading = false
    @State private var showKudos = false

    var body: some View {
        let kudoers = run.kudoers
        let comments = run.comments
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Kudos & Kommentare").font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }

            if run.kudosCount > 0 {
                Button { showKudos = true } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: -5) {
                            ForEach(Array(kudoers.prefix(5).enumerated()), id: \.offset) { _, kudoer in
                                InitialsAvatar(name: kudoer.name, initials: kudoer.initials, size: 30)
                                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            }
                        }
                        Label(run.kudosCount == 1 ? "1 Kudo" : "\(run.kudosCount) Kudos", systemImage: "hand.thumbsup.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !comments.isEmpty {
                if run.kudosCount > 0 { Divider() }
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        InitialsAvatar(name: comment.name, initials: comment.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(comment.name.isEmpty ? "Strava-Nutzer" : comment.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(comment.date, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.text).font(.subheadline)
                        }
                    }
                }
            } else if run.commentCount > 0 {
                Text(run.commentCount == 1 ? "1 Kommentar" : "\(run.commentCount) Kommentare")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let url = run.stravaURL {
                Link(destination: url) {
                    Label("In Strava antworten", systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showKudos) {
            KudosListView(kudoers: kudoers, total: run.kudosCount)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Liste aller Personen, die Kudos gegeben haben.
struct KudosListView: View {
    let kudoers: [StravaKudoer]
    let total: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(kudoers.enumerated()), id: \.offset) { _, kudoer in
                        HStack(spacing: 12) {
                            InitialsAvatar(name: kudoer.name, initials: kudoer.initials, size: 36)
                            Text(kudoer.name.isEmpty ? "Strava-Nutzer" : kudoer.name)
                        }
                    }
                } footer: {
                    if kudoers.count < total {
                        Text(kudoers.isEmpty
                             ? "Die Namen werden geladen, sobald eine Verbindung zu Strava besteht."
                             : "Nicht alle Namen konnten von Strava geladen werden.")
                    }
                }
            }
            .navigationTitle(total == 1 ? "1 Kudo" : "\(total) Kudos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
