import Foundation
import SceneKit
import ImageIO
import simd

// 3D-Übungsfigur: Menschmodell „Superhero Male“ aus den Universal Base Characters von Quaternius
// (CC0, quaternius.com). SceneKit kann glTF nicht lesen, deshalb lädt `HumanModel` die Datei selbst:
// Netz, Skelett (65 Knochen) und Hautgewichte. Die Figur wird über dieselben Haltungen gesteuert wie
// die frühere 2D-Figur: Die 2D-Gelenkpositionen bestimmen die Richtung jedes Knochens.

/// Einmal geladene Modelldaten (Netze, Knochen, Muskelregionen je Eckpunkt).
final class HumanModel {
    struct Mesh {
        let name: String
        let positions: [Float]      // xyz
        let normals: [Float]        // xyz
        let uvs: [Float]            // uv
        let joints: [UInt16]        // 4 je Eckpunkt
        let weights: [Float]        // 4 je Eckpunkt
        let indices: [UInt16]
        let material: Int
        var vertexCount: Int { positions.count / 3 }
    }

    struct Joint {
        let name: String
        let parent: Int?            // Index in `joints`
        let restLocal: simd_float4x4
        let restWorld: simd_float4x4
    }

    let meshes: [Mesh]
    let joints: [Joint]
    let inverseBinds: [simd_float4x4]
    let textures: [String: CGImage]
    /// Anteil jeder Muskelgruppe je Eckpunkt des Körpernetzes (0…1)
    let muscleWeights: [MuscleGroup: [Float]]
    let bodyMeshIndex: Int

    static let shared: HumanModel? = {
        guard let url = Bundle.main.url(forResource: "Human", withExtension: "gltf") else { return nil }
        return try? HumanModel(gltf: url)
    }()

    init(gltf url: URL) throws {
        let folder = url.deletingLastPathComponent()
        let file = try GLTFFile(url: url)
        let nodes = file.nodes

        // Knotenhierarchie und Ruhelage
        var parentOf: [Int: Int] = [:]
        for (i, node) in nodes.enumerated() {
            for child in node["children"] as? [Int] ?? [] { parentOf[child] = i }
        }
        var worldCache: [Int: simd_float4x4] = [:]
        func worldMatrix(_ i: Int) -> simd_float4x4 {
            if let m = worldCache[i] { return m }
            var m = GLTFFile.localMatrix(nodes[i])
            if let p = parentOf[i] { m = worldMatrix(p) * m }
            worldCache[i] = m
            return m
        }

        let skin = (file.json["skins"] as? [[String: Any]] ?? [[:]])[0]
        let jointNodes = skin["joints"] as? [Int] ?? []
        joints = jointNodes.map { nodeIndex in
            Joint(name: nodes[nodeIndex]["name"] as? String ?? "",
                  parent: parentOf[nodeIndex].flatMap { jointNodes.firstIndex(of: $0) },
                  restLocal: GLTFFile.localMatrix(nodes[nodeIndex]),
                  restWorld: worldMatrix(nodeIndex))
        }
        let ibm = file.components(skin["inverseBindMatrices"] as? Int ?? 0)
        inverseBinds = (0..<ibm.count).map { i in
            let v = (0..<16).map { Float(ibm.values[i * 16 + $0]) }
            return simd_float4x4(columns: (SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
                                           SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15])))
        }

        // Netze: Körper, Augen, Augenbrauen und (aus eigener Datei, gleiches Skelett) kurze Haare
        var loaded = file.meshes()
        bodyMeshIndex = loaded.firstIndex { $0.vertexCount > 2000 } ?? 0
        if let hair = try? GLTFFile(url: folder.appending(path: "HumanHair.gltf")) {
            loaded += hair.meshes()
        }
        meshes = loaded

        // Texturen
        var images: [String: CGImage] = [:]
        for name in ["HumanSkin.jpg", "HumanNormal.png", "HumanEye.png"] {
            if let source = CGImageSourceCreateWithURL(folder.appending(path: name) as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                images[name] = image
            }
        }
        textures = images

        muscleWeights = MuscleRegions.weights(for: loaded[bodyMeshIndex], joints: joints)
    }

    func jointIndex(_ name: String) -> Int? { joints.firstIndex { $0.name == name } }
}

