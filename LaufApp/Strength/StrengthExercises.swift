import Foundation
import CoreGraphics

/// Kraftübung mit Animation und Erklärung.
struct StrengthExercise: Identifiable {
    enum Measure { case reps, seconds }

    let id: String
    let name: String
    let primary: [MuscleGroup]
    let secondary: [MuscleGroup]
    let equipment: String
    /// Kurzer Technikhinweis (eine Zeile)
    let cue: String
    let steps: [String]
    let mistakes: [String]
    /// Warum die Übung Läufern hilft
    let benefit: String
    var measure: Measure = .reps
    var perSide = false
    /// Mit Zusatzgewicht möglich (sonst wird kein Gewicht abgefragt)
    var usesWeight = true
    let animation: ExerciseAnimation
}

extension StrengthExercise {
    static func with(id: String) -> StrengthExercise? { all.first { $0.id == id } }
}

// MARK: - Hilfen für die Haltungen

private let forward = 0.0, downward = 90.0, upward = -90.0, backward = 180.0

/// Fußgelenk über einem flach aufgesetzten Fuß, dessen Ferse bei `x` steht
private func flat(_ x: Double) -> CGPoint { CGPoint(x: x + Body.heel, y: Body.floor - Body.ankleHeight) }

/// Fußgelenk, wenn der Fußballen bei `toe` steht und der Fuß die Richtung `foot` hat
private func ankle(toe: CGPoint, foot: Double) -> CGPoint {
    let f = CGVector(dx: sin(foot * .pi / 180), dy: cos(foot * .pi / 180))
    let sole = CGVector(dx: -f.dy, dy: f.dx)
    return toe - f * Body.toe - sole * Body.ankleHeight
}

/// Hüfte zu einem Fußgelenk bei gegebenen Winkeln von Unterschenkel und Oberschenkel
private func hip(above ankle: CGPoint, shin: Double, thigh: Double) -> CGPoint {
    func dir(_ a: Double) -> CGVector { CGVector(dx: sin(a * .pi / 180), dy: cos(a * .pi / 180)) }
    return ankle - dir(shin) * Body.shin - dir(thigh) * Body.thigh
}

private func shifted(_ p: CGPoint, _ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }

private let hanging = Limb.angles(0, 0)

/// Griff der hinteren Hand an der Haltestange: dort, wo sie in der ersten Haltung mit diesem Arm liegt.
/// Mit festem Zielpunkt bleibt die Hand an der Stange, während sich der Körper hebt und senkt.
private func postGrip(_ pose: Pose) -> Limb {
    .reach(Skeleton(ResolvedPose(pose)).wrist[1], bend: 90)
}

// MARK: - Katalog

extension StrengthExercise {
    static let all: [StrengthExercise] = [
        gobletSquat, backSquat, romanianDeadlift, bulgarianSplitSquat, reverseLunge, stepUp, singleLegSquat,
        singleLegRDL, calfRaise, soleusRaise, heelDrop, gluteBridge, singleLegBridge, nordicCurl,
        copenhagenPlank, sideLyingAbduction, plank, sidePlank, deadBug, birdDog, pogoJumps, boxJump, jumpLunge,
    ]

