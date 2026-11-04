import Foundation
import SwiftData

/// Laufschuh, dessen Kilometer gezählt werden. Die Läufe verweisen über `Run.shoeID` auf ihn.
@Model
final class Shoe {
    var id: UUID = UUID()
    var brand: String = ""
    var model: String = ""
    /// Eigener Name (optional), z. B. „Wettkampfschuh“
    var nickname: String = ""
    /// In Gebrauch seit
    var startDate: Date = Date()
    /// Meter, die nicht über zugeordnete Läufe erfasst sind (vor der App gelaufen; bei Strava-Schuhen
    /// der Teil des Strava-Kilometerstands, zu dem es in der App keinen Lauf gibt)
    var initialDistance: Double = 0
    /// Empfohlene Laufleistung in Metern, danach erscheint der Hinweis zum Austauschen
    var limit: Double = Shoe.defaultLimit
    /// Wird neuen Läufen automatisch zugeordnet
    var isDefault: Bool = false
    var isRetired: Bool = false
    /// Kennung bei Strava (z. B. „g12345“), wenn der Schuh von dort übernommen wurde
    var stravaGearID: String?
    /// Kilometerstand (Meter), bei dem der Hinweis zuletzt weggeklickt wurde (0 = nie)
    var hintDismissedAt: Double = 0
    var createdAt: Date = Date()

    /// Übliche Empfehlung: 500–800 km je nach Schuh, Gewicht und Untergrund
    static let defaultLimit = 700_000.0
    /// Nach dem Wegklicken erscheint der Hinweis erst nach weiteren 50 km wieder
    static let hintRepeatDistance = 50_000.0

    init(brand: String, model: String, nickname: String = "", startDate: Date = .now) {
        self.brand = brand
        self.model = model
        self.nickname = nickname
        self.startDate = startDate
    }

    var isFromStrava: Bool { stravaGearID != nil }

    /// Standardschuh für neue Läufe (nur aktive Schuhe)
    static func defaultShoe(in context: ModelContext) -> Shoe? {
        let shoes = (try? context.fetch(FetchDescriptor<Shoe>())) ?? []
        return shoes.first { $0.isDefault && !$0.isRetired }
    }

    /// Standardschuh für einen importierten Lauf – nur, wenn er an diesem Tag schon in Gebrauch war
    static func defaultShoeID(for date: Date, in context: ModelContext) -> UUID? {
        guard let shoe = defaultShoe(in: context),
              Calendar.current.startOfDay(for: shoe.startDate) <= date else { return nil }
        return shoe.id
    }

    /// Anzeigename: eigener Name, sonst Marke und Modell
    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let name = [brand, model].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Laufschuh" : name
    }

    /// Marke und Modell, wenn ein eigener Name angezeigt wird
    var detailName: String? {
        guard !nickname.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let name = [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// Gesamtstrecke in Metern
    func distance(in runs: [Run]) -> Double {
        initialDistance + runs.reduce(0) { $1.shoeID == id ? $0 + $1.distance : $0 }
    }

    func status(distance: Double) -> ShoeStatus {
        guard limit > 0 else { return .fine }
        if distance >= limit { return .replace }
        if distance >= limit * 0.9 { return .soon }
        return .fine
    }

    /// Soll der Hinweis zum Austauschen angezeigt werden?
    func needsReplaceHint(distance: Double) -> Bool {
        !isRetired && status(distance: distance) == .replace
            && (hintDismissedAt == 0 || distance >= hintDismissedAt + Self.hintRepeatDistance)
    }
}

enum ShoeStatus {
    case fine, soon, replace

    var label: String? {
        switch self {
        case .fine: nil
        case .soon: "Bald austauschen"
        case .replace: "Austauschen"
        }
    }
}