/// Minimaler glTF-Leser (JSON + Binärpuffer) für die Daten, die die Figur braucht.
private struct GLTFFile {
    let json: [String: Any]
    let buffers: [Data]
    var nodes: [[String: Any]] { json["nodes"] as? [[String: Any]] ?? [] }

    init(url: URL) throws {
        let folder = url.deletingLastPathComponent()
        json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        buffers = (json["buffers"] as? [[String: Any]] ?? []).map { buffer in
            (try? Data(contentsOf: folder.appending(path: buffer["uri"] as? String ?? ""))) ?? Data()
        }
    }

    /// Werte eines Accessors (normalisierte Ganzzahlen werden auf 0…1 umgerechnet)
    func components(_ index: Int) -> (values: [Double], count: Int) {
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        let accessor = accessors[index]
        let view = views[accessor["bufferView"] as? Int ?? 0]
        let data = buffers[view["buffer"] as? Int ?? 0]
        let count = accessor["count"] as? Int ?? 0
        let perElement = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16][accessor["type"] as? String ?? ""] ?? 1
        let type = accessor["componentType"] as? Int ?? 5126
        let size = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4][type] ?? 4
        let normalized = accessor["normalized"] as? Bool ?? false
        let start = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        let stride = view["byteStride"] as? Int ?? size * perElement
        var values = [Double](repeating: 0, count: count * perElement)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                for c in 0..<perElement {
                    let offset = start + i * stride + c * size
                    let v: Double
                    switch type {
                    case 5126: v = Double(raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
                    case 5121: v = Double(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self)) / (normalized ? 255 : 1)
                    case 5123: v = Double(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) / (normalized ? 65535 : 1)
                    case 5125: v = Double(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                    default: v = 0
                    }
                    values[i * perElement + c] = v
                }
            }
        }
        return (values, count)
    }

    func meshes() -> [HumanModel.Mesh] {
        var result: [HumanModel.Mesh] = []
        for node in nodes where node["mesh"] != nil {
            let mesh = (json["meshes"] as? [[String: Any]] ?? [])[node["mesh"] as? Int ?? 0]
            guard let primitive = (mesh["primitives"] as? [[String: Any]])?.first,
                  let attributes = primitive["attributes"] as? [String: Int] else { continue }
            func floats(_ key: String) -> [Float] { attributes[key].map { components($0).values.map(Float.init) } ?? [] }
            let joints = attributes["JOINTS_0"].map { components($0).values.map { UInt16($0) } } ?? []
            var weights = floats("WEIGHTS_0")
            for v in stride(from: 0, to: weights.count, by: 4) {
                let sum = weights[v] + weights[v + 1] + weights[v + 2] + weights[v + 3]
                if sum > 0 { for c in 0..<4 { weights[v + c] /= sum } }
            }
            let indices = (primitive["indices"] as? Int).map { components($0).values.map { UInt16($0) } } ?? []
            // Materialien der Datei: Haare/Brauen, Augen, Haut (Haare haben nur ein Material)
            let materialName = ((json["materials"] as? [[String: Any]] ?? [])[primitive["material"] as? Int ?? 0]["name"] as? String) ?? ""
            let material = materialName.contains("Eye") ? 1 : (materialName.contains("Hair") ? 0 : 2)
            result.append(HumanModel.Mesh(name: node["name"] as? String ?? "", positions: floats("POSITION"),
                                          normals: floats("NORMAL"), uvs: floats("TEXCOORD_0"), joints: joints,
                                          weights: weights, indices: indices, material: material))
        }
        return result
    }

    static func localMatrix(_ node: [String: Any]) -> simd_float4x4 {
        let t = (node["translation"] as? [Double] ?? [0, 0, 0]).map(Float.init)
        let r = (node["rotation"] as? [Double] ?? [0, 0, 0, 1]).map(Float.init)
        let s = (node["scale"] as? [Double] ?? [1, 1, 1]).map(Float.init)
        var m = simd_float4x4(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])) * simd_float4x4(diagonal: SIMD4(s[0], s[1], s[2], 1))
        m.columns.3 = SIMD4(t[0], t[1], t[2], 1)
        return m
    }
}

