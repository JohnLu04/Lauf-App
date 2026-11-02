import SwiftUI

// Animierte Übungsfigur: ein schattierter Körper in Seitenansicht (Blick nach rechts), bei dem
// die beanspruchten Muskeln rot hervorgehoben sind. Gezeichnet wird in einem festen Raster von
// 300 × 200 Punkten (Boden bei y = 186), das auf die verfügbare Größe skaliert wird.

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
    case box(x: Double, width: Double, height: Double)
    case mat(x: Double, width: Double)
    case dumbbells
    case dumbbell
    case kettlebell
    case barbellBack
    /// Polster, das die Fersen festhält (Nordic Curl)
    case anklePad
}

/// Ablauf einer Übung: Schlüsselbilder mit Halte- und Bewegungsdauer (Sekunden).
struct ExerciseAnimation {
    var frames: [Pose]
    /// Haltezeit je Schlüsselbild
    var holds: [Double]
    /// Dauer der Bewegung vom Schlüsselbild i zum nächsten (zyklisch)
    var moves: [Double]
    var props: [Prop] = []
    /// Verkleinerung für Übungen, die mehr Höhe brauchen (z. B. auf einer Box)
    var zoom: Double = 1

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
    static let torso = 52.0, neck = 7.0, headRadius = 11.0
    static let upperArm = 29.0, forearm = 26.0
    static let thigh = 43.0, shin = 41.0
    static let floor = 186.0
    /// Höhe des Fußgelenks über der Fußsohle
    static let ankleHeight = 6.0
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
private func limbDir(_ deg: Double) -> CGVector { CGVector(dx: sin(rad(deg)), dy: cos(rad(deg))) }

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
            heel.append(a - f * 4 + sole * Body.ankleHeight)
            toe.append(a + f * 15 + sole * Body.ankleHeight)
        }
        for i in 2...3 {
            let offset = p.armsFollowTorso ? p.torso : 0
            let (e, w) = Skeleton.solve(p.limbs[i], root: shoulderJoint, l1: Body.upperArm, l2: Body.forearm, offset: offset)
            elbow.append(e); wrist.append(w)
        }
    }

    /// Mittel- und Endgelenk einer Gliedmaße
    private static func solve(_ limb: Limb, root: CGPoint, l1: Double, l2: Double, offset: Double) -> (CGPoint, CGPoint) {
        switch limb {
        case let .angles(a, b):
            let mid = root + limbDir(a + offset) * l1
            return (mid, mid + limbDir(b + offset) * l2)
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

// MARK: - Zeichnen

/// Animierte Übungsfigur.
struct ExerciseFigureView: View {
    let animation: ExerciseAnimation
    var primary: Set<MuscleGroup> = []
    var secondary: Set<MuscleGroup> = []
    var isAnimating = true

    var body: some View {
        if isAnimating {
            TimelineView(.animation) { timeline in
                FigureCanvas(pose: animation.pose(at: timeline.date.timeIntervalSinceReferenceDate),
                             props: animation.props, primary: primary, secondary: secondary, zoom: animation.zoom)
            }
        } else {
            FigureCanvas(pose: animation.pose(at: 0), props: animation.props, primary: primary, secondary: secondary, zoom: animation.zoom)
        }
    }
}

struct FigureCanvas: View {
    let pose: ResolvedPose
    let props: [Prop]
    let primary: Set<MuscleGroup>
    let secondary: Set<MuscleGroup>
    var zoom: Double = 1

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 300, size.height / 200)
            context.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 200 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            if zoom != 1 {
                // Um die Bodenmitte verkleinern, damit der Boden an seinem Platz bleibt
                context.translateBy(x: 150, y: 196)
                context.scaleBy(x: zoom, y: zoom)
                context.translateBy(x: -150, y: -196)
            }
            FigurePainter(context: context, skeleton: Skeleton(pose), props: props,
                          primary: primary, secondary: secondary).draw()
        }
        .aspectRatio(1.5, contentMode: .fit)
    }
}

private struct FigurePainter {
    var context: GraphicsContext
    let skeleton: Skeleton
    let props: [Prop]
    let primary: Set<MuscleGroup>
    let secondary: Set<MuscleGroup>

