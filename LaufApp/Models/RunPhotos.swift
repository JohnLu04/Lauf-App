import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Foto oder Video zu einem Lauf (z. B. von Strava). Dateien liegen im App-Ordner, nicht in der Datenbank.
struct RunPhoto: Codable, Hashable, Identifiable {
    /// Strava-ID des Fotos (bzw. eine eigene ID)
    var id: String
    /// Bild; bei Videos das Standbild
    var fileName: String
    var caption: String?
    /// true bei Videos (fehlt bei älteren Einträgen)
    var isVideo: Bool?
    /// Heruntergeladene Videodatei
    var videoFileName: String?
    /// Video-Adresse zum Streamen, wenn es keine Datei zum Herunterladen gibt
    var videoRemoteURL: String?

    var video: Bool { isVideo ?? false }
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

    /// Speichert die Daten und gibt den Dateinamen zurück.
    static func save(_ data: Data, photoID: String, runID: UUID, fileExtension: String = "jpg") throws -> String {
        let folder = folder(for: runID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = photoID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let fileName = (safeID.isEmpty ? UUID().uuidString : safeID) + "." + fileExtension
        try data.write(to: folder.appending(path: fileName), options: .atomic)
        return fileName
    }

    /// Verschiebt eine heruntergeladene Datei (z. B. ein Video) in den Ordner des Laufs.
    static func move(_ file: URL, photoID: String, runID: UUID, fileExtension: String) throws -> String {
        let folder = folder(for: runID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = photoID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let fileName = (safeID.isEmpty ? UUID().uuidString : safeID) + "." + fileExtension
        let target = folder.appending(path: fileName)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: file, to: target)
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
