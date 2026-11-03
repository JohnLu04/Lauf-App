import SwiftUI
import SceneKit

/// Animierte 3D-Übungsfigur (dreht sich nicht, Kamera steht fest wie in einer Illustration).
struct Exercise3DView: UIViewRepresentable {
    let exercise: StrengthExercise

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(white: 0.965, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        context.coordinator.attach(exercise, to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.exercise?.id != exercise.id { context.coordinator.attach(exercise, to: view) }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private(set) var exercise: StrengthExercise?
        private var scene: ExerciseScene?
        private var start: TimeInterval?

        func attach(_ exercise: StrengthExercise, to view: SCNView) {
            self.exercise = exercise
            start = nil
            scene = ExerciseScene(exercise: exercise)
            view.scene = scene?.scene
            view.pointOfView = scene?.cameraNode
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if start == nil { start = time }
            scene?.update(at: time - (start ?? time))
        }
    }
}

/// Standbilder der Figur für Listen (einmal berechnet und zwischengespeichert).
@MainActor
final class ExerciseSnapshots {
    static let shared = ExerciseSnapshots()
    private var images: [String: UIImage] = [:]
    private lazy var renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    func image(for exercise: StrengthExercise) -> UIImage? {
        if let image = images[exercise.id] { return image }
        guard let scene = ExerciseScene(exercise: exercise) else { return nil }
        // Haltung mit der größten Beugung zeigen: Ende der ersten Bewegung
        let animation = exercise.animation
        let time = (animation.holds.first ?? 0) + (animation.moves.first ?? 0) + (animation.holds.dropFirst().first ?? 0) / 2
        scene.update(at: animation.frames.count > 1 ? time : 0)
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 240), antialiasingMode: .multisampling4X)
        images[exercise.id] = image
        return image
    }
}

/// Figur als Standbild, das im Hintergrund vorbereitet wird.
struct ExerciseSnapshotView: View {
    let exercise: StrengthExercise
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.965)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: exercise.id) {
            // Kurz warten, damit schnelles Scrollen nicht jede Zeile rendert
            try? await Task.sleep(for: .milliseconds(30))
            image = ExerciseSnapshots.shared.image(for: exercise)
        }
    }
}
