import SwiftUI
import AVKit

/// Lädt ein lokal gespeichertes Foto verkleinert im Hintergrund.
struct LocalPhotoView: View {
    let url: URL
    var maxPixelSize = 600
    var contentMode: ContentMode = .fill
    var background = Color(.tertiarySystemFill)

    @State private var image: UIImage?

    var body: some View {
        // Das Bild liegt als Overlay auf einer Fläche, damit es die vorgegebene Größe nur füllt
        // und das umgebende Layout nicht aufbläht.
        background
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .clipped()
            .task(id: url) {
            let url = url, size = maxPixelSize
            let cgImage = await Task.detached(priority: .userInitiated) {
                RunPhotoStore.thumbnail(at: url, maxPixelSize: size)
            }.value
            image = cgImage.map { UIImage(cgImage: $0) }
        }
    }
}

/// Play-Symbol über dem Standbild eines Videos.
struct VideoBadge: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.black.opacity(0.45), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Galerie in der Laufansicht; Antippen öffnet die Vollbildansicht.
struct RunPhotoGallery: View {
    let run: Run
    let photos: [RunPhoto]
    @State private var selection: RunPhoto?

    private var title: String {
        let videos = photos.filter(\.video).count
        let images = photos.count - videos
        switch (images, videos) {
        case (_, 0): return images == 1 ? "Foto" : "Fotos (\(images))"
        case (0, _): return videos == 1 ? "Video" : "Videos (\(videos))"
        default: return "Fotos & Videos (\(photos.count))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button {
                            selection = photo
                        } label: {
                            LocalPhotoView(url: run.photoURL(photo), maxPixelSize: 500)
                                .frame(width: photos.count == 1 ? 300 : 150, height: 150)
                                .overlay { if photo.video { VideoBadge() } }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel((photo.video ? "Video" : "Foto") + (photo.caption.map { ": \($0)" } ?? ""))
                    }
                }
            }
        }
        .fullScreenCover(item: $selection) { photo in
            PhotoViewer(run: run, photos: photos, selection: photo)
        }
    }
}

/// Vollbildansicht zum Durchwischen der Fotos und Videos eines Laufs.
struct PhotoViewer: View {
    let run: Run
    let photos: [RunPhoto]
    @State var selection: RunPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    // Bild bzw. Video bekommt die ganze verfügbare Höhe; das Seitenverhältnis
                    // (auch Hochformat) bleibt erhalten, der Rest wird schwarz aufgefüllt.
                    VStack(spacing: 12) {
                        Group {
                            if photo.video, let videoURL = run.videoURL(photo) {
                                VideoPage(url: videoURL, isActive: selection == photo)
                            } else {
                                LocalPhotoView(url: run.photoURL(photo), maxPixelSize: 2400, contentMode: .fit,
                                               background: .black)
                                    .overlay {
                                        if photo.video { videoOnlyInStrava }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Platz für den Schließen-Knopf, damit er die Player-Bedienelemente nicht verdeckt
                        .padding(.top, 64)
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        // Platz für die Seitenpunkte
                        Color.clear.frame(height: photos.count > 1 ? 50 : 20)
                    }
                    .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Schließen")
        }
    }

    /// Strava gibt die Videodatei nicht heraus: Standbild mit Knopf zum Abspielen in Strava.
    @ViewBuilder
    private var videoOnlyInStrava: some View {
        VStack(spacing: 12) {
            VideoBadge(size: 64)
            if let url = run.stravaURL {
                Link(destination: url) {
                    Label("In Strava ansehen", systemImage: "arrow.up.right.square")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.white)
                }
            } else {
                Text("Dieses Video ist nur in Strava verfügbar.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Spielt ein Video ab, solange seine Seite in der Vollbildansicht sichtbar ist.
private struct VideoPage: View {
    let url: URL
    let isActive: Bool
    @State private var player: AVPlayer?
    /// nil = noch unbekannt
    @State private var hasAudio: Bool?

    var body: some View {
        // Der Player füllt die Fläche und zeigt das Video im richtigen Seitenverhältnis (auch Hochformat).
        VideoPlayer(player: player)
            .overlay(alignment: .bottom) {
                if hasAudio == false {
                    Label("Dieses Video hat keinen Ton", systemImage: "speaker.slash.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.bottom, 70)
                }
            }
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                if isActive { startPlayback() }
            }
            .onChange(of: isActive) { _, active in
                if active { startPlayback() } else { player?.pause() }
            }
            .onDisappear {
                player?.pause()
                // Andere Audio-Apps (Musik, Podcasts) wieder laut stellen
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            .task(id: url) {
                let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
                hasAudio = !(tracks ?? []).isEmpty
            }
    }

    /// Ton wie in der Fotos-App: auch bei Lautlos-Schalter hörbar, andere Audio-Apps pausieren.
    /// Ohne diese Einstellung gilt der iOS-Standard, der im Lautlos-Modus stumm ist.
    private func startPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        player?.isMuted = false
        player?.play()
    }
}
