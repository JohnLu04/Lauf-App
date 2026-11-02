import Foundation
import Observation
import SwiftData

/// Verbindung zu Strava: Anmeldung (OAuth), Token-Verwaltung und Import neuer Läufe.
/// Client-ID und Client-Secret stammen aus der eigenen API-Anwendung des Nutzers;
/// das Secret und die Tokens liegen im Schlüsselbund.
@MainActor
@Observable
final class StravaSync {
    static let shared = StravaSync()

    static let callbackScheme = "laufapp"
    static let callbackDomain = "localhost"
    static let redirectURI = "\(callbackScheme)://\(callbackDomain)"

    enum SyncError: LocalizedError {
        case missingCredentials
        case denied
        case missingScope
        case notConnected
        case rateLimited
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .missingCredentials: "Bitte trage zuerst Client-ID und Client-Secret deiner Strava-API-Anwendung ein."
            case .denied: "Die Verbindung wurde bei Strava nicht erlaubt."
            case .missingScope: "Bitte erlaube bei Strava das Lesen deiner Aktivitäten (auch „Nur ich“), sonst kann LaufApp keine Läufe importieren."
            case .notConnected: "LaufApp ist nicht mit Strava verbunden."
            case .rateLimited: "Strava-Limit erreicht. Die restlichen Läufe werden beim nächsten Synchronisieren importiert."
            case let .http(code) where code == 401: "Strava hat die Anmeldung abgelehnt (401). Prüfe Client-ID und Client-Secret und verbinde dich erneut."
            case let .http(code): "Strava hat mit Fehler \(code) geantwortet. Versuch es später noch einmal."
            }
        }
    }

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Double
    }

    private struct TokenResponse: Decodable {
        struct Athlete: Decodable { let firstname: String?; let lastname: String? }
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double
        let athlete: Athlete?
    }

    private let tokensKey = "strava.tokens"
    private let secretKey = "strava.clientSecret"
    private let defaults = UserDefaults.standard

    private(set) var isConnected = false
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastResult: String?

    private init() {
        isConnected = Keychain.data(for: tokensKey) != nil
    }

    // MARK: - Einstellungen

    var clientID: String {
        get { defaults.string(forKey: "strava.clientID") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "strava.clientID") }
    }

    var clientSecret: String {
        get { Keychain.string(for: secretKey) ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            Keychain.setString(value.isEmpty ? nil : value, for: secretKey)
        }
    }

    var hasCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    var athleteName: String? { defaults.string(forKey: "strava.athleteName") }

    /// Beim ersten Synchronisieren werden die Läufe dieser letzten Tage importiert.
    var initialImportDays: Int {
        get { defaults.object(forKey: "strava.initialDays") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "strava.initialDays") }
    }

    /// Start des zuletzt importierten Laufs; neue Läufe werden ab hier abgefragt.
    private var syncedUntil: Date? {
        get { defaults.object(forKey: "strava.syncedUntil") as? Date }
        set { defaults.set(newValue, forKey: "strava.syncedUntil") }
    }

    private(set) var lastSyncDate: Date? {
        get { defaults.object(forKey: "strava.lastSync") as? Date }
        set { defaults.set(newValue, forKey: "strava.lastSync") }
    }

    // MARK: - Anmeldung

    /// Adresse der Strava-Anmeldeseite.
    var authorizeURL: URL? {
        guard !clientID.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all"),
        ]
        return components.url
    }

    /// Verarbeitet die Rückleitung von Strava (`laufapp://localhost?code=…&scope=…`).
    func handleCallback(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if item("error") != nil { throw SyncError.denied }
        guard let code = item("code") else { throw SyncError.denied }
        guard let scope = item("scope"), scope.contains("activity:read") else { throw SyncError.missingScope }
        let response = try await requestToken(["code": code, "grant_type": "authorization_code"])
        let name = [response.athlete?.firstname, response.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        defaults.set(name.isEmpty ? nil : name, forKey: "strava.athleteName")
        lastError = nil
    }

    /// Trennt die Verbindung. Bereits importierte Läufe bleiben erhalten.
    func disconnect() async {
        if let tokens = loadTokens() {
            var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/deauthorize")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        Keychain.set(nil, for: tokensKey)
        defaults.removeObject(forKey: "strava.athleteName")
        syncedUntil = nil
        lastSyncDate = nil
        lastResult = nil
        lastError = nil
        isConnected = false
    }

    private func loadTokens() -> Tokens? {
        Keychain.data(for: tokensKey).flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }
    }

    @discardableResult
    private func requestToken(_ parameters: [String: String]) async throws -> TokenResponse {
        guard hasCredentials else { throw SyncError.missingCredentials }
        var request = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = (["client_id": clientID, "client_secret": clientSecret].merging(parameters) { $1 })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SyncError.http(status) }
        let token = try StravaImport.decoder.decode(TokenResponse.self, from: data)
        let tokens = Tokens(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: token.expiresAt)
        Keychain.set(try JSONEncoder().encode(tokens), for: tokensKey)
        isConnected = true
        return token
    }

    /// Gültiges Zugriffstoken; läuft es in der nächsten Minute ab, wird es erneuert.
    private func accessToken() async throws -> String {
        guard let tokens = loadTokens() else { throw SyncError.notConnected }
        if tokens.expiresAt > Date().timeIntervalSince1970 + 60 { return tokens.accessToken }
        return try await requestToken(["refresh_token": tokens.refreshToken, "grant_type": "refresh_token"]).accessToken
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T? {
        var components = URLComponents(string: "https://www.strava.com/api/v3" + path)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try StravaImport.decoder.decode(T.self, from: data)
        case 404: return nil
        case 429: throw SyncError.rateLimited
        case let code: throw SyncError.http(code)
        }
    }

    // MARK: - Fotos

    /// Lädt Fotos und Videos einer Strava-Aktivität herunter und speichert sie beim Lauf.
    /// Bereits vorhandene Einträge werden nicht erneut geladen, aber aktualisiert, falls sich
    /// herausstellt, dass sie Videos sind (ältere Versionen haben Videos als Fotos gespeichert).
    /// Gibt die Anzahl neuer oder aktualisierter Einträge zurück.
    @discardableResult
    func importPhotos(for run: Run, activityID: Int) async throws -> Int {
        let photos: [StravaImport.Photo] = try await get("/activities/\(activityID)/photos", query: [
            URLQueryItem(name: "photo_sources", value: "true"),
            URLQueryItem(name: "size", value: String(StravaImport.photoSize)),
        ]) ?? []
        return try await mergePhotos(photos, into: run)
    }

    /// Gleicht die Strava-Liste mit den gespeicherten Einträgen ab: lädt neue Fotos/Videos,
    /// stellt fehlende Dateien wieder her und ergänzt Video-Informationen.
    func mergePhotos(_ photos: [StravaImport.Photo], into run: Run) async throws -> Int {
        var stored = run.photos
        var changed = 0
        for photo in photos where !photo.isPlaceholder {
            guard let id = photo.identifier else { continue }
            if let index = stored.firstIndex(where: { $0.id == id }) {
                let before = stored[index]
                var restoredImage = false
                // Fehlende Bilddatei neu laden (z. B. nach einer Neuinstallation der App)
                let imageURL = RunPhotoStore.url(for: stored[index], runID: run.id)
                if !FileManager.default.fileExists(atPath: imageURL.path), let url = photo.bestURL {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty {
                        stored[index].fileName = try RunPhotoStore.save(data, photoID: id, runID: run.id)
                        restoredImage = true
                    }
                }
                // Video-Informationen ergänzen bzw. fehlende Videodatei neu laden
                if photo.isVideo {
                    stored[index].isVideo = true
                    let videoMissing = stored[index].videoFileName.map {
                        !FileManager.default.fileExists(atPath: RunPhotoStore.folder(for: run.id).appending(path: $0).path)
                    } ?? true
                    if videoMissing {
                        stored[index].videoFileName = nil
                        await attachVideo(photo, to: &stored[index], runID: run.id)
                    }
                }
                if restoredImage || stored[index] != before { changed += 1 }
                continue
            }
            guard let url = photo.bestURL else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { continue }
            let fileName = try RunPhotoStore.save(data, photoID: id, runID: run.id)
            var entry = RunPhoto(id: id, fileName: fileName, caption: photo.caption, isVideo: photo.isVideo ? true : nil)
            if photo.isVideo { await attachVideo(photo, to: &entry, runID: run.id) }
            stored.append(entry)
            changed += 1
        }
        if changed > 0 { run.photos = stored }
        return changed
    }

    /// Lädt die Videodatei herunter oder merkt sich die Stream-Adresse. Ohne Adresse bleibt nur
    /// das Standbild; das Video wird dann in Strava geöffnet.
    private func attachVideo(_ photo: StravaImport.Photo, to entry: inout RunPhoto, runID: UUID) async {
        guard let videoURL = photo.videoURL else { return }
        guard photo.isDownloadableVideo else {
            entry.videoRemoteURL = videoURL.absoluteString
            return
        }
        do {
            let (file, response) = try await URLSession.shared.download(from: videoURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                entry.videoRemoteURL = videoURL.absoluteString
                return
            }
            let ext = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension.lowercased()
            entry.videoFileName = try RunPhotoStore.move(file, photoID: entry.id + "-video", runID: runID, fileExtension: ext)
        } catch {
            // Download fehlgeschlagen: wenigstens streamen versuchen
            entry.videoRemoteURL = videoURL.absoluteString
        }
    }

    /// Lädt fehlende Bild- und Videodateien aller Strava-Läufe neu.
    /// Gibt die Anzahl der Läufe zurück, bei denen etwas wiederhergestellt wurde.
    func repairMissingPhotos(context: ModelContext) async -> (repaired: Int, failed: Int) {
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        var repaired = 0, failed = 0
        for run in runs where run.stravaID != nil && run.hasMissingPhotoFiles {
            guard let activityID = run.stravaID else { continue }
            if (try? await importPhotos(for: run, activityID: activityID)) != nil, !run.hasMissingPhotoFiles {
                repaired += 1
            } else {
                failed += 1
            }
        }
        try? context.save()
        return (repaired, failed)
    }

    /// Holt Fotos nach, die nach dem Import bei Strava hinzugefügt wurden.
    func refreshPhotos(for run: Run, context: ModelContext) async throws -> Int {
        guard let activityID = run.stravaID else { return 0 }
        let added = try await importPhotos(for: run, activityID: activityID)
        try? context.save()
        return added
    }

    // MARK: - Kudos und Kommentare

    /// Übernimmt die Zahlen von Strava und lädt die Listen nur, wenn sie nicht mehr dazu passen
    /// (oder `force` gesetzt ist). Gibt true zurück, wenn sich etwas geändert hat.
    @discardableResult
    func updateSocial(for run: Run, kudosCount: Int, commentCount: Int, force: Bool = false) async throws -> Bool {
        guard let activityID = run.stravaID else { return false }
        let before = (run.kudosCount, run.commentCount, run.kudoers, run.comments)
        run.kudosCount = kudosCount
        run.commentCount = commentCount

        if kudosCount == 0 {
            if !run.kudosData.isEmpty { run.kudoers = [] }
        } else if force || run.kudoers.count != kudosCount {
            let athletes: [StravaImport.Athlete] = try await get("/activities/\(activityID)/kudos", query: [
                URLQueryItem(name: "per_page", value: "200"),
            ]) ?? []
            run.kudoers = athletes.map(StravaImport.kudoer)
        }

        if commentCount == 0 {
            if !run.commentsData.isEmpty { run.comments = [] }
        } else if force || run.comments.count != commentCount {
            let comments: [StravaImport.Comment] = try await get("/activities/\(activityID)/comments", query: [
                URLQueryItem(name: "per_page", value: "200"),
                URLQueryItem(name: "page_size", value: "200"),
            ]) ?? []
            run.comments = comments.map(StravaImport.comment).sorted { $0.date < $1.date }
        }
        return before != (run.kudosCount, run.commentCount, run.kudoers, run.comments)
    }

    /// Lädt die Listen nach, wenn sie nicht zu den gespeicherten Zahlen passen (z. B. weil sie beim
    /// Import wegen des Strava-Limits fehlten oder nur die Zahlen nachgetragen wurden).
    @discardableResult
    func loadMissingSocial(for run: Run, context: ModelContext) async throws -> Bool {
        guard run.needsSocialRefresh else { return false }
        let changed = try await updateSocial(for: run, kudosCount: run.kudosCount, commentCount: run.commentCount)
        try? context.save()
        return changed
    }

    /// Fragt die aktuellen Zahlen der Aktivität ab und lädt Kudos und Kommentare neu.
    @discardableResult
    func refreshSocial(for run: Run, context: ModelContext) async throws -> Bool {
        guard let activityID = run.stravaID else { return false }
        guard let activity: StravaImport.Activity = try await get("/activities/\(activityID)") else { return false }
        let changed = try await updateSocial(for: run, kudosCount: activity.kudosCount ?? 0,
                                             commentCount: activity.commentCount ?? 0, force: true)
        try? context.save()
        return changed
    }

    /// Kudos und Kommentare kommen oft erst Stunden nach dem Lauf: Läufe der letzten 7 Tage
    /// werden deshalb bei jedem Synchronisieren aktualisiert. Beim ersten Mal werden außerdem
    /// die Zahlen aller älteren Strava-Läufe nachgetragen (die Listen lädt die Laufansicht).
    private func refreshRecentSocial(runs: [Run]) async throws {
        let byID = Dictionary(runs.compactMap { run in run.stravaID.map { ($0, run) } }, uniquingKeysWith: { a, _ in a })
        guard !byID.isEmpty else { return }

        if !defaults.bool(forKey: "strava.socialBackfill"), let oldest = runs.compactMap({ $0.stravaID != nil ? $0.startDate : nil }).min() {
            for page in 1...5 {
                let batch: [StravaImport.Activity] = try await get("/athlete/activities", query: [
                    URLQueryItem(name: "after", value: String(Int(oldest.timeIntervalSince1970) - 86_400)),
                    URLQueryItem(name: "per_page", value: "200"),
                    URLQueryItem(name: "page", value: String(page)),
                ]) ?? []
                for activity in batch {
                    guard let run = byID[activity.id] else { continue }
                    run.kudosCount = activity.kudosCount ?? 0
                    run.commentCount = activity.commentCount ?? 0
                }
                if batch.count < 200 { break }
            }
            defaults.set(true, forKey: "strava.socialBackfill")
        }

        let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
        let recent: [StravaImport.Activity] = try await get("/athlete/activities", query: [
            URLQueryItem(name: "after", value: String(Int(weekAgo.timeIntervalSince1970))),
            URLQueryItem(name: "per_page", value: "50"),
        ]) ?? []
        for activity in recent {
            guard let run = byID[activity.id] else { continue }
            try await updateSocial(for: run, kudosCount: activity.kudosCount ?? 0, commentCount: activity.commentCount ?? 0)
        }
    }

    // MARK: - Import

    /// Synchronisiert höchstens alle 5 Minuten (z. B. beim Öffnen der App).
    func syncIfNeeded(context: ModelContext) async {
        guard isConnected, !isSyncing else { return }
        if let last = lastSyncDate, Date().timeIntervalSince(last) < 300 { return }
        await sync(context: context)
    }

    /// Importiert alle neuen Läufe seit dem letzten Import (älteste zuerst).
    func sync(context: ModelContext) async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let since = syncedUntil
            ?? Calendar.current.date(byAdding: .day, value: -initialImportDays, to: .now) ?? .now
        var imported = 0
        do {
            var activities: [StravaImport.Activity] = []
            for page in 1...4 {
                let batch: [StravaImport.Activity] = try await get("/athlete/activities", query: [
                    URLQueryItem(name: "after", value: String(Int(since.timeIntervalSince1970))),
                    URLQueryItem(name: "per_page", value: "50"),
                    URLQueryItem(name: "page", value: String(page)),
                ]) ?? []
                activities += batch
                if batch.count < 50 { break }
            }

            let existing = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            let knownIDs = Set(existing.compactMap(\.stravaID))
            for activity in activities.filter(\.isRun).sorted(by: { $0.startDate < $1.startDate }) {
                defer { syncedUntil = max(syncedUntil ?? .distantPast, activity.startDate) }
                if knownIDs.contains(activity.id) || StravaImport.isDuplicate(activity, of: existing) { continue }
                let streams: StravaImport.Streams? = try await get("/activities/\(activity.id)/streams", query: [
                    URLQueryItem(name: "keys", value: StravaImport.streamKeys),
                    URLQueryItem(name: "key_by_type", value: "true"),
                ])
                let run = StravaImport.makeRun(activity: activity, streams: streams)
                context.insert(run)
                if (activity.totalPhotoCount ?? 0) > 0 {
                    // Fotos sind ein Extra: Fehler hier sollen den Import nicht abbrechen
                    try? await importPhotos(for: run, activityID: activity.id)
                }
                // Kudos und Kommentare ebenfalls nur als Extra; fehlende Listen werden später nachgeladen
                run.kudosCount = activity.kudosCount ?? 0
                run.commentCount = activity.commentCount ?? 0
                try? await updateSocial(for: run, kudosCount: run.kudosCount, commentCount: run.commentCount)
                try? context.save()
                imported += 1
            }
            if syncedUntil == nil { syncedUntil = since }
            // Neue Kudos und Kommentare der letzten Tage; Fehler hier sollen den Import nicht als fehlgeschlagen melden
            if let runs = try? context.fetch(FetchDescriptor<Run>()) {
                try? await refreshRecentSocial(runs: runs)
                try? context.save()
            }
            lastSyncDate = .now
            lastResult = imported == 0 ? "Keine neuen Läufe." : (imported == 1 ? "1 neuer Lauf importiert." : "\(imported) neue Läufe importiert.")
        } catch {
            lastSyncDate = .now
            lastError = error.localizedDescription
            if imported > 0 { lastResult = "\(imported) Läufe importiert." }
        }
    }
}
