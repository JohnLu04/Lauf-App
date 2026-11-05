import SwiftUI

// Haltungen der Übungsfigur. Sie werden in einer Seitenansicht (Blick nach rechts) in einem Raster von
// 300 × 200 Punkten beschrieben (Boden bei y = 186) und von `HumanFigure` auf das 3D-Skelett übertragen.

/// Muskelgruppen, die bei einer Übung hervorgehoben werden.
enum MuscleGroup: String, CaseIterable, Codable, Hashable {
    case quads, hamstrings, glutes, hipAbductors, adductors, hipFlexors, calves
    case core, obliques, lowerBack, chest, upperBack, shoulders, triceps

    var name: String {
        switch self {
        case .quads: "Oberschenkelvorderseite"
        case .hamstrings: "Oberschenkelrückseite"
        case .glutes: "Gesäß"
        case .hipAbductors: "Hüftabduktoren"
        case .adductors: "Adduktoren"
        case .hipFlexors: "Hüftbeuger"
        case .calves: "Waden"
        case .core: "Bauch"
        case .obliques: "Seitliche Bauchmuskeln"
        case .lowerBack: "Unterer Rücken"
        case .chest: "Brust"
        case .upperBack: "Oberer Rücken"
        case .shoulders: "Schultern"
        case .triceps: "Armstrecker"
        }
    }

    /// Anatomische Bezeichnung
    var detail: String {
        switch self {
        case .quads: "Quadrizeps"
        case .hamstrings: "Ischiocrurale Muskulatur"
        case .glutes: "Großer Gesäßmuskel"
        case .hipAbductors: "Mittlerer Gesäßmuskel"
        case .adductors: "Schenkelanzieher"
        case .hipFlexors: "Hüftlendenmuskel"
        case .calves: "Gastrocnemius und Soleus"
        case .core: "Gerader und querer Bauchmuskel"
        case .obliques: "Schräge Bauchmuskeln"
        case .lowerBack: "Rückenstrecker"
        case .chest: "Großer Brustmuskel"
        case .upperBack: "Latissimus und Trapezmuskel"
        case .shoulders: "Deltamuskel"
        case .triceps: "Trizeps"
        }
    }
}

/// Stellung eines Arms oder Beins: entweder feste Winkel oder ein Zielpunkt für Hand bzw.
/// Fußgelenk, zu dem Ellbogen bzw. Knie automatisch gebeugt werden.
enum Limb {
    /// Absolute Winkel in Grad: 0 = senkrecht nach unten, positiv = nach vorn (Blickrichtung)
    case angles(Double, Double)
    /// Zielpunkt im Raster; `bend` = Richtung (Grad, 0 = vorn, 90 = unten), in die das Gelenk zeigt
    case reach(CGPoint, bend: Double)
    /// Arm auf den Unterarm gestützt (Übungen in Seitenlage): Oberarm mit festem Winkel in der Zeichenebene,
    /// Unterarm liegt quer dazu nach vorn auf dem Boden
    case forearmSupport(Double)
}

/// Eine Körperhaltung (Schlüsselbild der Animation).
struct Pose {
    var hip: CGPoint
    /// Rumpfneigung: 0 = aufrecht, 90 = waagrecht mit Kopf nach vorn, −90 = Kopf nach hinten
    var torso: Double
    /// Kopfneigung relativ zum Rumpf (positiv = Kinn zur Brust)
    var head: Double = 0
    var nearLeg: Limb
    var farLeg: Limb
    var nearArm: Limb
    var farArm: Limb
    /// Fußrichtung (Ferse → Zehen), absolut: 90 = waagrecht nach vorn
    var nearFoot: Double = 90
    var farFoot: Double = 90
    /// Armwinkel relativ zum Rumpf (z. B. Hantelstange auf den Schultern)
    var armsFollowTorso = false
}

/// Geräte und Hilfsmittel, die mitgezeichnet werden.
enum Prop {
    case bench(x: Double, width: Double, height: Double)
    /// Bank quer zur Zeichenebene (Beine an den Enden vorn und hinten, darunter ist Platz)
    case crossBench(x: Double, width: Double, height: Double)
    case box(x: Double, width: Double, height: Double)
    case mat(x: Double, width: Double)
    case dumbbells
    /// Eine Kurzhantel, in der vorderen oder (bei `inFarHand`) der hinteren Hand
    case dumbbell(inFarHand: Bool)
    case kettlebell
    case barbellBack
    /// Polster, das die Fersen festhält (Nordic Curl)
    case anklePad
    /// Stange zum Festhalten für die hintere Hand (Gleichgewicht bei Übungen auf einem Bein)
    case handPost
}

