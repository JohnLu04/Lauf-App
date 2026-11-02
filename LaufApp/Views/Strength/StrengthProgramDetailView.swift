import SwiftUI

/// Details eines Programms: Ziel, Übungen mit Vorgaben, Tipps und Studienlage.
struct StrengthProgramDetailView: View {
    let program: StrengthProgram
    @AppStorage("strengthProgramID") private var programID = ""
    @State private var showLog = false

    private var isActive: Bool { programID == program.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Warum es wirkt").font(.headline)
                    Text(program.why).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Übungen").font(.headline)
                    ForEach(program.items, id: \.exerciseID) { item in
                        if let exercise = item.exercise {
                            NavigationLink {
                                ExerciseDetailView(exercise: exercise, item: item)
                            } label: {
                                ProgramItemRow(exercise: exercise, item: item)
                            }
                            .buttonStyle(.plain)
                            if item != program.items.last { Divider() }
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tipps").font(.headline)
                    ForEach(program.tips, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .labelStyle(BulletLabelStyle(color: .green))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Studienlage").font(.headline)
                    ForEach(program.studies, id: \.self) { study in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(study.finding).font(.subheadline)
                            Text(study.citation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .padding()
            .padding(.bottom, 70)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if isActive {
                    Button {
                        showLog = true
                    } label: {
                        Label("Training eintragen", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        programID = program.id
                    } label: {
                        Label("Programm wählen", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .toolbar {
            if isActive {
                Menu {
                    Button("Programm beenden", systemImage: "xmark.circle", role: .destructive) { programID = "" }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showLog) { StrengthLogView(program: program) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: program.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name).font(.title3.bold())
                    Text(program.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(program.description).font(.subheadline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    StatView(label: "Niveau", value: program.level)
                    StatView(label: "Häufigkeit", value: program.frequency)
                }
                GridRow {
                    StatView(label: "Dauer", value: program.duration)
                    StatView(label: "Übungen", value: "\(program.items.count)")
                }
            }
            Label(program.equipment, systemImage: "dumbbell")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Übung mit Vorgabe in der Programmansicht.
struct ProgramItemRow: View {
    let exercise: StrengthExercise
    let item: ProgramItem

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise)
                .frame(width: 96, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.subheadline.weight(.semibold))
                Text(item.prescription).font(.subheadline.monospacedDigit())
                Text("\(item.intensity) · Pause \(item.rest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Aufzählungspunkt mit farbigem Symbol.
struct BulletLabelStyle: LabelStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(color).font(.caption)
            configuration.title
        }
    }
}
