import Foundation
import SceneKit
import simd

/// 3D-Szene einer Übung: Figur mit hervorgehobenen Muskeln, Geräte, Licht und Kamera.
final class ExerciseScene {
    let scene = SCNScene()
    let figure: HumanFigure
    let exercise: StrengthExercise
    let cameraNode = SCNNode()
    private var kettlebell: SCNNode?
    private let unit = HumanFigure.unit

    init?(exercise: StrengthExercise, model: HumanModel? = HumanModel.shared) {
        guard let model else { return nil }
        self.exercise = exercise
        figure = HumanFigure(model: model)
        figure.highlight(primary: Set(exercise.primary), secondary: Set(exercise.secondary))
        scene.rootNode.addChildNode(figure.root)
        scene.background.contents = CGColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1)

        addLights()
        addFloor()
        for prop in exercise.animation.props { addProp(prop) }
        // Hände, die ein Gewicht halten, zur Faust schließen
        let holds = exercise.animation.props.contains { prop in
            switch prop {
            case .dumbbells, .dumbbell, .kettlebell, .barbellBack: true
            default: false
            }
        }
        if holds { figure.grip = true }
        update(at: 0)
        frameCamera()
    }

    /// Haltung zum Zeitpunkt `time` (Sekunden, in Schleife)
    func update(at time: TimeInterval) {
        figure.apply(exercise.animation.pose(at: time), frontal: exercise.animation.frontal)
        if let kettlebell, let l = figure.bone("hand_l"), let r = figure.bone("hand_r") {
            // Kettlebell vor der Brust zwischen beiden Händen
            kettlebell.simdPosition = (l.simdWorldPosition + r.simdWorldPosition) / 2 + SIMD3(0.04, -0.1, 0)
        }
    }

    // MARK: Licht und Boden

    private func addLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowColor = CGColor(gray: 0, alpha: 0.22)
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.orthographicScale = 3
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3(1.5, 4, 3)
        keyNode.simdLook(at: SIMD3(0, 0.6, 0))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 380
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = SIMD3(-2.5, 1.5, -1)
        fillNode.simdLook(at: SIMD3(0, 0.8, 0))
        scene.rootNode.addChildNode(fillNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func addFloor() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let material = SCNMaterial()
        material.lightingModel = .shadowOnly
        floor.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))
    }

    // MARK: Geräte

    private func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, rough: CGFloat = 0.5, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = CGColor(red: r, green: g, blue: b, alpha: 1)
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    /// Punkt des 2D-Rasters in Metern (Breite und Tiefe = z)
    private func world(_ x: Double, _ y: Double, z: Float = 0) -> SIMD3<Float> {
        SIMD3((Float(x) - 150) * unit, Float(Body.floor - y) * unit, z)
    }

    private func box(from x: Double, width: Double, bottom: Double, top: Double, depth: Float, _ m: SCNMaterial,
                     chamfer: CGFloat = 0.01) -> SCNNode {
        let w = CGFloat(Float(width) * unit), h = CGFloat(Float(top - bottom) * unit)
        let geometry = SCNBox(width: w, height: h, length: CGFloat(depth), chamferRadius: chamfer)
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.simdPosition = world(x + width / 2, Body.floor - (bottom + top) / 2)
        node.castsShadow = true
        return node
    }

    private func addProp(_ prop: Prop) {
        switch prop {
        case let .bench(x, width, height):
            let pad = box(from: x, width: width, bottom: height - 7, top: height, depth: 0.32, material(0.13, 0.13, 0.14, rough: 0.7), chamfer: 0.02)
            scene.rootNode.addChildNode(pad)
            let frame = material(0.92, 0.92, 0.93, rough: 0.35, metal: 0.3)
            for legX in [x + 8, x + width - 12] {
                scene.rootNode.addChildNode(box(from: legX, width: 4, bottom: 0, top: height - 7, depth: 0.05, frame))
                scene.rootNode.addChildNode(box(from: legX - 6, width: 16, bottom: 0, top: 2.5, depth: 0.36, frame))
            }
        case let .box(x, width, height):
            scene.rootNode.addChildNode(box(from: x, width: width, bottom: 0, top: height, depth: 0.55,
                                            material(0.80, 0.66, 0.47, rough: 0.8), chamfer: 0.015))
        case let .mat(x, width):
            scene.rootNode.addChildNode(box(from: x, width: width, bottom: 0, top: 1, depth: 0.62,
                                            material(0.36, 0.55, 0.74, rough: 0.9), chamfer: 0.004))
        case .dumbbells:
            attachDumbbell(to: "hand_l")
            attachDumbbell(to: "hand_r")
        case .dumbbell:
            attachDumbbell(to: exercise.animation.frontal ? "hand_l" : "hand_r")
        case .kettlebell:
            let bell = SCNNode()
            let body = SCNSphere(radius: 0.085)
            body.materials = [material(0.12, 0.12, 0.13, rough: 0.45, metal: 0.4)]
            bell.addChildNode(SCNNode(geometry: body))
            let handle = SCNTorus(ringRadius: 0.06, pipeRadius: 0.014)
            handle.materials = body.materials
            let handleNode = SCNNode(geometry: handle)
            handleNode.simdPosition = SIMD3(0, 0.08, 0)
            handleNode.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            bell.addChildNode(handleNode)
            bell.castsShadow = true
            scene.rootNode.addChildNode(bell)
            kettlebell = bell
        case .barbellBack:
            guard let spine = figure.bone("spine_03"), let index = figure.model.jointIndex("spine_03") else { return }
            let restWorld = figure.model.joints[index].restWorld
            let inverse = restWorld.inverse
            let bar = SCNNode()
            let metal = material(0.75, 0.75, 0.77, rough: 0.3, metal: 0.9)
            let rod = SCNCylinder(radius: 0.014, height: 1.9)
            rod.materials = [metal]
            let rodNode = SCNNode(geometry: rod)
            rodNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)   // Stange entlang der Körperbreite (x)
            bar.addChildNode(rodNode)
            for side: Float in [-1, 1] {
                let plate = SCNCylinder(radius: 0.21, height: 0.05)
                plate.materials = [material(0.1, 0.1, 0.11, rough: 0.6)]
                let plateNode = SCNNode(geometry: plate)
                plateNode.simdEulerAngles = SIMD3(0, 0, .pi / 2)
                plateNode.simdPosition = SIMD3(side * 0.66, 0, 0)
                bar.addChildNode(plateNode)
            }
            // Ruhelage: auf dem oberen Rücken hinter dem Hals
            let restPos = SIMD4<Float>(0, restWorld.columns.3.y + 0.16, restWorld.columns.3.z - 0.1, 1)
            let local = inverse * restPos
            bar.simdPosition = SIMD3(local.x, local.y, local.z)
            bar.simdOrientation = simd_quatf(inverse)
            bar.castsShadow = true
            spine.addChildNode(bar)
        case .anklePad:
            let s = Skeleton(ResolvedPose(exercise.animation.frames[0]))
            let a = s.ankle[0]
            let roll = SCNCylinder(radius: 0.06, height: 0.4)
            roll.materials = [material(0.12, 0.12, 0.13, rough: 0.8)]
            let node = SCNNode(geometry: roll)
            node.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            node.simdPosition = world(a.x - 1, a.y - 10)
            node.castsShadow = true
            scene.rootNode.addChildNode(node)
            let post = box(from: a.x - 2, width: 4, bottom: 0, top: Body.floor - a.y + 10, depth: 0.05, material(0.9, 0.9, 0.9, rough: 0.4, metal: 0.3))
            scene.rootNode.addChildNode(post)
        }
    }

    /// Kurzhantel in der Hand: Griff quer durch die Faust (in der T-Pose von vorn nach hinten)
    private func attachDumbbell(to handName: String) {
        guard let hand = figure.bone(handName), let index = figure.model.jointIndex(handName) else { return }
        let restWorld = figure.model.joints[index].restWorld
        let inverse = restWorld.inverse
        let sideSign: Float = restWorld.columns.3.x > 0 ? 1 : -1
        let gripWorld = SIMD4<Float>(restWorld.columns.3.x + sideSign * 0.085, restWorld.columns.3.y - 0.02, restWorld.columns.3.z + 0.01, 1)
        let local = inverse * gripWorld

        let dumbbell = SCNNode()
        let iron = material(0.1, 0.1, 0.11, rough: 0.5, metal: 0.5)
        let handle = SCNCylinder(radius: 0.016, height: 0.17)
        handle.materials = [material(0.6, 0.6, 0.62, rough: 0.35, metal: 0.9)]
        dumbbell.addChildNode(SCNNode(geometry: handle))
        for side: Float in [-1, 1] {
            let plate = SCNCylinder(radius: 0.055, height: 0.05)
            plate.materials = [iron]
            let node = SCNNode(geometry: plate)
            node.simdPosition = SIMD3(0, side * 0.1, 0)
            dumbbell.addChildNode(node)
        }
        dumbbell.simdPosition = SIMD3(local.x, local.y, local.z)
        // Zylinder liegen entlang y; Griffachse soll in der Ruhelage entlang z zeigen
        let worldOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: SIMD3(0, 0, 1))
        dumbbell.simdOrientation = simd_quatf(inverse) * worldOrientation
        dumbbell.castsShadow = true
        hand.addChildNode(dumbbell)
    }

    // MARK: Kamera

    /// Schräg von vorn oben (wie in Fitness-Apps), so nah, dass die ganze Bewegung ins Bild passt.
    private func frameCamera() {
        // Punkte der ganzen Bewegung (Gelenke mit Polster für die Körperform, Kopf bis zum Scheitel)
        var points: [(SIMD3<Float>, Float)] = []
        let steps = 16
        let head = figure.bone("Head"), neck = figure.bone("neck_01")
        for k in 0..<steps {
            update(at: exercise.animation.duration * Double(k) / Double(steps))
            for node in figure.boneNodes where !(node.name ?? "").contains("leaf") {
                points.append((node.simdWorldPosition, 0.07))
            }
            if let head, let neck {
                let top = head.simdWorldPosition + simd_normalize(head.simdWorldPosition - neck.simdWorldPosition) * 0.2
                points.append((top, 0.05))
            }
        }
        update(at: 0)
        // Geräte
        for node in scene.rootNode.childNodes where node.geometry != nil && !(node.geometry is SCNFloor) {
            let (lo, hi) = node.boundingBox
            for corner in 0..<8 {
                let local = SIMD3<Float>(Float(corner & 1 == 0 ? lo.x : hi.x), Float(corner & 2 == 0 ? lo.y : hi.y),
                                         Float(corner & 4 == 0 ? lo.z : hi.z))
                points.append((node.simdConvertPosition(local, to: nil), 0))
            }
        }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for (p, r) in points { lo = simd_min(lo, p - r); hi = simd_max(hi, p + r) }
        let center = (lo + hi) / 2

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.05
        camera.zFar = 30
        camera.wantsHDR = false
        cameraNode.camera = camera

        let frontal = exercise.animation.frontal
        // Hauptmuskeln auf der Rückseite (z. B. Oberschenkelrückseite) von schräg hinten zeigen
        let posterior: Set<MuscleGroup> = [.hamstrings, .glutes, .calves, .lowerBack, .upperBack, .triceps]
        let backCount = exercise.primary.filter(posterior.contains).count
        let fromBehind = !frontal && backCount * 2 > exercise.primary.count
        let yaw: Float = (frontal ? 15 : (fromBehind ? -35 : 35)) * .pi / 180
        let pitch: Float = 14 * .pi / 180
        let direction = simd_normalize(SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)))
        // Abstand so wählen, dass alle Punkte ins Bild (Seitenverhältnis 3:2) passen
        let forward = -direction
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let camUp = simd_cross(right, forward)
        let tanV = tan(Float(camera.fieldOfView) * .pi / 360), tanH = tanV * 1.5
        var distance: Float = 0.5
        for (p, r) in points {
            let v = p - center
            let depth = simd_dot(v, direction)
            distance = max(distance, depth + (abs(simd_dot(v, right)) + r) / tanH, depth + (abs(simd_dot(v, camUp)) + r) / tanV)
        }
        distance *= 1.04
        cameraNode.simdPosition = center + direction * distance
        cameraNode.simdLook(at: center)
        scene.rootNode.addChildNode(cameraNode)
    }
}