    // Hautton der anatomischen Figur (helles Grau wie bei Anatomie-Illustrationen)
    static let near = (shadow: Color(white: 0.58), base: Color(white: 0.83), light: Color(white: 0.95))
    static let far = (shadow: Color(white: 0.50), base: Color(white: 0.70), light: Color(white: 0.80))
    static let outline = Color(white: 0.35).opacity(0.55)

    func draw() {
        var ctx = context
        let s = skeleton
        // Schatten am Boden
        let minX = ([s.hip, s.shoulder, s.headCenter] + s.toe + s.heel + s.wrist).map(\.x).min() ?? 100
        let maxX = ([s.hip, s.shoulder, s.headCenter] + s.toe + s.heel + s.wrist).map(\.x).max() ?? 200
        ctx.fill(Path(ellipseIn: CGRect(x: minX - 10, y: Body.floor - 4, width: maxX - minX + 20, height: 8)),
                 with: .color(.black.opacity(0.10)))

        for prop in props { drawStatic(prop, in: &ctx) }

        // Hintere Körperseite
        drawLeg(1, in: &ctx)
        drawArm(1, in: &ctx)
        // Rumpf, Becken und Kopf
        drawTorso(in: &ctx)
        drawHead(in: &ctx)
        // Vordere Körperseite
        drawLeg(0, in: &ctx)
        drawArm(0, in: &ctx)
        if props.contains(where: { if case .barbellBack = $0 { true } else { false } }) { drawBarbell(in: &ctx) }
        for prop in props { drawHeld(prop, in: &ctx) }
    }

    // MARK: Körperteile

    private func colors(_ farSide: Bool) -> (shadow: Color, base: Color, light: Color) {
        farSide ? Self.far : Self.near
    }