/// Ablauf einer Übung: Schlüsselbilder mit Halte- und Bewegungsdauer (Sekunden).
struct ExerciseAnimation {
    var frames: [Pose]
    /// Haltezeit je Schlüsselbild
    var holds: [Double]
    /// Dauer der Bewegung vom Schlüsselbild i zum nächsten (zyklisch)
    var moves: [Double]
    var props: [Prop] = []
    /// true: Die Zeichenebene ist die Vorderansicht des Körpers (Übungen in Seitenlage)
    var frontal = false

    var duration: Double { holds.reduce(0, +) + moves.reduce(0, +) }

    /// Haltung zum Zeitpunkt `time` (Sekunden, läuft in Schleife)
    func pose(at time: Double) -> ResolvedPose {
        let resolved = frames.map(ResolvedPose.init)
        guard resolved.count > 1, duration > 0 else { return resolved[0] }
        var t = time.truncatingRemainder(dividingBy: duration)
        for i in resolved.indices {
            let hold = i < holds.count ? holds[i] : 0
            if t < hold { return resolved[i] }
            t -= hold
            let move = i < moves.count ? moves[i] : 0.8
            if t < move {
                let x = t / move
                let eased = x * x * (3 - 2 * x)
                return ResolvedPose.interpolate(resolved[i], resolved[(i + 1) % resolved.count], eased)
            }
            t -= move
        }
        return resolved[0]
    }
}

// MARK: - Skelett

enum Body {
    // Proportionen des 3D-Modells in Rasterpunkten (1 Punkt ≈ 1,05 cm)
    static let torso = 50.9, neck = 7.0, headRadius = 11.0
    static let upperArm = 23.8, forearm = 23.1
    static let thigh = 40.7, shin = 43.6
    static let floor = 186.0
    /// Höhe des Fußgelenks über der Fußsohle
    static let ankleHeight = 8.2
    /// Ferse hinter bzw. Zehenspitze vor dem Fußgelenk
    static let heel = 5.5, toe = 21.0
}

/// Haltung mit aufgelösten Gliedmaßen (Winkel); Zielpunkte bleiben erhalten, damit Füße und
/// Hände beim Überblenden an ihrem Platz bleiben.
struct ResolvedPose {
    var hip: CGPoint
    var torso: Double
    var head: Double
    var limbs: [Limb]          // nearLeg, farLeg, nearArm, farArm
    var nearFoot: Double
    var farFoot: Double
    var armsFollowTorso: Bool

    init(_ pose: Pose) {
        hip = pose.hip; torso = pose.torso; head = pose.head
        limbs = [pose.nearLeg, pose.farLeg, pose.nearArm, pose.farArm]
        nearFoot = pose.nearFoot; farFoot = pose.farFoot
        armsFollowTorso = pose.armsFollowTorso
    }

    static func interpolate(_ a: ResolvedPose, _ b: ResolvedPose, _ t: Double) -> ResolvedPose {
        var r = a
        r.hip = CGPoint(x: lerp(a.hip.x, b.hip.x, t), y: lerp(a.hip.y, b.hip.y, t))
        r.torso = lerp(a.torso, b.torso, t)
        r.head = lerp(a.head, b.head, t)
        r.nearFoot = lerp(a.nearFoot, b.nearFoot, t)
        r.farFoot = lerp(a.farFoot, b.farFoot, t)
        let sa = Skeleton(a), sb = Skeleton(b)
        for i in 0..<4 {
            switch (a.limbs[i], b.limbs[i]) {
            case let (.reach(pa, ba), .reach(pb, bb)):
                r.limbs[i] = .reach(CGPoint(x: lerp(pa.x, pb.x, t), y: lerp(pa.y, pb.y, t)), bend: lerp(ba, bb, t))
            case let (.forearmSupport(fa), .forearmSupport(fb)):
                r.limbs[i] = .forearmSupport(lerp(fa, fb, t))
            default:
                // Unterschiedliche Angaben: über die tatsächlichen Winkel überblenden
                let (a1, a2) = sa.limbAngles(i), (b1, b2) = sb.limbAngles(i)
                r.limbs[i] = .angles(lerpAngle(a1, b1, t), lerpAngle(a2, b2, t))
            }
        }
        if a.armsFollowTorso != b.armsFollowTorso { r.armsFollowTorso = false }
        return r
    }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

private func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
    var d = (b - a).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return a + d * t
}

private func rad(_ deg: Double) -> Double { deg * .pi / 180 }

