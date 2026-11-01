import SwiftUI

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

/// Fotogalerie in der Laufansicht; Antippen öffnet die Vollbildansicht.
struct RunPhotoGallery: View {
    let run: Run
    let photos: [RunPhoto]
    @State private var selection: RunPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(photos.count == 1 ? "Foto" : "Fotos (\(photos.count))").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button {
                            selection = photo
                        } label: {
                            LocalPhotoView(url: run.photoURL(photo), maxPixelSize: 500)
                                .frame(width: photos.count == 1 ? 300 : 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.caption ?? "Foto")
                    }
                }
            }
        }
        .fullScreenCover(item: $selection) { photo in
            PhotoViewer(run: run, photos: photos, selection: photo)
        }
    }
}

/// Vollbildansicht zum Durchwischen der Fotos eines Laufs.
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
                    VStack {
                        Spacer()
                        LocalPhotoView(url: run.photoURL(photo), maxPixelSize: 2400, contentMode: .fit,
                                       background: .black)
                        Spacer()
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
}
