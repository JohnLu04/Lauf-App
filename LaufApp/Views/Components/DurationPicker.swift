import SwiftUI

/// Zeit-Eingabe (h:mm:ss), die sich bei Antippen als Drehrad aufklappt.
struct DurationPicker: View {
    let title: String
    @Binding var duration: TimeInterval
    @State private var expanded = false

    init(_ title: String, duration: Binding<TimeInterval>) {
        self.title = title
        self._duration = duration
    }

    private var total: Int { Int(duration.rounded()) }
    private var hours: Int { total / 3600 }
    private var minutes: Int { (total % 3600) / 60 }
    private var seconds: Int { total % 60 }

    private func set(h: Int? = nil, m: Int? = nil, s: Int? = nil) {
        duration = TimeInterval((h ?? hours) * 3600 + (m ?? minutes) * 60 + (s ?? seconds))
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text(Format.duration(duration))
                        .monospacedDigit()
                        .foregroundStyle(expanded ? Color.accentColor : .secondary)
                }
            }
            if expanded {
                HStack(spacing: 0) {
                    wheel("h", range: 0..<10, selection: Binding(get: { hours }, set: { set(h: $0) }))
                    wheel("min", range: 0..<60, selection: Binding(get: { minutes }, set: { set(m: $0) }))
                    wheel("s", range: 0..<60, selection: Binding(get: { seconds }, set: { set(s: $0) }))
                }
                .frame(height: 140)
            }
        }
    }

    private func wheel(_ unit: String, range: Range<Int>, selection: Binding<Int>) -> some View {
        Picker(unit, selection: selection) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
