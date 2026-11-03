import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Vom Nutzer gewähltes Foto oder Video, das beim Speichern an einen Lauf angehängt wird.
/// Die Dateien liegen bis dahin im temporären Ordner.
struct PendingPhoto: Identifiable, Hashable {
    let id = UUID()
    /// JPEG; bei Videos das Standbild
    var imageFile: URL
    var videoFile: URL?

    var isVideo: Bool { videoFile != nil }

    /// Temporäre Dateien entfernen (wenn das Foto doch nicht angehängt wird)
    func discard() {
        try? FileManager.default.removeItem(at: imageFile)
        if let videoFile { try? FileManager.default.removeItem(at: videoFile) }
    }
}

/// Video aus der Fotomediathek als Datei (wird in den temporären Ordner kopiert).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension.lowercased()
            let target = PhotoAttachment.temporaryURL(extension: ext)
            try FileManager.default.copyItem(at: received.file, to: target)
            return Self(url: target)
        }
    }
}

/// Eigene Fotos und Videos zu einem Lauf: aus der Mediathek oder der Kamera übernehmen und speichern.
enum PhotoAttachment {
    /// Längste Kante gespeicherter Fotos in Pixeln (spart Speicher, reicht für die Vollbildansicht)
    static let maxPixelSize = 2560

    static func temporaryURL(extension ext: String) -> URL {
        let folder = URL.temporaryDirectory.appending(path: "PendingPhotos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: UUID().uuidString + "." + ext)
    }

    /// Mehrere Fotos und Videos gleichzeitig laden (Reihenfolge der Auswahl bleibt erhalten).
    static func load(_ items: [PhotosPickerItem]) async -> [PendingPhoto] {
        await withTaskGroup(of: (Int, PendingPhoto?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, await load(item)) }
            }
            var results: [(Int, PendingPhoto)] = []
            for await (index, photo) in group {
                if let photo { results.append((index, photo)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Foto oder Video aus der Mediathek laden; nil, wenn es sich nicht lesen lässt.
    static func load(_ item: PhotosPickerItem) async -> PendingPhoto? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return await Task.detached(priority: .userInitiated) { pending(imageData: data) }.value
        }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        guard let still = await videoStill(movie.url) else {
            try? FileManager.default.removeItem(at: movie.url)
            return nil
        }
        return PendingPhoto(imageFile: still, videoFile: movie.url)
    }

    /// Foto (z. B. von der Kamera) verkleinert als JPEG im temporären Ordner ablegen.
    static func pending(imageData data: Data) -> PendingPhoto? {
        guard let jpeg = jpeg(from: data) else { return nil }
        let url = temporaryURL(extension: "jpg")
        guard (try? jpeg.write(to: url, options: .atomic)) != nil else { return nil }
        return PendingPhoto(imageFile: url)
    }

    /// Verkleinert ein Bild (HEIC, JPEG, PNG …) auf `maxPixelSize`, richtet es auf und kodiert es als JPEG.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Standbild eines Videos (nach einer halben Sekunde, damit es nicht schwarz ist).
    static func videoStill(_ url: URL) async -> URL? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { return nil }
        let still = temporaryURL(extension: "jpg")
        guard (try? data.write(to: still, options: .atomic)) != nil else { return nil }
        return still
    }

    /// Hängt die gewählten Fotos und Videos an den Lauf an (verschiebt die Dateien in seinen Ordner).
    @discardableResult
    static func attach(_ pending: [PendingPhoto], to run: Run) -> Int {
        var photos = run.photos
        var added = 0
        for item in pending {
            let id = RunPhoto.ownPrefix + UUID().uuidString
            guard let fileName = try? RunPhotoStore.move(item.imageFile, photoID: id, runID: run.id, fileExtension: "jpg")
            else { item.discard(); continue }
            var photo = RunPhoto(id: id, fileName: fileName)
            if let video = item.videoFile {
                photo.isVideo = true
                let ext = video.pathExtension.isEmpty ? "mov" : video.pathExtension
                photo.videoFileName = try? RunPhotoStore.move(video, photoID: id + "-video", runID: run.id, fileExtension: ext)
            }
            photos.append(photo)
            added += 1
        }
        if added > 0 { run.photos = photos }
        return added
    }

    /// Entfernt ein eigenes Foto bzw. Video samt Dateien.
    static func remove(_ photo: RunPhoto, from run: Run) {
        let folder = RunPhotoStore.folder(for: run.id)
        try? FileManager.default.removeItem(at: folder.appending(path: photo.fileName))
        if let video = photo.videoFileName { try? FileManager.default.removeItem(at: folder.appending(path: video)) }
        run.photos.removeAll { $0.id == photo.id }
    }
}