    static let gobletSquat = StrengthExercise(
        id: "gobletSquat", name: "Goblet Squat",
        primary: [.quads, .glutes], secondary: [.adductors, .core, .upperBack],
        equipment: "Kettlebell oder Kurzhantel",
        cue: "Gewicht eng an der Brust, Oberkörper bleibt aufrecht.",
        steps: [
            "Füße etwa schulterbreit, Fußspitzen leicht nach außen. Kettlebell mit beiden Händen vor der Brust halten.",
            "Hüfte nach hinten unten senken, bis die Oberschenkel mindestens waagrecht sind. Knie zeigen in Richtung der Fußspitzen.",
            "Über die ganze Fußsohle kraftvoll nach oben drücken, oben das Gesäß anspannen.",
        ],
        mistakes: ["Fersen heben ab", "Knie fallen nach innen", "Rücken rundet sich am tiefsten Punkt"],
        benefit: "Kräftigt Oberschenkel und Gesäß, die bei jedem Schritt die Landung abfangen. Ideal, um die Kniebeuge sauber zu lernen.",
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 3, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(149), bend: forward),
                     nearArm: .angles(18, 142), farArm: .angles(14, 140)),
                Pose(hip: CGPoint(x: 123, y: 149), torso: 27, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(149), bend: forward),
                     nearArm: .angles(58, 150), farArm: .angles(54, 148)),
            ],
            holds: [0.5, 0.3], moves: [1.4, 1.1], props: [.kettlebell]))

    static let backSquat = StrengthExercise(
        id: "backSquat", name: "Kniebeuge mit Langhantel",
        primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .lowerBack, .core],
        equipment: "Langhantel, Rack",
        cue: "Bis etwa 90° Kniewinkel, schwer und kontrolliert.",
        steps: [
            "Stange auf dem oberen Rücken ablegen, Hände etwas breiter als schulterbreit, Ellbogen nach unten.",
            "Tief einatmen, Bauch anspannen und die Hüfte nach hinten unten bewegen, bis die Knie etwa 90° gebeugt sind.",
            "Kraftvoll nach oben drücken; die Bewegung nach oben so schnell wie möglich ausführen.",
        ],
        mistakes: ["Oberkörper kippt weit nach vorn", "Knie fallen nach innen", "Ohne Aufwärmsätze direkt schwer beginnen"],
        benefit: "Schwere Kniebeugen mit wenigen Wiederholungen verbessern nachweislich die Laufökonomie, ohne dass die Muskeln merklich wachsen.",
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 4, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(149), bend: forward),
                     nearArm: .angles(-40, 165), farArm: .angles(-45, 160), armsFollowTorso: true),
                Pose(hip: CGPoint(x: 124, y: 135), torso: 32, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(149), bend: forward),
                     nearArm: .angles(-40, 165), farArm: .angles(-45, 160), armsFollowTorso: true),
            ],
            holds: [0.6, 0.2], moves: [1.5, 0.9], props: [.barbellBack]))

    static let romanianDeadlift = StrengthExercise(
        id: "romanianDeadlift", name: "Rumänisches Kreuzheben",
        primary: [.hamstrings, .glutes], secondary: [.lowerBack, .upperBack, .core],
        equipment: "Kurzhanteln oder Langhantel",
        cue: "Hüfte nach hinten schieben, Rücken bleibt gerade.",
        steps: [
            "Aufrecht stehen, Hanteln vor den Oberschenkeln, Knie leicht gebeugt.",
            "Hüfte nach hinten schieben und den Oberkörper mit geradem Rücken nach vorn neigen. Die Hanteln gleiten nah an den Beinen nach unten.",
            "Wenn die Dehnung in der Oberschenkelrückseite deutlich ist, die Hüfte nach vorn bringen und aufrichten.",
        ],
        mistakes: ["Rundrücken", "Knie werden zu stark gebeugt (wird zur Kniebeuge)", "Hanteln entfernen sich vom Körper"],
        benefit: "Stärkt die Oberschenkelrückseite und das Gesäß – wichtig für den kraftvollen Abdruck und gegen Zerrungen.",
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 2, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(148), bend: forward),
                     nearArm: .angles(4, 2), farArm: .angles(2, 0)),
                Pose(hip: CGPoint(x: 124, y: 103), torso: 80, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(148), bend: forward),
                     nearArm: hanging, farArm: hanging),
            ],
            holds: [0.5, 0.3], moves: [1.6, 1.2], props: [.dumbbells]))

    /// Fußgelenk des hinteren Beins: genau über der Bankkante, der Spann liegt auf der Bank,
    /// damit das Schienbein beim Absenken vor der Bank nach unten geht
    private static let bulgarianRearAnkle = CGPoint(x: 101, y: 139)

    static let bulgarianSplitSquat = StrengthExercise(
        id: "bulgarianSplitSquat", name: "Bulgarische Kniebeuge",
        primary: [.quads, .glutes], secondary: [.adductors, .hamstrings, .hipFlexors, .core],
        equipment: "Bank, Kurzhanteln",
        cue: "Hinterer Fuß auf der Bank, Gewicht auf dem vorderen Bein.",
        steps: [
            "Mit dem Rücken zur Bank stellen und den Spann des hinteren Fußes auf die Bank legen. Vorderer Fuß gut einen Schritt vor der Bank.",
            "Senkrecht nach unten gehen, bis das hintere Knie fast den Boden berührt.",
            "Über die Ferse des vorderen Fußes nach oben drücken. Nach allen Wiederholungen die Seite wechseln.",
        ],
        mistakes: ["Vorderes Knie knickt nach innen", "Vorderer Fuß steht zu nah an der Bank", "Oberkörper fällt nach vorn"],
        benefit: "Einbeinige Kraft wie beim Laufen: trainiert jedes Bein einzeln und gleicht Seitenunterschiede aus.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 138, y: 104), torso: 8, nearLeg: .reach(flat(171), bend: forward), farLeg: .reach(bulgarianRearAnkle, bend: downward),
                     nearArm: hanging, farArm: hanging, farFoot: -72),
                Pose(hip: CGPoint(x: 129, y: 136), torso: 12, nearLeg: .reach(flat(171), bend: forward), farLeg: .reach(bulgarianRearAnkle, bend: downward),
                     nearArm: hanging, farArm: hanging, farFoot: -72),
            ],
            holds: [0.4, 0.3], moves: [1.3, 1.1], props: [.bench(x: 30, width: 70, height: 42), .dumbbells]))

    static let reverseLunge = StrengthExercise(
        id: "reverseLunge", name: "Ausfallschritt rückwärts",
        primary: [.quads, .glutes], secondary: [.hamstrings, .adductors, .calves, .core],
        equipment: "Kurzhanteln (optional)",
        cue: "Großer Schritt nach hinten, vorderes Knie über dem Fuß.",
        steps: [
            "Hüftbreit stehen, Hanteln seitlich halten.",
            "Mit einem Bein einen großen Schritt nach hinten machen und absenken, bis das hintere Knie knapp über dem Boden ist.",
            "Über das vordere Bein zurück in den Stand drücken. Seiten abwechseln oder nacheinander trainieren.",
        ],
        mistakes: ["Schritt zu kurz", "Oberkörper kippt nach vorn", "Vorderes Knie wandert nach innen"],
        benefit: "Gelenkschonender als der Ausfallschritt nach vorn und schult die Stabilität auf einem Bein.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 2, nearLeg: .reach(flat(146), bend: forward), farLeg: .reach(flat(148), bend: forward),
                     nearArm: hanging, farArm: hanging),
                Pose(hip: CGPoint(x: 126, y: 141), torso: 6, nearLeg: .reach(flat(146), bend: forward),
                     farLeg: .reach(ankle(toe: CGPoint(x: 86, y: 186), foot: 55), bend: downward),
                     nearArm: hanging, farArm: hanging, farFoot: 55),
            ],
            holds: [0.4, 0.3], moves: [1.2, 1.2], props: [.dumbbells]))

    static let stepUp = StrengthExercise(
        id: "stepUp", name: "Step-up auf die Box",
        primary: [.quads, .glutes], secondary: [.hamstrings, .calves, .hipFlexors],
        equipment: "Box oder Stufe (ca. kniehoch), Kurzhanteln",
        cue: "Nur mit dem oberen Bein hochdrücken, nicht abspringen.",
        steps: [
            "Einen Fuß komplett auf die Box stellen.",
            "Das Gewicht nach vorn verlagern und nur mit dem oberen Bein nach oben drücken; das andere Knie kommt nach vorn hoch wie beim Laufen.",
            "Kontrolliert wieder absteigen. Nach allen Wiederholungen die Seite wechseln.",
        ],
        mistakes: ["Mit dem unteren Bein abstoßen", "Knie knickt nach innen", "Box zu hoch"],
        benefit: "Sehr laufnahe Bewegung: Hüft- und Kniestreckung auf einem Bein mit Kniehub des anderen Beins.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 136, y: 110), torso: 14, nearLeg: .reach(CGPoint(x: 178, y: 135), bend: forward), farLeg: .reach(flat(104), bend: forward),
                     nearArm: hanging, farArm: hanging),
                stepUpLift, stepUpMid,
                Pose(hip: CGPoint(x: 174, y: 57), torso: 4, nearLeg: .reach(CGPoint(x: 178, y: 135), bend: forward), farLeg: .angles(72, 2),
                     nearArm: hanging, farArm: hanging, farFoot: 105),
                stepUpMid, stepUpLift,
            ],
            holds: [0.4, 0, 0, 0.4, 0, 0], moves: [0.35, 0.35, 0.45, 0.45, 0.4, 0.45],
            props: [.box(x: 152, width: 80, height: 45), .dumbbells]))

    /// Zwischenstellungen: Das hintere Bein löst sich erst hinter der Box vom Boden (Knie bleibt vor der
    /// Kante), dann kommt der Fuß angewinkelt über die Kante nach vorn
    private static let stepUpLift = Pose(hip: CGPoint(x: 148, y: 90), torso: 10, nearLeg: .reach(CGPoint(x: 178, y: 135), bend: forward),
                                         farLeg: .angles(5, -60), nearArm: hanging, farArm: hanging, farFoot: 30)

    /// Zwischenstellung: Das hintere Bein ist schon vom Boden gelöst und angewinkelt, damit der Fuß
    /// über die Kante der Box nach vorn kommt
    private static let stepUpMid = Pose(hip: CGPoint(x: 166, y: 66), torso: 6, nearLeg: .reach(CGPoint(x: 178, y: 135), bend: forward),
                                        farLeg: .angles(35, -95), nearArm: hanging, farArm: hanging, farFoot: 0)

    static let singleLegSquat = StrengthExercise(
        id: "singleLegSquat", name: "Einbeinige Kniebeuge zur Box",
        primary: [.quads, .glutes], secondary: [.hipAbductors, .adductors, .core],
        equipment: "Box oder Bank",
        cue: "Langsam auf einem Bein absetzen, Knie bleibt stabil.",
        steps: [
            "Vor einer Box auf einem Bein stehen, das andere Bein leicht nach vorn halten, Arme nach vorn.",
            "Langsam auf dem Standbein nach hinten unten setzen, bis das Gesäß die Box berührt.",
            "Ohne Schwung wieder aufstehen. Nach allen Wiederholungen die Seite wechseln.",
        ],
        mistakes: ["Fallen statt kontrolliert absetzen", "Knie wandert nach innen", "Becken kippt zur Seite"],
        benefit: "Trainiert die Kontrolle von Hüfte und Knie auf einem Bein – genau das, was bei der Landung jedes Laufschritts gefordert ist.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 2, nearLeg: .reach(flat(146), bend: forward), farLeg: .angles(25, 12),
                     nearArm: .angles(70, 80), farArm: .angles(66, 76), farFoot: 100),
                Pose(hip: CGPoint(x: 113, y: 131), torso: 40, nearLeg: .reach(flat(146), bend: forward), farLeg: .angles(78, 80),
                     nearArm: .angles(88, 90), farArm: .angles(84, 86), farFoot: 165),
            ],
            holds: [0.4, 0.3], moves: [1.8, 1.1], props: [.box(x: 66, width: 46, height: 45)]))

    static let singleLegRDL = StrengthExercise(
        id: "singleLegRDL", name: "Einbeiniges Kreuzheben",
        primary: [.hamstrings, .glutes], secondary: [.hipAbductors, .lowerBack, .core],
        equipment: "Kurzhantel oder Kettlebell",
        cue: "Oberkörper und hinteres Bein bilden eine Linie.",
        steps: [
            "Auf einem Bein stehen, Knie leicht gebeugt, Hantel in der Hand der Gegenseite.",
            "Oberkörper nach vorn neigen, während das freie Bein gestreckt nach hinten geht, bis beide etwa waagrecht sind.",
            "Über das Gesäß des Standbeins wieder aufrichten. Becken bleibt gerade.",
        ],
        mistakes: ["Becken dreht nach außen auf", "Rundrücken", "Standbein komplett durchgestreckt"],
        benefit: "Stärkt Oberschenkelrückseite und seitliche Hüftmuskeln auf einem Bein – schützt vor Zerrungen und verbessert das Gleichgewicht.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 144, y: 97), torso: 2, nearLeg: .reach(flat(146), bend: forward), farLeg: .angles(-8, -34),
                     nearArm: hanging, farArm: .angles(4, 2), farFoot: 88),
                Pose(hip: CGPoint(x: 136, y: 103), torso: 84, nearLeg: .reach(flat(146), bend: forward), farLeg: .angles(-84, -86),
                     nearArm: hanging, farArm: .angles(20, 10), farFoot: 4),
            ],
            holds: [0.4, 0.4], moves: [1.6, 1.3], props: [.dumbbell(inFarHand: true)]))

    private static let raiseToe = CGPoint(x: 172, y: 166)

    /// Hand an der Haltestange (Wadenheben, Fersensenken), etwa auf Brusthöhe vor dem Körper
    private static let raiseGrip = postGrip(Pose(hip: shifted(ankle(toe: raiseToe, foot: 80), -3.5, -82), torso: 2,
                                                 nearLeg: .reach(ankle(toe: raiseToe, foot: 80), bend: forward), farLeg: .angles(8, -70),
                                                 nearArm: hanging, farArm: .angles(40, 75)))

    static let calfRaise = StrengthExercise(
        id: "calfRaise", name: "Einbeiniges Wadenheben",
        primary: [.calves], secondary: [.core],
        equipment: "Stufe, Kurzhantel (optional)",
        cue: "Volle Bewegung: Ferse ganz unten bis ganz oben.",
        steps: [
            "Mit dem Fußballen eines Fußes auf die Kante einer Stufe stellen, mit einer Hand an einer Wand oder Stange festhalten.",
            "Bei gestrecktem Knie die Ferse so hoch wie möglich drücken, kurz halten.",
            "Langsam absenken, bis die Ferse unter der Stufenkante ist.",
        ],
        mistakes: ["Wippen statt kontrollierter Bewegung", "Nur halbe Bewegung", "Knie beugt sich"],
        benefit: "Die Wadenmuskeln liefern beim langsamen und mittleren Laufen den größten Teil der Stützkraft (Dorn et al. 2012). Kräftige Waden entlasten Achillessehne und Schienbein.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: shifted(ankle(toe: raiseToe, foot: 112), -4, -82), torso: 2,
                     nearLeg: .reach(ankle(toe: raiseToe, foot: 112), bend: forward), farLeg: .angles(8, -70),
                     nearArm: hanging, farArm: raiseGrip, nearFoot: 112, farFoot: 20),
                Pose(hip: shifted(ankle(toe: raiseToe, foot: 52), -3, -82), torso: 2,
                     nearLeg: .reach(ankle(toe: raiseToe, foot: 52), bend: forward), farLeg: .angles(8, -70),
                     nearArm: hanging, farArm: raiseGrip, nearFoot: 52, farFoot: 20),
            ],
            holds: [0.3, 0.5], moves: [0.9, 1.5], props: [.box(x: 160, width: 70, height: 20), .dumbbell(inFarHand: false), .handPost]))

    private static let soleusToe = CGPoint(x: 168, y: 186)

    static let soleusRaise = StrengthExercise(
        id: "soleusRaise", name: "Wadenheben mit gebeugtem Knie",
        primary: [.calves], secondary: [.quads],
        equipment: "Kurzhanteln oder Langhantel",
        cue: "Knie bleiben gebeugt – so arbeitet vor allem der Soleus.",
        steps: [
            "Hüftbreit stehen, Knie etwa 30–45° beugen und die Haltung beibehalten.",
            "Fersen so hoch wie möglich drücken, oben kurz halten.",
            "Langsam absenken. Für mehr Belastung zusätzlich Gewicht halten oder einbeinig ausführen.",
        ],
        mistakes: ["Knie strecken sich beim Hochdrücken", "Zu schnell", "Zu leichtes Gewicht – der Soleus verträgt viel"],
        benefit: "Soleus und Gastrocnemius tragen beim Laufen den größten Teil der Stützkraft (Dorn et al. 2012). Mit gebeugtem Knie wird vor allem der Soleus trainiert.",
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: hip(above: ankle(toe: soleusToe, foot: 90), shin: -22, thigh: 40), torso: 12,
                     nearLeg: .reach(ankle(toe: soleusToe, foot: 90), bend: forward),
                     farLeg: .reach(ankle(toe: shifted(soleusToe, 3, 0), foot: 90), bend: forward),
                     nearArm: hanging, farArm: hanging, nearFoot: 90, farFoot: 90),
                Pose(hip: hip(above: ankle(toe: soleusToe, foot: 52), shin: -22, thigh: 40), torso: 12,
                     nearLeg: .reach(ankle(toe: soleusToe, foot: 52), bend: forward),
                     farLeg: .reach(ankle(toe: shifted(soleusToe, 3, 0), foot: 52), bend: forward),
                     nearArm: hanging, farArm: hanging, nearFoot: 52, farFoot: 52),
            ],
            holds: [0.3, 0.5], moves: [0.9, 1.4], props: [.dumbbells]))

    static let heelDrop = StrengthExercise(
        id: "heelDrop", name: "Exzentrisches Fersensenken",
        primary: [.calves], secondary: [],
        equipment: "Stufe, Rucksack mit Gewicht (optional)",
        cue: "Auf zwei Beinen hoch, auf einem Bein langsam (3 s) absenken.",
        steps: [
            "Mit den Fußballen auf eine Stufe stellen und mit beiden Beinen auf die Zehenspitzen drücken.",
            "Ein Bein anheben und auf dem anderen die Ferse in etwa drei Sekunden unter die Stufenkante absenken.",
            "Mit beiden Beinen wieder hochdrücken. Auch mit leicht gebeugtem Knie ausführen.",
        ],
        mistakes: ["Zu schnell absenken", "Auf einem Bein hochdrücken (die Hubphase ist bewusst beidbeinig)"],
        benefit: "Das klassische Programm nach Alfredson (1998) bei Achillessehnenbeschwerden: im Original 3 × 15 mit gestrecktem und 3 × 15 mit gebeugtem Knie, zweimal täglich über 12 Wochen. Stärkt Sehne und Wade.",
        perSide: true,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: shifted(ankle(toe: raiseToe, foot: 52), -3, -82), torso: 2,
                     nearLeg: .reach(ankle(toe: raiseToe, foot: 52), bend: forward), farLeg: .angles(6, -60),
                     nearArm: hanging, farArm: raiseGrip, nearFoot: 52, farFoot: 28),
                Pose(hip: shifted(ankle(toe: raiseToe, foot: 115), -4, -82), torso: 2,
                     nearLeg: .reach(ankle(toe: raiseToe, foot: 115), bend: forward), farLeg: .angles(6, -60),
                     nearArm: hanging, farArm: raiseGrip, nearFoot: 115, farFoot: 28),
            ],
            holds: [0.4, 0.3], moves: [3.0, 0.9], props: [.box(x: 160, width: 70, height: 20), .handPost]))

    /// Fußgelenke über den flach auf der Matte stehenden Füßen
    private static let bridgeFeet = (near: CGPoint(x: 198, y: 176.5), far: CGPoint(x: 201, y: 176.5))

    static let gluteBridge = StrengthExercise(
        id: "gluteBridge", name: "Hüftheben",
        primary: [.glutes], secondary: [.hamstrings, .core, .lowerBack],
        equipment: "Matte",
        cue: "Hüfte hoch, bis Schultern, Hüfte und Knie eine Linie bilden.",
        steps: [
            "Auf den Rücken legen, Füße hüftbreit aufstellen, Arme neben dem Körper.",
            "Gesäß anspannen und die Hüfte anheben, bis Oberkörper und Oberschenkel eine Linie bilden.",
            "Oben kurz halten und langsam absenken.",
        ],
        mistakes: ["Hohlkreuz statt Gesäßspannung", "Füße zu weit weg (Oberschenkelrückseite krampft)"],
        benefit: "Aktiviert das Gesäß, das beim Laufen die Hüfte streckt und das Becken stabilisiert.",
        usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 150, y: 174), torso: -90, nearLeg: .reach(bridgeFeet.near, bend: upward), farLeg: .reach(bridgeFeet.far, bend: upward),
                     nearArm: .angles(82, 88), farArm: .angles(80, 86)),
                Pose(hip: CGPoint(x: 144, y: 145), torso: -123, head: 30, nearLeg: .reach(bridgeFeet.near, bend: upward), farLeg: .reach(bridgeFeet.far, bend: upward),
                     nearArm: .angles(82, 88), farArm: .angles(80, 86)),
            ],
            holds: [0.4, 0.6], moves: [1.0, 1.3], props: [.mat(x: 60, width: 180)]))

    static let singleLegBridge = StrengthExercise(
        id: "singleLegBridge", name: "Einbeiniges Hüftheben",
        primary: [.glutes], secondary: [.hamstrings, .hipAbductors, .core],
        equipment: "Matte",
        cue: "Becken bleibt waagrecht, das gestreckte Bein in Verlängerung.",
        steps: [
            "Auf den Rücken legen, ein Fuß aufgestellt, das andere Bein gestreckt in der Luft.",
            "Über die Ferse des aufgestellten Fußes die Hüfte anheben, bis der Körper eine Linie bildet.",
            "Langsam absenken, ohne dass das Becken zur Seite kippt. Danach Seite wechseln.",
        ],
        mistakes: ["Becken kippt zur Seite", "Schwung aus dem freien Bein"],
        benefit: "Fordert das Gesäß einseitig wie in der Standphase beim Laufen und stärkt die Beckenstabilität.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 150, y: 174), torso: -90, nearLeg: .reach(bridgeFeet.near, bend: upward), farLeg: .angles(118, 118),
                     nearArm: .angles(82, 88), farArm: .angles(80, 86), farFoot: 208),
                Pose(hip: CGPoint(x: 144, y: 145), torso: -123, head: 30, nearLeg: .reach(bridgeFeet.near, bend: upward), farLeg: .angles(123, 123),
                     nearArm: .angles(82, 88), farArm: .angles(80, 86), farFoot: 213),
            ],
            holds: [0.4, 0.6], moves: [1.0, 1.3], props: [.mat(x: 60, width: 180)]))

    static let nordicCurl = StrengthExercise(
        id: "nordicCurl", name: "Nordic Hamstring Curl",
        primary: [.hamstrings], secondary: [.glutes, .calves, .core],
        equipment: "Matte, Partner oder fester Halt für die Fersen",
        cue: "So langsam wie möglich nach vorn sinken lassen.",
        steps: [
            "Aufrecht knien, die Fersen werden vom Partner oder unter einem festen Gegenstand gehalten.",
            "Körper gerade halten und langsam nach vorn sinken lassen, indem die Oberschenkelrückseite bremst.",
            "Wenn du nicht mehr halten kannst, mit den Händen abfangen und dich mit den Armen zurückdrücken.",
        ],
        mistakes: ["In der Hüfte abknicken", "Zu schnell fallen lassen", "Zu viele Wiederholungen zu Beginn – Muskelkater ist anfangs stark"],
        benefit: "Bremsendes (exzentrisches) Training der Oberschenkelrückseite. Bei Amateurfußballern senkte es Verletzungen der Oberschenkelrückseite um rund zwei Drittel.",
        usesWeight: false,
        animation: ExerciseAnimation(
            // Der Körper kippt als Ganzes um die Knie, die auf der Matte bleiben (Zwischenbilder, damit sich
            // die Knie unterwegs nicht vom Drehpunkt lösen)
            frames: [nordic(0), nordic(1 / 3), nordic(2 / 3), nordic(1), nordic(2 / 3), nordic(1 / 3)],
            holds: [0.6, 0, 0, 0.2, 0, 0], moves: [1.07, 1.07, 1.07, 0.43, 0.43, 0.44],
            props: [.mat(x: 40, width: 170), .anklePad]))

    /// Knie auf der Matte, um das der Körper beim Nordic Curl nach vorn kippt
    private static let nordicKnee = CGPoint(x: 110, y: 178)

    /// Haltung beim Nordic Curl: `t` = 0 aufrecht kniend bis 1 = 60° nach vorn geneigt
    private static func nordic(_ t: Double) -> Pose {
        let lean = 60 * t
        // Oberschenkel und Rumpf bilden eine Linie; die Hüfte liegt auf dem Kreis um das Knie
        let hip = CGPoint(x: nordicKnee.x + Body.thigh * sin(lean * .pi / 180), y: nordicKnee.y - Body.thigh * cos(lean * .pi / 180))
        let shin = Limb.angles(-lean, -88)
        return Pose(hip: hip, torso: lean, nearLeg: shin, farLeg: shin,
                    nearArm: .angles(15 + 40 * t, 160 - 65 * t), farArm: .angles(12 + 38 * t, 158 - 66 * t),
                    nearFoot: -65, farFoot: -65)
    }

    static let copenhagenPlank = StrengthExercise(
        id: "copenhagenPlank", name: "Copenhagen Plank",
        primary: [.adductors], secondary: [.obliques, .core, .hipAbductors, .shoulders],
        equipment: "Bank, Matte",
        cue: "Oberes Bein auf der Bank, Körper bildet eine gerade Linie.",
        steps: [
            "Seitlich neben eine Bank legen, auf den Unterarm stützen und das obere Bein (Innenseite Knie oder Knöchel) auf die Bank legen.",
            "Hüfte anheben, bis der Körper gerade ist; das untere Bein zur Bank führen.",
            "Position halten bzw. langsam absenken und wieder anheben. Anfänger legen das Knie statt des Knöchels auf.",
        ],
        mistakes: ["Hüfte hängt durch", "Schulter weicht nach oben aus", "Zu Beginn mit gestrecktem Bein überfordern"],
        benefit: "Kräftigt die Adduktoren an der Innenseite des Oberschenkels; ein Programm damit senkte bei Fußballern das Risiko für Leistenprobleme um 41 %.",
        measure: .seconds, perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 110, y: 142), torso: -84.5, head: 0, nearLeg: .reach(CGPoint(x: 196, y: 138.5), bend: upward),
                     farLeg: .reach(CGPoint(x: 182, y: 180), bend: upward),
                     nearArm: .angles(84, 88), farArm: .forearmSupport(0)),
                Pose(hip: CGPoint(x: 110, y: 142), torso: -84.5, head: 0, nearLeg: .reach(CGPoint(x: 196, y: 138.5), bend: upward),
                     farLeg: .reach(CGPoint(x: 194, y: 156), bend: upward),
                     nearArm: .angles(84, 88), farArm: .forearmSupport(0)),
            ],
            holds: [0.5, 1.2], moves: [1.1, 1.1], props: [.mat(x: 30, width: 150), .crossBench(x: 182, width: 30, height: 42)], frontal: true))

    static let sideLyingAbduction = StrengthExercise(
        id: "sideLyingAbduction", name: "Seitliches Beinheben",
        primary: [.hipAbductors], secondary: [.glutes, .obliques],
        equipment: "Matte, Miniband (optional)",
        cue: "Bein leicht nach hinten führen, Fußspitze zeigt nach vorn.",
        steps: [
            "Auf die Seite legen, unteres Bein leicht gebeugt, oberes Bein gestreckt in Verlängerung des Körpers.",
            "Das obere Bein langsam etwa 30–40° anheben, ohne das Becken nach hinten zu drehen.",
            "Oben kurz halten und langsam absenken. Danach Seite wechseln.",
        ],
        mistakes: ["Becken rollt nach hinten", "Bein wandert nach vorn", "Zu hoch heben"],
        benefit: "Gezieltes Training der seitlichen Hüftmuskeln. Läufer mit Läuferknie (ITBS) hatten in einer Studie schwächere Hüftabduktoren; nach 6 Wochen Kräftigung waren fast alle wieder schmerzfrei.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 150, y: 165), torso: -83, nearLeg: .angles(78, 78), farLeg: .angles(90, 90),
                     nearArm: .angles(76, 82), farArm: .angles(-88, -88)),
                Pose(hip: CGPoint(x: 150, y: 165), torso: -83, nearLeg: .angles(112, 112), farLeg: .angles(90, 90),
                     nearArm: .angles(76, 82), farArm: .angles(-88, -88)),
            ],
            holds: [0.3, 0.5], moves: [1.0, 1.4], props: [.mat(x: 50, width: 200)], frontal: true))

    private static let plankFeet = (near: CGPoint(x: 62, y: 170), far: CGPoint(x: 64, y: 170))

    static let plank = StrengthExercise(
        id: "plank", name: "Unterarmstütz",
        primary: [.core], secondary: [.shoulders, .glutes, .quads],
        equipment: "Matte",
        cue: "Kopf bis Fersen in einer Linie, Bauch und Gesäß fest.",
        steps: [
            "Auf die Unterarme stützen, Ellbogen unter den Schultern.",
            "Beine strecken, auf die Zehen stellen und den Körper zu einer geraden Linie anspannen.",
            "Ruhig weiteratmen und die Spannung halten.",
        ],
        mistakes: ["Hüfte hängt durch", "Gesäß zu hoch", "Luft anhalten"],
        benefit: "Ein stabiler Rumpf hält das Becken beim Laufen ruhig und überträgt die Kraft der Beine.",
        measure: .seconds, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 154.3, y: 163.0), torso: 85.2, head: -6, nearLeg: .reach(CGPoint(x: 70.3, y: 170), bend: downward),
                     farLeg: .reach(CGPoint(x: 72.3, y: 170), bend: downward),
                     nearArm: .angles(0, 90), farArm: .angles(0, 90), nearFoot: 20, farFoot: 20),
                Pose(hip: CGPoint(x: 154.3, y: 161.6), torso: 85.0, head: -6, nearLeg: .reach(CGPoint(x: 70.3, y: 170), bend: downward),
                     farLeg: .reach(CGPoint(x: 72.3, y: 170), bend: downward),
                     nearArm: .angles(-1, 90), farArm: .angles(-1, 90), nearFoot: 20, farFoot: 20),
            ],
            holds: [1.2, 1.2], moves: [1.0, 1.0], props: [.mat(x: 40, width: 220)]))

    static let sidePlank = StrengthExercise(
        id: "sidePlank", name: "Seitstütz",
        primary: [.obliques], secondary: [.hipAbductors, .core, .shoulders],
        equipment: "Matte",
        cue: "Hüfte hoch, Körper bildet eine gerade Linie.",
        steps: [
            "Seitlich auf den Unterarm stützen, Ellbogen unter der Schulter, Beine gestreckt übereinander.",
            "Hüfte anheben, bis der Körper von Kopf bis Fuß gerade ist.",
            "Halten oder die Hüfte langsam absenken und wieder anheben. Danach Seite wechseln.",
        ],
        mistakes: ["Hüfte sinkt ab", "Oberkörper dreht nach vorn"],
        benefit: "Stärkt die seitliche Rumpf- und Hüftmuskulatur, die das Becken beim Laufen vom Abkippen abhält.",
        measure: .seconds, perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 156, y: 148), torso: 77.2, head: 4, nearLeg: .reach(CGPoint(x: 77, y: 181), bend: upward),
                     farLeg: .reach(CGPoint(x: 79, y: 172), bend: upward),
                     nearArm: .forearmSupport(0), farArm: .angles(180, 180)),
                Pose(hip: CGPoint(x: 156, y: 151), torso: 73.3, head: 6, nearLeg: .reach(CGPoint(x: 77, y: 181), bend: upward),
                     farLeg: .reach(CGPoint(x: 79, y: 172), bend: upward),
                     nearArm: .forearmSupport(0), farArm: .angles(178, 178)),
            ],
            holds: [1.4, 0.4], moves: [1.0, 1.0], props: [.mat(x: 40, width: 220)], frontal: true))

    static let deadBug = StrengthExercise(
        id: "deadBug", name: "Dead Bug",
        primary: [.core], secondary: [.hipFlexors, .shoulders],
        equipment: "Matte",
        cue: "Unterer Rücken bleibt am Boden, langsam im Wechsel strecken.",
        steps: [
            "Auf den Rücken legen, Arme senkrecht nach oben, Hüfte und Knie 90° gebeugt.",
            "Langsam einen Arm nach hinten und das gegenüberliegende Bein nach vorn strecken, ohne dass der Rücken abhebt.",
            "Zurück zur Mitte und Seite wechseln.",
        ],
        mistakes: ["Hohlkreuz", "Zu schnell", "Luft anhalten"],
        benefit: "Schult die Stabilität des Rumpfes gegen die Bewegung der Gliedmaßen – wie beim Laufen mit Armschwung und Beinarbeit.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 160, y: 174), torso: -90, nearLeg: .angles(180, 90), farLeg: .angles(178, 92),
                     nearArm: .angles(180, 180), farArm: .angles(176, 176), nearFoot: 180, farFoot: 180),
                Pose(hip: CGPoint(x: 160, y: 174), torso: -90, nearLeg: .angles(180, 90), farLeg: .angles(106, 106),
                     nearArm: .angles(-100, -100), farArm: .angles(176, 176), nearFoot: 180, farFoot: 196),
                Pose(hip: CGPoint(x: 160, y: 174), torso: -90, nearLeg: .angles(180, 90), farLeg: .angles(178, 92),
                     nearArm: .angles(180, 180), farArm: .angles(176, 176), nearFoot: 180, farFoot: 180),
                Pose(hip: CGPoint(x: 160, y: 174), torso: -90, nearLeg: .angles(106, 106), farLeg: .angles(178, 92),
                     nearArm: .angles(180, 180), farArm: .angles(-100, -100), nearFoot: 196, farFoot: 180),
            ],
            holds: [0.3, 0.5, 0.3, 0.5], moves: [1.2, 1.2, 1.2, 1.2], props: [.mat(x: 50, width: 200)]))

    static let birdDog = StrengthExercise(
        id: "birdDog", name: "Bird Dog",
        primary: [.core, .glutes], secondary: [.lowerBack, .shoulders, .hamstrings],
        equipment: "Matte",
        cue: "Gegengleich Arm und Bein strecken, Becken bleibt ruhig.",
        steps: [
            "In den Vierfüßlerstand gehen: Hände unter den Schultern, Knie unter der Hüfte.",
            "Einen Arm nach vorn und das gegenüberliegende Bein nach hinten strecken, bis beide waagrecht sind.",
            "Kurz halten, zurück und Seite wechseln.",
        ],
        mistakes: ["Becken dreht auf", "Hohlkreuz durch zu hohes Bein", "Schwung statt Kontrolle"],
        benefit: "Verbindet Gesäß- und Rückenmuskeln über Kreuz – das Muster der Laufbewegung – und stabilisiert die Lendenwirbelsäule.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 120, y: 128), torso: 90, head: -14, nearLeg: .reach(CGPoint(x: 79, y: 180), bend: downward), farLeg: .reach(CGPoint(x: 81, y: 180), bend: downward),
                     nearArm: .reach(CGPoint(x: 172, y: 181), bend: backward), farArm: .reach(CGPoint(x: 175, y: 181), bend: backward), nearFoot: -80, farFoot: -80),
                Pose(hip: CGPoint(x: 120, y: 128), torso: 90, head: -14, nearLeg: .reach(CGPoint(x: 79, y: 180), bend: downward), farLeg: .angles(-90, -90),
                     nearArm: .angles(90, 90), farArm: .reach(CGPoint(x: 175, y: 181), bend: backward), nearFoot: -80, farFoot: 0),
                Pose(hip: CGPoint(x: 120, y: 128), torso: 90, head: -14, nearLeg: .reach(CGPoint(x: 79, y: 180), bend: downward), farLeg: .reach(CGPoint(x: 81, y: 180), bend: downward),
                     nearArm: .reach(CGPoint(x: 172, y: 181), bend: backward), farArm: .reach(CGPoint(x: 175, y: 181), bend: backward), nearFoot: -80, farFoot: -80),
                Pose(hip: CGPoint(x: 120, y: 128), torso: 90, head: -14, nearLeg: .angles(-90, -90), farLeg: .reach(CGPoint(x: 81, y: 180), bend: downward),
                     nearArm: .reach(CGPoint(x: 172, y: 181), bend: backward), farArm: .angles(90, 90), nearFoot: 0, farFoot: -80),
            ],
            holds: [0.3, 0.6, 0.3, 0.6], moves: [1.1, 1.1, 1.1, 1.1], props: [.mat(x: 50, width: 200)]))

    private static let pogoToe = CGPoint(x: 160, y: 186)

    static let pogoJumps = StrengthExercise(
        id: "pogoJumps", name: "Pogo Jumps",
        primary: [.calves], secondary: [.quads, .core],
        equipment: "Keine",
        cue: "Kleine, schnelle Sprünge aus den Fußgelenken, Knie fast gestreckt.",
        steps: [
            "Hüftbreit stehen, Knie locker, Gewicht auf den Fußballen.",
            "Schnell und federnd aus den Fußgelenken springen; die Fersen berühren den Boden nicht.",
            "So kurz wie möglich am Boden bleiben, wie ein Flummi.",
        ],
        mistakes: ["Tiefe Kniebeugung", "Laute, schwere Landung", "Fersen setzen auf"],
        benefit: "Trainiert die Federwirkung von Wade und Achillessehne, die beim Laufen Energie speichert und zurückgibt.",
        usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: shifted(ankle(toe: pogoToe, foot: 64), -4, -82), torso: 4,
                     nearLeg: .reach(ankle(toe: pogoToe, foot: 64), bend: forward), farLeg: .reach(ankle(toe: shifted(pogoToe, 3, 0), foot: 64), bend: forward),
                     nearArm: .angles(14, 60), farArm: .angles(10, 56), nearFoot: 64, farFoot: 64),
                Pose(hip: shifted(ankle(toe: pogoToe, foot: 50), -4, -96), torso: 4,
                     nearLeg: .reach(shifted(ankle(toe: pogoToe, foot: 50), 0, -14), bend: forward),
                     farLeg: .reach(shifted(ankle(toe: shifted(pogoToe, 3, 0), foot: 50), 0, -14), bend: forward),
                     nearArm: .angles(10, 52), farArm: .angles(6, 48), nearFoot: 50, farFoot: 50),
            ],
            holds: [0.03, 0.03], moves: [0.2, 0.2]))

    static let boxJump = StrengthExercise(
        id: "boxJump", name: "Box Jump",
        primary: [.quads, .glutes, .calves], secondary: [.hamstrings, .core, .shoulders],
        equipment: "Stabile Box (30–60 cm)",
        cue: "Explosiv abspringen, leise und weich landen.",
        steps: [
            "Etwa eine Fußlänge vor der Box stehen.",
            "Mit Armschwung kurz in die Knie gehen und explosiv auf die Box springen.",
            "Weich in einer halben Kniebeuge landen, aufrichten und wieder hinuntersteigen (nicht springen).",
        ],
        mistakes: ["Box zu hoch", "Harte Landung mit gestreckten Knien", "Rückwärts herunterspringen"],
        benefit: "Steigert die explosive Kraft der Beine. Explosiv- und Sprungtraining verbesserte in Studien Laufökonomie sowie 3- und 5-km-Zeiten.",
        usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                Pose(hip: CGPoint(x: 120, y: 97), torso: 3, nearLeg: .reach(flat(122), bend: forward), farLeg: .reach(flat(125), bend: forward),
                     nearArm: .angles(5, 10), farArm: .angles(3, 8)),
                Pose(hip: CGPoint(x: 104, y: 127), torso: 40, nearLeg: .reach(flat(122), bend: forward), farLeg: .reach(flat(125), bend: forward),
                     nearArm: .angles(-55, -40), farArm: .angles(-58, -44)),
                Pose(hip: CGPoint(x: 165, y: 60), torso: 25, nearLeg: .angles(82, -22), farLeg: .angles(79, -25),
                     nearArm: .angles(150, 168), farArm: .angles(146, 165), nearFoot: 100, farFoot: 100),
                Pose(hip: CGPoint(x: 197, y: 96), torso: 35, nearLeg: .reach(CGPoint(x: 214, y: 130), bend: forward), farLeg: .reach(CGPoint(x: 217, y: 130), bend: forward),
                     nearArm: .angles(70, 90), farArm: .angles(66, 86)),
                Pose(hip: CGPoint(x: 208, y: 48), torso: 3, nearLeg: .reach(CGPoint(x: 214, y: 130), bend: forward), farLeg: .reach(CGPoint(x: 217, y: 130), bend: forward),
                     nearArm: .angles(5, 10), farArm: .angles(3, 8)),
                // Rückwärts absteigen: ein Fuß angehoben über die Kante, vor der Box auf den Boden, dann der zweite
                Pose(hip: CGPoint(x: 182, y: 80), torso: 8, nearLeg: .reach(CGPoint(x: 214, y: 130), bend: forward), farLeg: .reach(CGPoint(x: 176, y: 121), bend: forward),
                     nearArm: .angles(10, 16), farArm: .angles(-4, 4), farFoot: 70),
                Pose(hip: CGPoint(x: 160, y: 100), torso: 8, nearLeg: .reach(CGPoint(x: 214, y: 130), bend: forward), farLeg: .reach(flat(155), bend: forward),
                     nearArm: .angles(10, 16), farArm: .angles(-4, 4)),
                Pose(hip: CGPoint(x: 152, y: 97), torso: 4, nearLeg: .reach(CGPoint(x: 178, y: 124), bend: forward), farLeg: .reach(flat(155), bend: forward),
                     nearArm: .angles(2, 8), farArm: .angles(4, 10)),
            ],
            holds: [0.4, 0.08, 0, 0.12, 0.5, 0, 0.05, 0], moves: [0.5, 0.22, 0.22, 0.5, 0.4, 0.35, 0.45, 0.7],
            props: [.box(x: 188, width: 65, height: 50)]))

    static let jumpLunge = StrengthExercise(
        id: "jumpLunge", name: "Sprung-Ausfallschritt",
        primary: [.quads, .glutes], secondary: [.calves, .hamstrings, .hipFlexors, .core],
        equipment: "Keine",
        cue: "Im Sprung die Beine wechseln, weich landen.",
        steps: [
            "In einer Ausfallschrittstellung beginnen, hinteres Knie knapp über dem Boden.",
            "Explosiv nach oben springen und in der Luft die Beine wechseln.",
            "Weich im Ausfallschritt mit dem anderen Bein vorn landen und direkt weiterspringen.",
        ],
        mistakes: ["Vorderes Knie knickt nach innen", "Harte Landung", "Oberkörper fällt nach vorn"],
        benefit: "Explosive, einbeinige Kraft mit schnellem Beinwechsel – ähnlich dem Wechsel von Stütz- und Schwungbein beim Laufen.",
        perSide: true, usesWeight: false,
        animation: ExerciseAnimation(
            frames: [
                jumpLungePose(nearFront: true, hipY: 138),
                Pose(hip: CGPoint(x: 138, y: 80), torso: 3, nearLeg: .angles(2, -55), farLeg: .angles(8, -45),
                     nearArm: .angles(0, 15), farArm: .angles(0, 15), nearFoot: 75, farFoot: 82),
                jumpLungePose(nearFront: false, hipY: 124),
                jumpLungePose(nearFront: false, hipY: 138),
                Pose(hip: CGPoint(x: 138, y: 80), torso: 3, nearLeg: .angles(8, -45), farLeg: .angles(2, -55),
                     nearArm: .angles(0, 15), farArm: .angles(0, 15), nearFoot: 82, farFoot: 75),
                jumpLungePose(nearFront: true, hipY: 124),
            ],
            holds: [0.15, 0, 0, 0.15, 0, 0], moves: [0.3, 0.22, 0.12, 0.3, 0.22, 0.12]))

    /// Ausfallschritt beim Sprung-Ausfallschritt; mit höherer Hüfte die Haltung beim Aufsetzen
    private static func jumpLungePose(nearFront: Bool, hipY: Double) -> Pose {
        let front = Limb.reach(flat(168), bend: forward)
        let rear = Limb.reach(ankle(toe: CGPoint(x: 100, y: 186), foot: 55), bend: downward)
        let forwardArm = Limb.angles(30, 60), backArm = Limb.angles(-25, -10)
        return Pose(hip: CGPoint(x: 138, y: hipY), torso: 5, nearLeg: nearFront ? front : rear, farLeg: nearFront ? rear : front,
                    nearArm: nearFront ? backArm : forwardArm, farArm: nearFront ? forwardArm : backArm,
                    nearFoot: nearFront ? 90 : 55, farFoot: nearFront ? 55 : 90)
    }
}
