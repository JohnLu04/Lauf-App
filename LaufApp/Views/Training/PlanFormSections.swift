import SwiftUI

/// Formularteil "Trainingstage": Läufe pro Woche, mögliche Tage und Tag des langen Laufs.
struct TrainingScheduleSection: View {
    @Binding var runsPerWeek: Int
    @Binding var trainingDays: Set<Int>
    @Binding var longRunDay: Int

    var body: some View {
        Section {
            Stepper("Läufe pro Woche: \(runsPerWeek)", value: $runsPerWeek, in: 2...6)
            VStack(alignment: .leading, spacing: 8) {
                Text("An welchen Tagen kannst du laufen?")
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
            .padding(.vertical, 4)
            Picker("Langer Lauf am", selection: $longRunDay) {
                ForEach(trainingDays.sorted(), id: \.self) { Text(Calendar.weekdayName($0)).tag($0) }
            }
        } header: {
            Text("Trainingstage")
        } footer: {
            if trainingDays.count < runsPerWeek {
                Label("Wähle mindestens \(runsPerWeek) Tage oder weniger Läufe pro Woche.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                Text("Wähle alle Tage, an denen du laufen könntest. Der Plan verteilt die Läufe so, dass zwischen harten Einheiten möglichst ein Tag Pause liegt.")
            }
        }
        .onChange(of: trainingDays) { _, days in
            if !days.contains(longRunDay), let last = days.max() { longRunDay = last }
        }
    }

    private func dayButton(_ day: Int) -> some View {
        let selected = trainingDays.contains(day)
        return Button {
            if selected {
                if trainingDays.count > 1 { trainingDays.remove(day) }
            } else {
                trainingDays.insert(day)
            }
        } label: {
            Text(Calendar.weekdayShortName(day))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.weekdayName(day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Formularteil "Umfang": aktueller und gewünschter Wochenumfang mit Warnungen.
struct WeeklyVolumeSection: View {
    @Binding var currentKm: Double
    @Binding var targetKm: Double
    var recommendedKm: Double
    var warnings: [String]
    var onTargetEdited: () -> Void = {}

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                LabeledContent("Aktueller Wochenumfang", value: "\(Int(currentKm)) km")
                Slider(value: $currentKm, in: 0...120, step: 5)
            }
            VStack(alignment: .leading) {
                LabeledContent("Gewünschter Wochenumfang", value: "\(Int(targetKm)) km")
                Slider(value: $targetKm, in: 10...150, step: 5) { editing in
                    if editing { onTargetEdited() }
                }
                Text("Empfehlung für dein Ziel: ab \(Int(recommendedKm)) km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Umfang")
        } footer: {
            if warnings.isEmpty {
                Text("So viele Kilometer möchtest du in den umfangreichsten Wochen laufen. Der Plan steigert sich behutsam dorthin.")
            } else {
                PlanWarningsView(warnings: warnings)
            }
        }
    }
}

struct PlanWarningsView: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}