/// Richtung einer Gliedmaße (0 = unten, positiv = vorn)
func limbDir(_ deg: Double) -> CGVector { CGVector(dx: sin(rad(deg)), dy: cos(rad(deg))) }

/// Gelenkpositionen im Raster.
struct Skeleton {
    var hip, shoulder, neckTop, headCenter: CGPoint
    var knee: [CGPoint], ankle: [CGPoint], heel: [CGPoint], toe: [CGPoint]
    var shoulderJoint: CGPoint
    var elbow: [CGPoint], wrist: [CGPoint]
    var torsoDir: CGVector
    var headDir: CGVector
    var footDir: [CGVector]

    init(_ p: ResolvedPose) {
        hip = p.hip
        torsoDir = CGVector(dx: sin(rad(p.torso)), dy: -cos(rad(p.torso)))
        shoulder = hip + torsoDir * Body.torso
        headDir = CGVector(dx: sin(rad(p.torso + p.head)), dy: -cos(rad(p.torso + p.head)))
        neckTop = shoulder + headDir * Body.neck
        headCenter = shoulder + headDir * (Body.neck + Body.headRadius - 1)
        shoulderJoint = shoulder - torsoDir * 5

        knee = []; ankle = []; elbow = []; wrist = []; heel = []; toe = []; footDir = []
        for (i, foot) in [p.nearFoot, p.farFoot].enumerated() {
            let (k, a) = Skeleton.solve(p.limbs[i], root: hip, l1: Body.thigh, l2: Body.shin, offset: 0)
            knee.append(k); ankle.append(a)
            let f = limbDir(foot)
            let sole = CGVector(dx: -f.dy, dy: f.dx)
            footDir.append(f)
            heel.append(a - f * Body.heel + sole * Body.ankleHeight)
            toe.append(a + f * Body.toe + sole * Body.ankleHeight)
        }
        for i in 2...3 {
            let offset = p.armsFollowTorso ? p.torso : 0
            let (e, w) = Skeleton.solve(p.limbs[i], root: shoulderJoint, l1: Body.upperArm, l2: Body.forearm, offset: offset)
            elbow.append(e); wrist.append(w)
        }
    }

    /// Mittel- und Endgelenk einer Gliedmaße
    static func solve(_ limb: Limb, root: CGPoint, l1: Double, l2: Double, offset: Double) -> (CGPoint, CGPoint) {
        switch limb {
        case let .angles(a, b):
            let mid = root + limbDir(a + offset) * l1
            return (mid, mid + limbDir(b + offset) * l2)
        case let .forearmSupport(a):
            // Der Unterarm zeigt aus der Zeichenebene heraus; in der Ebene liegt die Hand am Ellbogen
            let mid = root + limbDir(a + offset) * l1
            return (mid, mid)
        case let .reach(target, bend):
            let v = target - root
            let d = min(max(v.length, abs(l1 - l2) + 0.01), l1 + l2 - 0.01)
            let base = atan2(v.dy, v.dx)
            let cosA = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
            let a = acos(min(1, max(-1, cosA)))
            let hint = CGVector(dx: cos(rad(bend)), dy: sin(rad(bend)))
            let candidates = [base + a, base - a].map { root + CGVector(dx: cos($0), dy: sin($0)) * l1 }
            let mid = candidates.max { ($0 - root).dot(hint) < ($1 - root).dot(hint) }!
            let end = mid + (target - mid).normalized * l2
            return (mid, end)
        }
    }

    /// Absolute Winkel (0 = unten) von Ober- und Unterteil der Gliedmaße i
    func limbAngles(_ i: Int) -> (Double, Double) {
        let (root, mid, end) = i < 2 ? (hip, knee[i], ankle[i]) : (shoulderJoint, elbow[i - 2], wrist[i - 2])
        func angle(_ v: CGVector) -> Double { atan2(v.dx, v.dy) * 180 / .pi }
        return (angle(mid - root), angle(end - mid))
    }
}

// MARK: - Vektorrechnung

extension CGVector {
    static func * (v: CGVector, s: Double) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func - (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx - b.dx, dy: a.dy - b.dy) }
    static prefix func - (v: CGVector) -> CGVector { CGVector(dx: -v.dx, dy: -v.dy) }
    var length: Double { (dx * dx + dy * dy).squareRoot() }
    var normalized: CGVector { length > 0 ? self * (1 / length) : self }
    func dot(_ o: CGVector) -> Double { dx * o.dx + dy * o.dy }
}

extension CGPoint {
    static func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
    static func - (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x - v.dx, y: p.y - v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}
