import Foundation

/// Person, die einem Strava-Lauf Kudos gegeben hat. Strava liefert meist nur den Vornamen
/// und den Anfangsbuchstaben des Nachnamens.
struct StravaKudoer: Codable, Hashable {
    var firstName: String
    var lastName: String

    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }

    var initials: String { StravaKudoer.initials(firstName, lastName) }

    static func initials(_ first: String, _ last: String) -> String {
        let letters = [first, last].compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// Kommentar zu einem Strava-Lauf.
struct StravaComment: Codable, Hashable, Identifiable {
    var id: Int
    var text: String
    var date: Date
    var firstName: String
    var lastName: String

    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }

    var initials: String { StravaKudoer.initials(firstName, lastName) }
}