// MARK: - Muskelregionen

/// Ordnet jedem Eckpunkt (in der T-Pose: x = links, y = oben, z = vorne, Meter) Muskelgruppen zu.
/// Die Grenzen sind weich, damit die Färbung wie gemalt wirkt.
enum MuscleRegions {
    static func weights(for mesh: HumanModel.Mesh, joints: [HumanModel.Joint]) -> [MuscleGroup: [Float]] {
        func joint(_ name: String) -> SIMD3<Float> {
            let m = joints.first { $0.name == name }?.restWorld ?? matrix_identity_float4x4
            return SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        }
        let hip = joint("thigh_l"), knee = joint("calf_l"), ankle = joint("foot_l")
        let shoulder = joint("upperarm_l"), elbow = joint("lowerarm_l")

        /// Weicher Übergang: 0 unterhalb von a, 1 oberhalb von b
        func ramp(_ x: Float, _ a: Float, _ b: Float) -> Float {
            let t = max(0, min(1, (x - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        func band(_ x: Float, _ lo: Float, _ hi: Float, soft: Float = 0.03) -> Float {
            ramp(x, lo - soft, lo + soft) * (1 - ramp(x, hi - soft, hi + soft))
        }

        var result: [MuscleGroup: [Float]] = [:]
        for group in MuscleGroup.allCases { result[group] = [Float](repeating: 0, count: mesh.vertexCount) }

        for v in 0..<mesh.vertexCount {
            let p = SIMD3(mesh.positions[v * 3], mesh.positions[v * 3 + 1], mesh.positions[v * 3 + 2])
            let x = abs(p.x), y = p.y, z = p.z
            func set(_ g: MuscleGroup, _ w: Float) { if w > 0.001 { result[g]![v] = max(result[g]![v], min(1, w)) } }

            // Beine (Winkel um die Oberschenkelachse: 0° = vorne, 90° = außen, −90° = innen)
            if x < 0.3, y < hip.y + 0.04 {
                let center = SIMD2(hip.x, hip.z - 0.005)
                let angle = atan2(x - center.x, z - center.y) * 180 / .pi
                let thighZone = band(y, knee.y + 0.05, hip.y - 0.06)
                set(.quads, thighZone * (1 - ramp(abs(angle - 10), 70, 100)))
                set(.hamstrings, band(y, knee.y + 0.02, hip.y - 0.12) * ramp(abs(angle), 115, 140))
                set(.adductors, band(y, knee.y + 0.12, hip.y - 0.04) * band(angle, -125, -40, soft: 15))
                set(.calves, band(y, ankle.y + 0.08, knee.y - 0.02) * ramp(abs(angle), 95, 125))
                set(.hipFlexors, band(y, hip.y - 0.12, hip.y + 0.02) * (1 - ramp(abs(angle + 15), 35, 55)) * ramp(z, 0.0, 0.04))
            }
            // Gesäß und Hüfte
            if x < 0.25, y > hip.y - 0.16, y < hip.y + 0.14 {
                set(.glutes, band(y, hip.y - 0.13, hip.y + 0.1) * ramp(-z, 0.04, 0.09) * ramp(x, 0.0, 0.03))
                set(.hipAbductors, band(y, hip.y - 0.02, hip.y + 0.12) * ramp(x, 0.12, 0.15) * band(z, -0.1, 0.04, soft: 0.03))
            }
            // Rumpf
            if x < 0.21, y > hip.y + 0.0, y < shoulder.y + 0.06 {
                let front = ramp(z, 0.03, 0.07), back = ramp(-z, 0.05, 0.09)
                set(.core, band(y, hip.y + 0.03, hip.y + 0.36) * front * (1 - ramp(x, 0.07, 0.1)))
                set(.obliques, band(y, hip.y + 0.04, hip.y + 0.3) * (1 - ramp(x, 0.17, 0.2)) * ramp(x, 0.08, 0.11) * ramp(z, -0.05, 0.0))
                set(.lowerBack, band(y, hip.y + 0.06, hip.y + 0.26) * back * (1 - ramp(x, 0.08, 0.11)))
                set(.chest, band(y, shoulder.y - 0.2, shoulder.y - 0.03) * front * (1 - ramp(x, 0.17, 0.2)))
                set(.upperBack, band(y, hip.y + 0.22, shoulder.y + 0.04) * back)
            }
            // Arme (T-Pose: Arm entlang x)
            if x > shoulder.x - 0.06, x < elbow.x + 0.02, y > shoulder.y - 0.14 {
                let dz = z - shoulder.z, dy = y - shoulder.y
                set(.shoulders, (1 - ramp(x, shoulder.x + 0.06, shoulder.x + 0.11)) * ramp(dy + dz * 0.3, -0.06, -0.02))
                set(.triceps, band(x, shoulder.x + 0.06, elbow.x - 0.02) * ramp(-dz, 0.0, 0.025) * ramp(-dy, -0.03, 0.01))
            }
        }
        return result
    }
}

// MARK: - Figur in der Szene

/// Wie die Hände ein Gerät halten. Ohne Angabe liegen die Arme in der Zeichenebene unter den Schultern.
enum HandHold {
    /// Arme wie in der Haltung, die Hände aber um diese Strecke (m) seitlich nach außen versetzt –
    /// z. B. damit Kurzhanteln neben den Beinen hängen statt in den Oberschenkeln
    case spread(Float)
    /// Fäuste an einem festen Punkt des Rumpfs (Ruhelage in Metern: x = links, y = oben, z = vorn),
    /// `width` (m) auseinander; die Ellbogen zeigen in Richtung `elbows` (Ruhelage)
    case trunk(SIMD3<Float>, width: Float, elbows: SIMD3<Float>)
}

/// Eine Figur mit eigenen Knoten, die Haltungen und Muskelfarben annehmen kann.
final class HumanFigure {
    let model: HumanModel
    let root = SCNNode()
    private(set) var boneNodes: [SCNNode] = []
    private var bodyNode: SCNNode?
    private var muscleKey = ""
    /// Finger zur Faust schließen (wenn ein Gewicht gehalten wird)
    var grip = false
    /// Haltung der Hände an einem Gerät
    var hold: HandHold?
    /// Mitte der geschlossenen Faust (wo ein Griff liegt) relativ zum Handgelenk, in den Achsen der Ruhelage
    /// (Arm waagrecht zur Seite, Handfläche unten)
    static func fistOffset(left: Bool) -> SIMD3<Float> { SIMD3(left ? 0.09 : -0.09, -0.03, 0.005) }

    /// Umrechnung der 2D-Einheiten in Meter (Beinlänge des Modells / Beinlänge der 2D-Figur)
    static let unit: Float = 0.885 / Float(Body.thigh + Body.shin)

    init(model: HumanModel) {
        self.model = model
        boneNodes = model.joints.map { joint in
            let node = SCNNode()
            node.name = joint.name
            node.simdTransform = joint.restLocal
            return node
        }
        for (i, joint) in model.joints.enumerated() {
            if let parent = joint.parent { boneNodes[parent].addChildNode(boneNodes[i]) } else { root.addChildNode(boneNodes[i]) }
        }
        for (index, mesh) in model.meshes.enumerated() {
            let node = SCNNode(geometry: makeGeometry(mesh, colors: nil))
            node.name = mesh.name
            node.skinner = makeSkinner(for: node.geometry!, mesh: mesh)
            node.castsShadow = true
            root.addChildNode(node)
            if index == model.bodyMeshIndex { bodyNode = node }
        }
    }

    // MARK: Geometrie

    private func makeGeometry(_ mesh: HumanModel.Mesh, colors: [Float]?) -> SCNGeometry {
        func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
            let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: semantic, vectorCount: values.count / components,
                                     usesFloatComponents: true, componentsPerVector: components,
                                     bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * components)
        }
        var sources = [source(mesh.positions, .vertex, 3), source(mesh.normals, .normal, 3), source(mesh.uvs, .texcoord, 2)]
        if let colors { sources.append(source(colors, .color, 3)) }
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material(for: mesh)]
        return geometry
    }

    private func material(for mesh: HumanModel.Mesh) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.isDoubleSided = false
        m.metalness.contents = 0.0
        switch mesh.material {
        case 2:   // Haut
            m.diffuse.contents = model.textures["HumanSkin.jpg"]
            m.normal.contents = model.textures["HumanNormal.png"]
            m.normal.intensity = 1.0
            m.roughness.contents = 0.62
        case 1:   // Augen
            m.diffuse.contents = model.textures["HumanEye.png"]
            m.roughness.contents = 0.25
        default:  // Haare und Augenbrauen: einheitlich dunkelgrau (Brauen etwas heller)
            let gray: CGFloat = mesh.name.contains("Eyebrow") ? 0.36 : 0.2
            m.diffuse.contents = CGColor(red: gray, green: gray, blue: gray + 0.01, alpha: 1)
            m.roughness.contents = 0.85
        }
        return m
    }

