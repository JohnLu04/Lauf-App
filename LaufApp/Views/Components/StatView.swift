import SwiftUI

/// Kleine Kennzahl: Beschriftung oben, Wert darunter.
struct StatView: View {
    let label: String
    let value: String
    var unit: String? = nil
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(large ? .title2.weight(.semibold) : .headline)
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Weiße Karte mit abgerundeten Ecken.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
