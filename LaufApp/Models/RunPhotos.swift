import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Foto zu einem Lauf (z. B. von Strava). Die Bilddatei liegt im App-Ordner, nicht in der Datenbank.
struct RunPhoto: Codable, Hashable, Identifiable {
    /// Strava-ID des Fotos (bzw. eine eigene ID)
    var id: String
    var fileName: String
    var caption: String?
}

/// Speichert Lauf-Fotos als Dateien unter "Application Support/RunPhotos/<Lauf-ID>/".
enum RunPhotoStore {
    static var baseURL: URL {
        URL.applicationSupportDirectory.appending(path: "RunPhotos", directoryHint: .isDirectory)
    }

    static func folder(for runID: UUID) -> URL {
        baseURL.appending(path: runID.uuidString, directoryHint: .isDirectory)
    }

    static func url(for photo: RunPhoto, runID: UUID) -> URL {
        folder(for: runID).appending(path: photo.fileName)
    }

    /// Speichert die Bilddaten und gibt den Dateinamen zurück.
    static func save(_ data: Data, photoID: String, runID: UUID) throws -> String {
        let folder = folder(for: runID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = photoID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let fileName = (safeID.isEmpty ? UUID().uuidString : safeID) + ".jpg"
        try data.write(to: folder.appending(path: fileName), options: .atomic)
        return fileName
    }

    static func deleteAll(for runID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: runID))
    }

    /// Verkleinertes Bild für Vorschauen, ohne das ganze Foto in den Speicher zu laden.
    static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