    private func makeSkinner(for geometry: SCNGeometry, mesh: HumanModel.Mesh) -> SCNSkinner {
        let weightData = mesh.weights.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = mesh.joints.withUnsafeBufferPointer { Data(buffer: $0) }
        let weights = SCNGeometrySource(data: weightData, semantic: .boneWeights, vectorCount: mesh.vertexCount,
                                        usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                        dataOffset: 0, dataStride: 16)
        let indices = SCNGeometrySource(data: indexData, semantic: .boneIndices, vectorCount: mesh.vertexCount,
                                        usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2,
                                        dataOffset: 0, dataStride: 8)
        let binds = model.inverseBinds.map { NSValue(scnMatrix4: SCNMatrix4($0)) }
        let skinner = SCNSkinner(baseGeometry: geometry, bones: boneNodes, boneInverseBindTransforms: binds,
                                 boneWeights: weights, boneIndices: indices)
        skinner.skeleton = boneNodes.first
        return skinner
    }

    /// Färbt die beanspruchten Muskeln rot (Hauptmuskeln kräftig, unterstützende blass).
    func highlight(primary: Set<MuscleGroup>, secondary: Set<MuscleGroup>) {
        let key = primary.map(\.rawValue).sorted().joined() + "|" + secondary.map(\.rawValue).sorted().joined()
        guard key != muscleKey, let bodyNode else { return }
        muscleKey = key
        let mesh = model.meshes[model.bodyMeshIndex]
        var colors = [Float](repeating: 1, count: mesh.vertexCount * 3)
        let red = SIMD3<Float>(1.0, 0.07, 0.05), pale = SIMD3<Float>(1.0, 0.5, 0.46)
        for v in 0..<mesh.vertexCount {
            let main = primary.map { model.muscleWeights[$0]?[v] ?? 0 }.max() ?? 0
            let support = secondary.map { model.muscleWeights[$0]?[v] ?? 0 }.max() ?? 0
            var c = SIMD3<Float>(repeating: 1)
            c = c + (pale - c) * support
            c = c + (red - c) * main
            colors[v * 3] = c.x; colors[v * 3 + 1] = c.y; colors[v * 3 + 2] = c.z
        }
        let geometry = makeGeometry(mesh, colors: colors)
        bodyNode.skinner = nil
        bodyNode.geometry = geometry
        bodyNode.skinner = makeSkinner(for: geometry, mesh: mesh)
    }

