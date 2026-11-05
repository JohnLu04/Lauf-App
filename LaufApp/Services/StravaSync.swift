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
        case missingWritePermission
        case uploadFailed(String)
        case uploadTimeout

        var errorDescription: String? {
            switch self {
            case .missingCredentials: "Bitte trage zuerst Client-ID und Client-Secret deiner Strava-API-Anwendung ein."
            case .denied: "Die Verbindung wurde bei Strava nicht erlaubt."
            case .missingScope: "Bitte erlaube bei Strava das Lesen deiner Aktivitäten (auch „Nur ich“), sonst kann LaufApp keine Läufe importieren."
            case .notConnected: "LaufApp ist nicht mit Strava verbunden."
            case .rateLimited: "Strava-Limit erreicht. Die restlichen Läufe werden beim nächsten Synchronisieren importiert."
            case let .http(code) where code == 401: "Strava hat die Anmeldung abgelehnt (401). Prüfe Client-ID und Client-Secret und verbinde dich erneut."
            case let .http(code): "Strava hat mit Fehler \(code) geantwortet. Versuch es später noch einmal."
            case .missingWritePermission: "Zum Hochladen braucht LaufApp bei Strava die Erlaubnis, Aktivitäten zu erstellen. Tippe in den Strava-Einstellungen auf „Hochladen erlauben“."
            case let .uploadFailed(message): "Strava konnte den Lauf nicht übernehmen: \(message)"
            case .uploadTimeout: "Strava verarbeitet den Lauf noch. Er erscheint gleich in Strava und wird beim nächsten Synchronisieren verknüpft."
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

    /// Darf LaufApp Läufe hochladen? (Ältere Verbindungen haben nur Leserechte und müssen neu erlaubt werden.)
    var canUpload: Bool { isConnected && (defaults.string(forKey: "strava.scope") ?? "").contains("activity:write") }

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
            URLQueryItem(name: "scope", value: "read,activity:read_all,activity:write"),
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
        // Erteilte Rechte merken (Hochladen nur mit „activity:write“)
        defaults.set(scope, forKey: "strava.scope")
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
        defaults.removeObject(forKey: "strava.scope")
        defaults.removeObject(forKey: "strava.gearBackfill")
        defaults.removeObject(forKey: "strava.gearRefresh")
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

    // MARK: - Hochladen

    private struct CreatedActivity: Decodable { let id: Int }

    private struct UploadStatus: Decodable {
        let id: Int
        let error: String?
        let activityId: Int?
    }

    /// Lädt einen in LaufApp aufgezeichneten oder eingetragenen Lauf zu Strava hoch und verknüpft ihn
    /// (damit er beim Synchronisieren nicht doppelt importiert wird). Mit GPS-Strecke als GPX-Datei,
    /// eingetragene Läufe ohne echte Aufzeichnung als manuelle Aktivität (ohne Karte).
    func upload(_ run: Run) async throws {
        guard canUpload else { throw SyncError.missingWritePermission }
        let activityID: Int
        if run.isManual || run.route.count < 2 {
            let created: CreatedActivity = try await send("POST", "/activities", form: [
                "name": run.title,
                "sport_type": "Run",
                "start_date_local": Self.localTimestamp(run.startDate),
                "elapsed_time": String(Int(max(run.elapsedTime, run.movingTime).rounded())),
                "distance": String(format: "%.1f", run.distance),
                "description": run.notes,
            ])
            activityID = created.id
        } else {
            activityID = try await uploadGPX(run)
            // Sportart sicherheitshalber festlegen (GPX-Dateien enthalten sie nur als Hinweis)
            let _: CreatedActivity? = try? await send("PUT", "/activities/\(activityID)", form: ["sport_type": "Run"])
        }
        run.stravaID = activityID
    }

    private func uploadGPX(_ run: Run) async throws -> Int {
        let boundary = "LaufApp-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("data_type", "gpx")
        field("name", run.title)
        field("description", run.notes)
        field("external_id", "laufapp-\(run.id.uuidString).gpx")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"laufapp.gpx\"\r\nContent-Type: application/gpx+xml\r\n\r\n".utf8))
        body.append(RunExport.gpx(for: run))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var status: UploadStatus = try await send("POST", "/uploads", body: body,
                                                  contentType: "multipart/form-data; boundary=\(boundary)")
        // Strava verarbeitet die Datei im Hintergrund; etwa eine Minute auf das Ergebnis warten
        for _ in 0..<30 {
            if let id = status.activityId { return id }
            if let error = status.error {
                // Schon vorhanden (z. B. zweimal hochgeladen): mit der bestehenden Aktivität verknüpfen
                if let range = error.range(of: #"activities/(\d+)"#, options: .regularExpression),
                   let id = Int(error[range].dropFirst("activities/".count)) {
                    return id
                }
                throw SyncError.uploadFailed(error.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            }
            try await Task.sleep(for: .seconds(2))
            guard let next: UploadStatus = try await get("/uploads/\(status.id)") else { break }
            status = next
        }
        throw SyncError.uploadTimeout
    }

    /// Ortszeit ohne Zeitzone, wie Strava sie für `start_date_local` erwartet
    private static func localTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, form: [String: String]) async throws -> T {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        return try await send(method, path, body: Data(body.utf8), contentType: "application/x-www-form-urlencoded")
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data, contentType: String) async throws -> T {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3" + path)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200, 201: return try StravaImport.decoder.decode(T.self, from: data)
        case 429: throw SyncError.rateLimited
        case 401, 403:
            // Fehlende Schreibrechte meldet Strava mit einem Hinweis auf „write“
            if String(decoding: data, as: UTF8.self).contains("write") { throw SyncError.missingWritePermission }
            throw SyncError.http(code)
        default:
            throw SyncError.http(code)
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

    // MARK: - Schuhe

    /// Schuhe aus Strava übernehmen: Läufe ihrem Schuh zuordnen und den Kilometerstand abgleichen.
    /// Beim ersten Mal werden die Schuhe aller älteren Strava-Läufe nachgetragen. Die Angaben der
    /// Schuhe werden höchstens alle 6 Stunden neu abgefragt, außer es taucht ein neuer Schuh auf.
    private func syncShoes(activities: [StravaImport.Activity], context: ModelContext) async throws {
        let runs = try context.fetch(FetchDescriptor<Run>())
        let byID = Dictionary(runs.compactMap { run in run.stravaID.map { ($0, run) } }, uniquingKeysWith: { a, _ in a })
        var gearByActivity: [Int: String] = [:]
        for activity in activities { if let gear = activity.gearId { gearByActivity[activity.id] = gear } }

        let backfill = !defaults.bool(forKey: "strava.gearBackfill")
        if backfill, let oldest = runs.compactMap({ $0.stravaID != nil ? $0.startDate : nil }).min() {
            for page in 1...5 {
                let batch: [StravaImport.Activity] = try await get("/athlete/activities", query: [
                    URLQueryItem(name: "after", value: String(Int(oldest.timeIntervalSince1970) - 86_400)),
                    URLQueryItem(name: "per_page", value: "200"),
                    URLQueryItem(name: "page", value: String(page)),
                ]) ?? []
                for activity in batch where activity.isRun {
                    if let gear = activity.gearId { gearByActivity[activity.id] = gear }
                }
                if batch.count < 200 { break }
            }
        }

        var shoes = try context.fetch(FetchDescriptor<Shoe>())
        // Nur Schuhe („g…“), keine Räder
        let newGear = Set(gearByActivity.values.filter { $0.hasPrefix("g") })
        let known = Set(shoes.compactMap(\.stravaGearID))
        let lastRefresh = defaults.object(forKey: "strava.gearRefresh") as? Date ?? .distantPast
        let refreshAll = backfill || !newGear.isSubset(of: known) || Date.now.timeIntervalSince(lastRefresh) > 6 * 3600
        let gearIDs = refreshAll ? newGear.union(known) : newGear

        for gearID in gearIDs.sorted() {
            guard let gear: StravaImport.Gear = try await get("/gear/\(gearID)") else { continue }
            let shoe: Shoe
            if let existing = shoes.first(where: { $0.stravaGearID == gearID }) {
                shoe = existing
            } else {
                // In Gebrauch seit dem ersten bekannten Lauf mit diesem Schuh
                let firstRun = gearByActivity.filter { $0.value == gearID }.compactMap { byID[$0.key]?.startDate }.min()
                shoe = Shoe(brand: "", model: "", startDate: firstRun ?? .now)
                shoe.stravaGearID = gearID
                context.insert(shoe)
                shoes.append(shoe)
            }
            shoe.brand = gear.brandName ?? shoe.brand
            shoe.model = gear.modelName ?? shoe.model
            // Strava-Name nur als eigener Name übernehmen, wenn er mehr sagt als Marke und Modell
            let name = (gear.name ?? "").trimmingCharacters(in: .whitespaces)
            shoe.nickname = name.isEmpty || name == "\(shoe.brand) \(shoe.model)" ? "" : name
            if let retired = gear.retired { shoe.isRetired = retired }
            if gear.primary == true, !shoe.isRetired, !shoes.contains(where: { $0.isDefault }) { shoe.isDefault = true }

            for (activityID, id) in gearByActivity where id == gearID {
                byID[activityID]?.shoeID = shoe.id
            }
            // Strava-Kilometerstand abzüglich der Strava-Läufe, die in der App diesem Schuh zugeordnet sind;
            // Läufe nur in der App (nicht bei Strava) kommen beim Zählen noch dazu
            let linked = runs.filter { $0.shoeID == shoe.id && $0.stravaID != nil }.reduce(0) { $0 + $1.distance }
            shoe.initialDistance = max(0, gear.distance - linked)
        }
        if refreshAll { defaults.set(Date.now, forKey: "strava.gearRefresh") }
        if backfill { defaults.set(true, forKey: "strava.gearBackfill") }
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
                if knownIDs.contains(activity.id) { continue }
                if let duplicate = StravaImport.duplicate(of: activity, in: existing) {
                    // Schon aus Apple Health importiert: mit Strava verknüpfen (Fotos, Kudos, Kommentare)
                    if duplicate.isFromHealth, duplicate.stravaID == nil {
                        duplicate.stravaID = activity.id
                        if (activity.totalPhotoCount ?? 0) > 0 { try? await importPhotos(for: duplicate, activityID: activity.id) }
                        try? await updateSocial(for: duplicate, kudosCount: activity.kudosCount ?? 0,
                                                commentCount: activity.commentCount ?? 0)
                        try? context.save()
                    }
                    continue
                }
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
            // Schuhe und ihre Kilometer ebenfalls nur als Extra
            try? await syncShoes(activities: activities.filter(\.isRun), context: context)
            try? context.save()
            lastSyncDate = .now
            lastResult = imported == 0 ? "Keine neuen Läufe." : (imported == 1 ? "1 neuer Lauf importiert." : "\(imported) neue Läufe importiert.")
        } catch {
            lastSyncDate = .now
            lastError = error.localizedDescription
            if imported > 0 { lastResult = "\(imported) Läufe importiert." }
        }
    }
}