    private func drawLeg(_ i: Int, in ctx: inout GraphicsContext) {
        let s = skeleton, far = i == 1
        // Gliedmaßen mit Muskelbäuchen (Quadrizeps, Oberschenkelrückseite, Wade)
        let thigh = taperedCapsule(s.hip, s.knee[i], 10.5, 6.4)
            .union(bulge(s.hip, s.knee[i], t: 0.42, side: 1, offset: 4.2, length: 0.36, width: 7.4))
            .union(bulge(s.hip, s.knee[i], t: 0.38, side: -1, offset: 3.4, length: 0.34, width: 7))
        let shin = taperedCapsule(s.knee[i], s.ankle[i], 6.2, 3.6)
            .union(bulge(s.knee[i], s.ankle[i], t: 0.3, side: -1, offset: 2.6, length: 0.27, width: 5.4))
        let foot = taperedCapsule(s.heel[i] + s.footDir[i] * 1.5 - CGVector(dx: -s.footDir[i].dy, dy: s.footDir[i].dx) * 2.5,
                                  s.toe[i] - s.footDir[i] * 2 - CGVector(dx: -s.footDir[i].dy, dy: s.footDir[i].dx) * 2.3, 3.4, 2.4)
        shade(foot, from: s.heel[i], to: s.toe[i], width: 4, far: far, in: &ctx)
        shade(shin, from: s.knee[i], to: s.ankle[i], width: 6.6, far: far, in: &ctx)
        muscle(.calves, on: shin, segment: (s.knee[i], s.ankle[i]), t: 0.32, length: 0.5, side: -1, offset: 0.35, width: 0.7, radius: 6.2, far: far, in: &ctx)
        shade(thigh, from: s.hip, to: s.knee[i], width: 10.5, far: far, in: &ctx)
        muscle(.quads, on: thigh, segment: (s.hip, s.knee[i]), t: 0.55, length: 0.75, side: 1, offset: 0.3, width: 0.72, radius: 9, far: far, in: &ctx)
        muscle(.hamstrings, on: thigh, segment: (s.hip, s.knee[i]), t: 0.5, length: 0.72, side: -1, offset: 0.4, width: 0.6, radius: 9, far: far, in: &ctx)
        muscle(.hipFlexors, on: thigh, segment: (s.hip, s.knee[i]), t: 0.12, length: 0.3, side: 1, offset: 0.45, width: 0.45, radius: 9.5, far: far, in: &ctx)
        if far {
            // Innenseite des hinteren Beins ist sichtbar
            muscle(.adductors, on: thigh, segment: (s.hip, s.knee[i]), t: 0.35, length: 0.55, side: -1, offset: 0.05, width: 0.6, radius: 9.5, far: false, in: &ctx)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: s.knee[i].x - 2.5, y: s.knee[i].y - 2.5, width: 5, height: 5)),
                 with: .color(.white.opacity(far ? 0.06 : 0.12)))
    }

    private func drawArm(_ i: Int, in ctx: inout GraphicsContext) {
        let s = skeleton, far = i == 1
        let upper = taperedCapsule(s.shoulderJoint, s.elbow[i], 6.2, 4.2)
            .union(bulge(s.shoulderJoint, s.elbow[i], t: 0.12, side: 0, offset: 0, length: 0.28, width: 7))
            .union(bulge(s.shoulderJoint, s.elbow[i], t: 0.5, side: -1, offset: 1.6, length: 0.3, width: 4.8))
        let fore = taperedCapsule(s.elbow[i], s.wrist[i], 4.4, 2.8)
            .union(bulge(s.elbow[i], s.wrist[i], t: 0.25, side: 1, offset: 0.8, length: 0.28, width: 4.8))
        let handEnd = s.wrist[i] + (s.wrist[i] - s.elbow[i]).normalized * 6
        let hand = taperedCapsule(s.wrist[i], handEnd, 3.3, 2.6)
        shade(fore, from: s.elbow[i], to: s.wrist[i], width: 4, far: far, in: &ctx)
        shade(hand, from: s.wrist[i], to: handEnd, width: 3, far: far, in: &ctx)
        shade(upper, from: s.shoulderJoint, to: s.elbow[i], width: 6.2, far: far, in: &ctx)
        muscle(.triceps, on: upper, segment: (s.shoulderJoint, s.elbow[i]), t: 0.55, length: 0.6, side: -1, offset: 0.35, width: 0.6, radius: 6, far: far, in: &ctx)
        muscle(.shoulders, on: upper, segment: (s.shoulderJoint, s.elbow[i]), t: 0.08, length: 0.42, side: 0, offset: 0, width: 1.05, radius: 6.4, far: far, in: &ctx)
    }

    private func drawTorso(in ctx: inout GraphicsContext) {
        let s = skeleton
        let d = s.torsoDir
        let front = CGVector(dx: -d.dy, dy: d.dx)
        // Becken mit Gesäß
        let pelvisCenter = s.hip - front * 2.5 + d * 3
        let pelvis = ellipse(center: pelvisCenter, along: d, a: 13, b: 12.5)
        // Rumpf aus Brustkorb, Bauch und Verbindung zusammengesetzt
        let torso = taperedCapsule(s.hip + d * 4, s.shoulder - d * 3, 12, 13)
            .union(ellipse(center: s.shoulder - d * 15 + front * 1.5, along: d, a: 16, b: 15))
            .union(ellipse(center: s.hip + d * 17 + front * 0.5, along: d, a: 15, b: 12.5))
            .union(ellipse(center: s.shoulder - d * 4 - front * 2, along: d, a: 7, b: 10))
        let mid = s.hip + d * (Body.torso / 2)
        let gradient = Gradient(stops: [
            .init(color: Self.near.shadow, location: 0), .init(color: Self.near.base, location: 0.3),
            .init(color: Self.near.light, location: 0.55), .init(color: Self.near.base, location: 0.8),
            .init(color: Self.near.shadow, location: 1),
        ])
        let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: mid - front * 15, endPoint: mid + front * 15)
        ctx.fill(pelvis, with: shading)
        ctx.stroke(pelvis, with: .color(Self.outline), lineWidth: 0.5)
        clipped(pelvis, in: &ctx) { c in
            fillMuscle(.glutes, ellipse(center: pelvisCenter - front * 5 - d * 1, along: d, a: 12, b: 9.5), in: &c)
            fillMuscle(.hipAbductors, ellipse(center: pelvisCenter + d * 7, along: d, a: 7, b: 8), in: &c)
        }
        ctx.fill(torso, with: shading)
        ctx.stroke(torso, with: .color(Self.outline), lineWidth: 0.5)
        clipped(torso, in: &ctx) { c in
            fillMuscle(.core, ellipse(center: s.hip + d * 20 + front * 10, along: d, a: 16, b: 6), in: &c)
            fillMuscle(.obliques, ellipse(center: s.hip + d * 19 + front * 2, along: d, a: 14, b: 7), in: &c)
            fillMuscle(.lowerBack, ellipse(center: s.hip + d * 15 - front * 10, along: d, a: 13, b: 5), in: &c)
            fillMuscle(.chest, ellipse(center: s.shoulder - d * 13 + front * 11, along: d, a: 9.5, b: 6), in: &c)
            fillMuscle(.upperBack, ellipse(center: s.shoulder - d * 15 - front * 9, along: d, a: 14, b: 6.5), in: &c)
            fillMuscle(.hipFlexors, ellipse(center: s.hip + d * 5 + front * 10, along: d, a: 5.5, b: 4), in: &c)
        }
        // Rippenbogen und Bauchlinie andeuten
        var line = Path()
        line.move(to: s.shoulder - d * 22 + front * 13)
        line.addQuadCurve(to: s.hip + d * 8 + front * 10.5, control: s.hip + d * 18 + front * 13)
        ctx.stroke(line, with: .color(.black.opacity(0.06)), lineWidth: 0.8)
    }

    private func drawHead(in ctx: inout GraphicsContext) {
        let s = skeleton
        let neck = taperedCapsule(s.shoulder - s.torsoDir * 2, s.neckTop + s.headDir * 2, 5, 4.4)
        shade(neck, from: s.shoulder, to: s.neckTop, width: 4.5, far: false, in: &ctx)
        let front = CGVector(dx: -s.headDir.dy, dy: s.headDir.dx)
        let head = ellipse(center: s.headCenter + front * 0.5, along: s.headDir, a: Body.headRadius + 0.5, b: Body.headRadius - 1)
        var face = Path()
        // Nase und Kinn in Blickrichtung
        face.move(to: s.headCenter + front * 9 + s.headDir * 1)
        face.addLine(to: s.headCenter + front * 12.2 - s.headDir * 1.5)
        face.addLine(to: s.headCenter + front * 9.5 - s.headDir * 3.5)
        face.addQuadCurve(to: s.headCenter + front * 5 - s.headDir * 10.5, control: s.headCenter + front * 10 - s.headDir * 9)
        face.addLine(to: s.headCenter - s.headDir * 6)
        face.closeSubpath()
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [Self.near.light, Self.near.base, Self.near.shadow]),
            center: s.headCenter + front * 3 + s.headDir * 4, startRadius: 1, endRadius: 15)
        ctx.fill(face, with: shading)
        ctx.fill(head, with: shading)
        ctx.stroke(head, with: .color(Self.outline), lineWidth: 0.5)
    }

    // MARK: Hilfsfunktionen

    private func shade(_ path: Path, from a: CGPoint, to b: CGPoint, width: Double, far: Bool, in ctx: inout GraphicsContext) {
        let c = colors(far)
        let d = (b - a).normalized
        let n = CGVector(dx: -d.dy, dy: d.dx)
        let mid = a + (b - a) * 0.5
        let gradient = Gradient(stops: [
            .init(color: c.shadow, location: 0), .init(color: c.base, location: 0.28),
            .init(color: c.light, location: 0.5), .init(color: c.base, location: 0.75),
            .init(color: c.shadow, location: 1),
        ])
        ctx.fill(path, with: .linearGradient(gradient, startPoint: mid - n * (width + 1), endPoint: mid + n * (width + 1)))
        ctx.stroke(path, with: .color(Self.outline), lineWidth: 0.5)
    }

    /// Muskel auf einem Körpersegment (Ellipse entlang des Segments, auf das Segment beschnitten)
    private func muscle(_ group: MuscleGroup, on path: Path, segment: (CGPoint, CGPoint), t: Double, length: Double,
                        side: Double, offset: Double, width: Double, radius: Double, far: Bool, in ctx: inout GraphicsContext) {
        guard primary.contains(group) || secondary.contains(group) else { return }
        let (a, b) = segment
        let v = b - a
        let d = v.normalized
        let frontNormal = CGVector(dx: d.dy, dy: -d.dx)
        let center = a + v * t + frontNormal * (side * radius * offset)
        let shape = ellipse(center: center, along: d, a: v.length * length / 2, b: radius * width)
        clipped(path, in: &ctx) { c in fillMuscle(group, shape, dim: far, in: &c) }
    }

    private func fillMuscle(_ group: MuscleGroup, _ shape: Path, dim: Bool = false, in ctx: inout GraphicsContext) {
        let isPrimary = primary.contains(group)
        guard isPrimary || secondary.contains(group) else { return }
        let rect = shape.boundingRect
        let center = CGPoint(x: rect.midX - rect.width * 0.15, y: rect.midY - rect.height * 0.2)
        let colors: [Color] = dim
            ? [Color(red: 0.80, green: 0.30, blue: 0.27), Color(red: 0.62, green: 0.13, blue: 0.11), Color(red: 0.45, green: 0.07, blue: 0.06)]
            : [Color(red: 0.98, green: 0.47, blue: 0.42), Color(red: 0.85, green: 0.18, blue: 0.15), Color(red: 0.62, green: 0.07, blue: 0.06)]
        let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: colors), center: center, startRadius: 0,
                                                            endRadius: max(rect.width, rect.height) * 0.65)
        var c = ctx
        c.opacity = isPrimary ? 0.95 : 0.42
        c.fill(shape, with: shading)
        // Faserverlauf andeuten
        if isPrimary {
            c.opacity = 0.18
            c.stroke(shape, with: .color(.black), lineWidth: 0.4)
        }
    }

    private func clipped(_ path: Path, in ctx: inout GraphicsContext, _ body: (inout GraphicsContext) -> Void) {
        var c = ctx
        c.clip(to: path)
        body(&c)
    }

    // MARK: Geräte

    private func drawStatic(_ prop: Prop, in ctx: inout GraphicsContext) {
        switch prop {
        case let .bench(x, width, height):
            let top = Body.floor - height
            // Gestell
            for legX in [x + 6, x + width - 10] {
                let leg = Path(roundedRect: CGRect(x: legX, y: top + 6, width: 4, height: height - 6), cornerRadius: 1.5)
                ctx.fill(leg, with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.8)]),
                                                   startPoint: CGPoint(x: legX, y: 0), endPoint: CGPoint(x: legX + 4, y: 0)))
                ctx.stroke(leg, with: .color(Color(white: 0.6)), lineWidth: 0.5)
                let foot = Path(roundedRect: CGRect(x: legX - 5, y: Body.floor - 3, width: 14, height: 3), cornerRadius: 1.5)
                ctx.fill(foot, with: .color(Color(white: 0.85)))
                ctx.stroke(foot, with: .color(Color(white: 0.6)), lineWidth: 0.5)
            }
            // Polster
            let pad = Path(roundedRect: CGRect(x: x, y: top, width: width, height: 7), cornerRadius: 3)
            ctx.fill(pad, with: .linearGradient(Gradient(colors: [Color(white: 0.35), Color(white: 0.12)]),
                                               startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + 7)))
        case let .box(x, width, height):
            let rect = CGRect(x: x, y: Body.floor - height, width: width, height: height)
            let box = Path(roundedRect: rect, cornerRadius: 3)
            ctx.fill(box, with: .linearGradient(Gradient(colors: [Color(red: 0.86, green: 0.74, blue: 0.56), Color(red: 0.72, green: 0.58, blue: 0.40)]),
                                               startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            ctx.stroke(box, with: .color(Color(red: 0.5, green: 0.38, blue: 0.25).opacity(0.7)), lineWidth: 0.6)
        case let .mat(x, width):
            let mat = Path(roundedRect: CGRect(x: x, y: Body.floor - 2.5, width: width, height: 3.5), cornerRadius: 1.5)
            ctx.fill(mat, with: .color(Color(red: 0.42, green: 0.62, blue: 0.80)))
        default:
            break
        }
    }

    private func drawHeld(_ prop: Prop, in ctx: inout GraphicsContext) {
        let s = skeleton
        switch prop {
        case .dumbbells:
            drawDumbbell(at: handCenter(1), dim: true, in: &ctx)
            drawDumbbell(at: handCenter(0), dim: false, in: &ctx)
        case .dumbbell:
            drawDumbbell(at: handCenter(0), dim: false, in: &ctx)
        case .kettlebell:
            let c = handCenter(0) + CGVector(dx: 2, dy: 8)
            var handle = Path()
            handle.addArc(center: c - CGVector(dx: 0, dy: 6), radius: 5, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(handle, with: .color(Color(white: 0.15)), lineWidth: 2.2)
            let bell = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 6, width: 16, height: 15))
            ctx.fill(bell, with: .radialGradient(Gradient(colors: [Color(white: 0.45), Color(white: 0.12)]),
                                                center: c - CGVector(dx: 3, dy: 3), startRadius: 0, endRadius: 11))
        case .anklePad:
            let a = s.ankle[0]
            let roll = Path(ellipseIn: CGRect(x: a.x - 6, y: a.y - 14, width: 12, height: 10))
            ctx.fill(roll, with: .radialGradient(Gradient(colors: [Color(white: 0.4), Color(white: 0.12)]),
                                                center: a - CGVector(dx: 2, dy: 11), startRadius: 0, endRadius: 8))
            let post = Path(roundedRect: CGRect(x: a.x - 1.5, y: a.y - 9, width: 3, height: Body.floor - a.y + 9), cornerRadius: 1)
            ctx.fill(post, with: .color(Color(white: 0.8)))
        default:
            break
        }
    }

    private func handCenter(_ i: Int) -> CGPoint {
        skeleton.wrist[i] + (skeleton.wrist[i] - skeleton.elbow[i]).normalized * 3.5
    }

    /// Kurzhantel von der Seite: Scheiben mit Griff zur Kamera
    private func drawDumbbell(at c: CGPoint, dim: Bool, in ctx: inout GraphicsContext) {
        let outer = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
        ctx.fill(outer, with: .radialGradient(Gradient(colors: [Color(white: dim ? 0.30 : 0.42), Color(white: 0.06)]),
                                             center: c - CGVector(dx: 3, dy: 3), startRadius: 0, endRadius: 11))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11)),
                   with: .color(Color(white: dim ? 0.35 : 0.5).opacity(0.7)), lineWidth: 0.7)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)), with: .color(Color(white: 0.75)))
    }

    private func drawBarbell(in ctx: inout GraphicsContext) {
        let s = skeleton
        let front = CGVector(dx: -s.torsoDir.dy, dy: s.torsoDir.dx)
        let c = s.shoulder - s.torsoDir * 4 - front * 8
        let plate = Path(ellipseIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32))
        ctx.fill(plate, with: .radialGradient(Gradient(colors: [Color(white: 0.35), Color(white: 0.08)]),
                                             center: c - CGVector(dx: 5, dy: 5), startRadius: 0, endRadius: 21))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)), with: .color(Color(white: 0.4).opacity(0.6)), lineWidth: 0.8)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(Color(white: 0.8)))
    }

    // MARK: Formen

    /// Kapsel mit unterschiedlichen Radien an beiden Enden
    private func taperedCapsule(_ a: CGPoint, _ b: CGPoint, _ r1: Double, _ r2: Double) -> Path {
        let v = b - a
        let d = v.length > 0.001 ? v.normalized : CGVector(dx: 0, dy: 1)
        let n = CGVector(dx: -d.dy, dy: d.dx)
        var path = Path()
        path.move(to: a + n * r1)
        path.addLine(to: b + n * r2)
        for k in 1...10 {
            let phi = Double(k) / 10 * .pi
            path.addLine(to: b + (n * cos(phi) + d * sin(phi)) * r2)
        }
        path.addLine(to: a - n * r1)
        for k in 1...10 {
            let phi = Double(k) / 10 * .pi
            path.addLine(to: a + (n * -cos(phi) + d * -sin(phi)) * r1)
        }
        path.closeSubpath()
        return path
    }

    /// Muskelbauch: Ellipse entlang eines Segments, zur Vorder- (1) oder Rückseite (−1) versetzt
    private func bulge(_ a: CGPoint, _ b: CGPoint, t: Double, side: Double, offset: Double, length: Double, width: Double) -> Path {
        let v = b - a
        let d = v.length > 0.001 ? v.normalized : CGVector(dx: 0, dy: 1)
        let frontNormal = CGVector(dx: d.dy, dy: -d.dx)
        return ellipse(center: a + v * t + frontNormal * (side * offset), along: d, a: v.length * length, b: width)
    }

    /// Ellipse mit Halbachse `a` entlang `along`
    private func ellipse(center: CGPoint, along: CGVector, a: Double, b: Double) -> Path {
        let d = along.length > 0.001 ? along.normalized : CGVector(dx: 1, dy: 0)
        let n = CGVector(dx: -d.dy, dy: d.dx)
        var path = Path()
        for k in 0...24 {
            let phi = Double(k) / 24 * 2 * .pi
            let p = center + d * (a * cos(phi)) + n * (b * sin(phi))
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
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