    // MARK: Haltung

    /// Überträgt eine 2D-Haltung auf das Skelett. Die Zeichenebene ist die Seitenansicht des Körpers
    /// (bzw. bei `frontal` die Vorderansicht, z. B. für Übungen in Seitenlage).
    func apply(_ pose: ResolvedPose, frontal: Bool) {
        let s = Skeleton(pose)
        let e1 = SIMD3<Float>(1, 0, 0), e2 = SIMD3<Float>(0, 1, 0), n = SIMD3<Float>(0, 0, 1)
        func dir(_ v: CGVector) -> SIMD3<Float> { simd_normalize(Float(v.dx) * e1 - Float(v.dy) * e2) }
        func point(_ p: CGPoint) -> SIMD3<Float> { (Float(p.x) - 150) * Self.unit * e1 + (Float(Body.floor - p.y)) * Self.unit * e2 }
        /// Senkrecht zur Richtung in der Ebene, zur Seite wachsender Winkel (für Arme „vorne“)
        func forwardPerp(_ d: SIMD3<Float>) -> SIMD3<Float> { simd_cross(n, d) }

        var world: [Int: simd_float3x3] = [:]
        func frame(_ d: SIMD3<Float>, _ f: SIMD3<Float>) -> simd_float3x3 {
            let x = simd_normalize(d)
            var y = f - simd_dot(f, x) * x
            if simd_length(y) < 1e-4 { y = simd_cross(x, SIMD3(0, 0, 1)) }
            y = simd_normalize(y)
            return simd_float3x3(columns: (x, y, simd_cross(x, y)))
        }
        func rest(_ i: Int) -> simd_float3x3 { rotation(model.joints[i].restWorld) }
        func restPosition(_ name: String) -> SIMD3<Float> {
            guard let i = model.jointIndex(name) else { return .zero }
            let c = model.joints[i].restWorld.columns.3
            return SIMD3(c.x, c.y, c.z)
        }
        /// Knochen so drehen, dass seine Ruherichtung `d0` (mit Bezugsvektor `f0`) auf `d1`/`f1` zeigt
        func drive(_ name: String, d0: SIMD3<Float>, f0: SIMD3<Float>, d1: SIMD3<Float>, f1: SIMD3<Float>) {
            guard let i = model.jointIndex(name) else { return }
            let r = frame(d1, f1) * frame(d0, f0).transpose
            world[i] = r * rest(i)
        }
        func restDir(_ from: String, _ to: String) -> SIMD3<Float> { simd_normalize(restPosition(to) - restPosition(from)) }

        // Rumpf
        let torsoDir = dir(s.torsoDir)
        let torsoFront = frontal ? n : dir(CGVector(dx: -s.torsoDir.dy, dy: s.torsoDir.dx))
        let up = SIMD3<Float>(0, 1, 0), front = SIMD3<Float>(0, 0, 1)
        drive("pelvis", d0: up, f0: front, d1: torsoDir, f1: torsoFront)
        let headDir = dir(s.headDir)
        let headFront = frontal ? n : dir(CGVector(dx: -s.headDir.dy, dy: s.headDir.dx))
        drive("neck_01", d0: up, f0: front, d1: headDir, f1: headFront)

        // In der Vorderansicht liegen Hüft- und Schultergelenke übereinander statt hintereinander:
        // Glieder mit Zielpunkt werden deshalb vom tatsächlichen Gelenk aus neu gelöst.
        let trunk = frame(torsoDir, torsoFront) * frame(up, front).transpose
        let hipMid = (restPosition("thigh_l") + restPosition("thigh_r")) / 2
        func plane(_ p: SIMD3<Float>) -> CGPoint {
            CGPoint(x: Double(p.x / Self.unit) + 150, y: Body.floor - Double(p.y / Self.unit))
        }
        func limbJoints(_ limb: Limb, root: String, original: (CGPoint, CGPoint, CGPoint), l1: Double, l2: Double)
            -> (CGPoint, CGPoint, CGPoint) {
            guard frontal, case let .reach(_, bend) = limb else { return original }
            let start = plane(point(s.hip) + trunk * (restPosition(root) - hipMid))
            let (mid, end) = Skeleton.solve(.reach(original.2, bend: bend), root: start, l1: l1, l2: l2, offset: 0)
            return (start, mid, end)
        }

        /// Punkt, der fest am Rumpf sitzt (Ruhelage), in der aktuellen Haltung
        func onTrunk(_ rest: SIMD3<Float>) -> SIMD3<Float> { point(s.hip) + trunk * (rest - hipMid) }
        /// Arm räumlich lösen: Schulter, Ziel des Handgelenks und Richtung, in die der Ellbogen zeigen soll
        func driveArm(_ side: String, shoulder: SIMD3<Float>, wrist target: SIMD3<Float>, pole: SIMD3<Float>) {
            let l1 = simd_length(restPosition("lowerarm_\(side)") - restPosition("upperarm_\(side)"))
            let l2 = simd_length(restPosition("hand_\(side)") - restPosition("lowerarm_\(side)"))
            let toTarget = target - shoulder
            let d = min(max(simd_length(toTarget), abs(l1 - l2) + 0.001), l1 + l2 - 0.001)
            let axis = simd_normalize(toTarget)
            var bendDir = (pole - shoulder) - simd_dot(pole - shoulder, axis) * axis
            if simd_length(bendDir) < 1e-4 { bendDir = simd_cross(axis, n) }
            bendDir = simd_normalize(bendDir)
            let cosA = max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
            let elbow = shoulder + axis * (l1 * cosA) + bendDir * (l1 * (1 - cosA * cosA).squareRoot())
            let upper = simd_normalize(elbow - shoulder)
            let lower = simd_normalize(shoulder + axis * d - elbow)
            // Beugeachse des Ellbogens: aus der Beugung, bei gestrecktem Arm aus der Richtung des Ellbogens
            let hinge = simd_normalize(simd_cross(upper, lower) + 0.05 * simd_cross(bendDir, upper))
            drive("upperarm_\(side)", d0: restDir("upperarm_\(side)", "lowerarm_\(side)"), f0: front,
                  d1: upper, f1: simd_cross(hinge, upper))
            drive("lowerarm_\(side)", d0: restDir("lowerarm_\(side)", "hand_\(side)"), f0: front,
                  d1: lower, f1: simd_cross(hinge, lower))
        }

        // Arme und Beine: Index 0 = vorderes (der Kamera zugewandtes) Glied
        for i in 0..<2 {
            let side = frontal ? (i == 0 ? "l" : "r") : (i == 0 ? "r" : "l")
            let arm = limbJoints(pose.limbs[2 + i], root: "upperarm_\(side)", original: (s.shoulderJoint, s.elbow[i], s.wrist[i]),
                                 l1: Body.upperArm, l2: Body.forearm)
            let leg = limbJoints(pose.limbs[i], root: "thigh_\(side)", original: (s.hip, s.knee[i], s.ankle[i]),
                                 l1: Body.thigh, l2: Body.shin)
            let shoulder3D = onTrunk(restPosition("upperarm_\(side)"))
            /// Richtung von der Körpermitte zu dieser Seite
            let outward = simd_normalize(trunk * SIMD3(restPosition("upperarm_\(side)").x, 0, 0))
            if case let .forearmSupport(angle) = pose.limbs[2 + i] {
                // Oberarm in der Ebene, Unterarm nach vorn auf dem Boden
                let upperDir = dir(limbDir(angle + (pose.armsFollowTorso ? pose.torso : 0)))
                let l1 = simd_length(restPosition("lowerarm_\(side)") - restPosition("upperarm_\(side)"))
                let l2 = simd_length(restPosition("hand_\(side)") - restPosition("lowerarm_\(side)"))
                let elbow = shoulder3D + upperDir * l1
                driveArm(side, shoulder: shoulder3D, wrist: elbow + torsoFront * l2, pole: elbow + upperDir * 0.1)
            } else if !frontal, let hold {
                switch hold {
                case let .spread(offset):
                    // Form des Arms wie in der Haltung, von der echten Schulter aus und seitlich versetzt
                    let base = shoulder3D - point(s.shoulderJoint)
                    driveArm(side, shoulder: shoulder3D, wrist: point(s.wrist[i]) + base + outward * offset,
                             pole: point(s.elbow[i]) + base + outward * (offset * 0.5))
                case let .trunk(grip, width, elbows):
                    let fist = onTrunk(grip + simd_normalize(restPosition("upperarm_\(side)") * SIMD3(1, 0, 0)) * (width / 2))
                    let pole = shoulder3D + trunk * simd_normalize(elbows) * 0.3 + outward * 0.08
                    // Handgelenk so setzen, dass die Faust am Griff liegt (die Hand folgt dem Unterarm)
                    let offset = Self.fistOffset(left: side == "l")
                    var target = fist - simd_normalize(fist - shoulder3D) * simd_length(offset)
                    for _ in 0..<4 {
                        driveArm(side, shoulder: shoulder3D, wrist: target, pole: pole)
                        guard let index = model.jointIndex("lowerarm_\(side)"), let w = world[index] else { break }
                        target = fist - w * rest(index).transpose * offset
                    }
                }
            } else {
                let upper = dir(arm.1 - arm.0), lower = dir(arm.2 - arm.1)
                drive("upperarm_\(side)", d0: restDir("upperarm_\(side)", "lowerarm_\(side)"), f0: front,
                      d1: upper, f1: frontal ? torsoFront : forwardPerp(upper))
                drive("lowerarm_\(side)", d0: restDir("lowerarm_\(side)", "hand_\(side)"), f0: front,
                      d1: lower, f1: frontal ? torsoFront : forwardPerp(lower))
            }

            let thigh = dir(leg.1 - leg.0), shin = dir(leg.2 - leg.1)
            let back = -front
            drive("thigh_\(side)", d0: restDir("thigh_\(side)", "calf_\(side)"), f0: back,
                  d1: thigh, f1: frontal ? -torsoFront : -forwardPerp(thigh))
            drive("calf_\(side)", d0: restDir("calf_\(side)", "foot_\(side)"), f0: back,
                  d1: shin, f1: frontal ? -torsoFront : -forwardPerp(shin))

            // Fuß: 2D-Richtung ist die Sohle (Ferse → Zehen), der Fußknochen zeigt schräg nach unten
            let footBone = restDir("foot_\(side)", "ball_\(side)")
            let beta = asin(max(-1, min(1, -footBone.y)))
            let soleDir: SIMD3<Float>, soleDown: SIMD3<Float>
            if frontal {
                soleDir = torsoFront
                soleDown = shin
            } else {
                soleDir = dir(s.footDir[i])
                soleDown = -forwardPerp(soleDir)
            }
            let d1 = cos(beta) * soleDir + sin(beta) * soleDown
            let f1 = cos(beta) * -soleDown + sin(beta) * soleDir
            drive("foot_\(side)", d0: footBone, f0: simd_normalize(up - simd_dot(up, footBone) * footBone), d1: d1, f1: f1)
        }

        // Weltdrehungen in lokale Drehungen umrechnen (Eltern zuerst, die Liste ist so sortiert)
        var current: [simd_float3x3] = []
        for (i, joint) in model.joints.enumerated() {
            let parentWorld = joint.parent.map { current[$0] } ?? matrix_identity_float3x3
            var restLocal = rotation(joint.restLocal)
            if let curl = fingerCurl(joint) { restLocal = restLocal * curl }
            let w = world[i] ?? parentWorld * restLocal
            current.append(w)
            boneNodes[i].simdOrientation = simd_quatf(parentWorld.transpose * w)
        }

        // Becken so verschieben, dass die Hüftgelenke an der 2D-Hüfte liegen
        if let pelvis = model.jointIndex("pelvis") {
            let offset = hipMid - restPosition("pelvis")
            let target = point(s.hip) - current[pelvis] * offset
            let parentWorld = model.joints[pelvis].parent.map { model.joints[$0].restWorld } ?? matrix_identity_float4x4
            let local = parentWorld.inverse * SIMD4(target, 1)
            boneNodes[pelvis].simdPosition = SIMD3(local.x, local.y, local.z)
        }
    }

    func bone(_ name: String) -> SCNNode? { model.jointIndex(name).map { boneNodes[$0] } }

    /// Beugung eines Fingerglieds (lokal), wenn die Hand greift. In der T-Pose zeigen die Handflächen
    /// nach unten; Beugen dreht die Finger um die Achse nach vorn.
    private func fingerCurl(_ joint: HumanModel.Joint) -> simd_float3x3? {
        guard grip else { return nil }
        let name = joint.name
        guard ["index", "middle", "ring", "pinky", "thumb"].contains(where: name.hasPrefix), !name.contains("leaf") else { return nil }
        let left = name.hasSuffix("_l")
        let isThumb = name.hasPrefix("thumb")
        let angle: Float = (isThumb ? 35 : (name.contains("_01_") ? 75 : 85)) * .pi / 180
        let worldAxis = SIMD3<Float>(0, 0, left ? -1 : 1)
        let localAxis = rotation(joint.restWorld).transpose * worldAxis
        return simd_float3x3(simd_quatf(angle: angle, axis: simd_normalize(localAxis)))
    }
}

private func rotation(_ m: simd_float4x4) -> simd_float3x3 {
    simd_float3x3(columns: (SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                            SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                            SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
}
