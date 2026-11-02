import Foundation

/// Studie, auf die sich ein Programm stützt.
struct StrengthStudy: Hashable {
    let citation: String
    let finding: String
}

/// Übung innerhalb eines Programms mit Vorgaben für Umfang und Intensität.
struct ProgramItem: Hashable {
    let exerciseID: String
    let sets: Int
    /// Wiederholungen bzw. Sekunden pro Satz (Vorschlag beim Eintragen)
    let target: Int
    let intensity: String
    let rest: String

    var exercise: StrengthExercise? { StrengthExercise.with(id: exerciseID) }

    /// z. B. „4 × 4“, „3 × 8 je Seite“, „3 × 30 s“
    var prescription: String {
        guard let exercise else { return "" }
        let amount = exercise.measure == .seconds ? "\(target) s" : "\(target)"
        return "\(sets) × \(amount)" + (exercise.perSide ? " je Seite" : "")
    }
}

/// Krafttrainingsprogramm für Läufer.
struct StrengthProgram: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let level: String
    let frequency: String
    let duration: String
    let equipment: String
    let description: String
    let why: String
    let tips: [String]
    let studies: [StrengthStudy]
    let items: [ProgramItem]

    static func with(id: String) -> StrengthProgram? { all.first { $0.id == id } }

    static func == (a: StrengthProgram, b: StrengthProgram) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Programme

extension StrengthProgram {
    static let all: [StrengthProgram] = [basics, maxStrength, plyometrics, prevention, core, hipKnee]

    static let basics = StrengthProgram(
        id: "basics", name: "Kraft-Basis für Läufer", subtitle: "Der Einstieg ins Krafttraining",
        icon: "figure.strengthtraining.functional", level: "Einsteiger",
        frequency: "2× pro Woche", duration: "35–45 min", equipment: "Kurzhanteln oder Kettlebell, Matte",
        description: "Ein Ganzkörperprogramm mit den wichtigsten Grundübungen für Läufer: Kniebeuge, Hüftbeugen, Ausfallschritt, Gesäß, Waden und Rumpf. Moderate Gewichte, saubere Technik.",
        why: "Krafttraining senkt das Verletzungsrisiko im Sport deutlich und verbessert langfristig die Laufökonomie. Als Einsteiger lernst du hier die Bewegungen, bevor das Gewicht steigt.",
        tips: [
            "Wähle das Gewicht so, dass nach dem Satz noch 2–3 Wiederholungen möglich wären.",
            "Steigere das Gewicht, wenn alle Sätze sauber gelingen.",
            "Krafttraining am besten an Tagen mit lockeren Läufen oder nach dem Lauf – nicht vor Intervallen.",
        ],
        studies: [
            StrengthStudy(citation: "Lauersen, Bertelsen & Andersen (2014), Br J Sports Med",
                          finding: "Meta-Analyse aus 25 Studien: Krafttraining senkte Sportverletzungen auf weniger als ein Drittel."),
            StrengthStudy(citation: "Blagrove, Howatson & Hayes (2018), Sports Medicine",
                          finding: "Übersichtsarbeit: Krafttraining verbessert Laufökonomie und Leistung von Mittel- und Langstreckenläufern."),
        ],
        items: [
            ProgramItem(exerciseID: "gobletSquat", sets: 3, target: 10, intensity: "mittel (2–3 Wdh. Reserve)", rest: "90 s"),
            ProgramItem(exerciseID: "romanianDeadlift", sets: 3, target: 10, intensity: "mittel", rest: "90 s"),
            ProgramItem(exerciseID: "reverseLunge", sets: 3, target: 8, intensity: "mittel", rest: "60 s"),
            ProgramItem(exerciseID: "gluteBridge", sets: 3, target: 12, intensity: "Körpergewicht", rest: "45 s"),
            ProgramItem(exerciseID: "calfRaise", sets: 3, target: 12, intensity: "Körpergewicht oder leicht", rest: "45 s"),
            ProgramItem(exerciseID: "plank", sets: 3, target: 40, intensity: "Körpergewicht", rest: "45 s"),
        ])

    static let maxStrength = StrengthProgram(
        id: "maxStrength", name: "Maximalkraft & Laufökonomie", subtitle: "Schwer und wenige Wiederholungen",
        icon: "dumbbell.fill", level: "Fortgeschritten",
        frequency: "2× pro Woche", duration: "45–55 min", equipment: "Langhantel mit Rack, Kurzhanteln, Bank, Box",
        description: "Schwere Grundübungen mit wenigen Wiederholungen und explosiver Hubphase, wie sie in Studien mit gut trainierten Läufern eingesetzt wurden.",
        why: "Schwere Sätze (etwa 85–90 % der Maximalkraft) verbessern die Kraft der Nerven-Muskel-Ansteuerung, ohne nennenswert Muskelmasse aufzubauen. Dadurch kostet jeder Schritt weniger Energie.",
        tips: [
            "Erst nach einigen Wochen Kraft-Basis beginnen; vor dem schweren Satz 2–3 Aufwärmsätze.",
            "Die Bewegung nach oben so schnell wie möglich ausführen, die Abwärtsbewegung kontrolliert.",
            "Mindestens 48 Stunden Abstand zu harten Laufeinheiten der Beine.",
        ],
        studies: [
            StrengthStudy(citation: "Støren et al. (2008), Med Sci Sports Exerc",
                          finding: "8 Wochen halbtiefe Kniebeugen (4 × 4, 3× pro Woche) verbesserten bei gut trainierten Läufern die Laufökonomie um 5 % und die Zeit bis zur Erschöpfung um 21 %."),
            StrengthStudy(citation: "Balsalobre-Fernández, Santos-Concejero & Grivas (2016), J Strength Cond Res",
                          finding: "Meta-Analyse: Krafttraining verbessert die Laufökonomie hochtrainierter Läufer deutlich."),
            StrengthStudy(citation: "Beattie et al. (2017), J Strength Cond Res",
                          finding: "40 Wochen Krafttraining verbesserten bei Langstreckenläufern Maximalkraft, Reaktivkraft und Laufökonomie, ohne das Körpergewicht zu erhöhen."),
        ],
        items: [
            ProgramItem(exerciseID: "backSquat", sets: 4, target: 4, intensity: "schwer, ca. 85–90 % (1 Wdh. Reserve)", rest: "2–3 min"),
            ProgramItem(exerciseID: "romanianDeadlift", sets: 3, target: 6, intensity: "schwer", rest: "2 min"),
            ProgramItem(exerciseID: "bulgarianSplitSquat", sets: 3, target: 6, intensity: "schwer", rest: "90 s"),
            ProgramItem(exerciseID: "soleusRaise", sets: 3, target: 8, intensity: "schwer", rest: "90 s"),
            ProgramItem(exerciseID: "stepUp", sets: 3, target: 6, intensity: "mittel bis schwer", rest: "90 s"),
        ])

    static let plyometrics = StrengthProgram(
        id: "plyometrics", name: "Plyometrie & Reaktivkraft", subtitle: "Sprungkraft für einen federnden Laufstil",
        icon: "figure.jumprope", level: "Fortgeschritten",
        frequency: "1–2× pro Woche", duration: "20–30 min", equipment: "Stabile Box",
        description: "Kurze, explosive Sprünge mit wenig Bodenkontaktzeit. Sie trainieren die Federwirkung von Muskeln und Sehnen, die beim Laufen Energie speichern und zurückgeben.",
        why: "Explosiv- und Sprungtraining verbesserte in mehreren Studien die Laufökonomie und die Wettkampfzeit von Läufern – teils schon nach 6–9 Wochen.",
        tips: [
            "Nur ausgeruht trainieren; Qualität vor Menge. Aufhören, wenn die Sprünge langsamer werden.",
            "Weich und leise landen, kurze Bodenkontakte.",
            "Gut als Ergänzung nach einem lockeren Lauf oder vor dem Krafttraining.",
        ],
        studies: [
            StrengthStudy(citation: "Paavolainen et al. (1999), J Appl Physiol",
                          finding: "9 Wochen Explosivkrafttraining verbesserten bei Ausdauerathleten Laufökonomie und 5-km-Zeit."),
            StrengthStudy(citation: "Spurrs, Murphy & Watsford (2003), Eur J Appl Physiol",
                          finding: "6 Wochen Plyometrie verbesserten Laufökonomie und 3-km-Zeit bei Läufern."),
            StrengthStudy(citation: "Saunders et al. (2006), J Strength Cond Res",
                          finding: "9 Wochen Plyometrie verbesserten die Laufökonomie hochtrainierter Mittel- und Langstreckenläufer."),
        ],
        items: [
            ProgramItem(exerciseID: "pogoJumps", sets: 3, target: 20, intensity: "schnell, federnd", rest: "60 s"),
            ProgramItem(exerciseID: "boxJump", sets: 4, target: 5, intensity: "maximal explosiv", rest: "90 s"),
            ProgramItem(exerciseID: "jumpLunge", sets: 3, target: 6, intensity: "explosiv", rest: "90 s"),
            ProgramItem(exerciseID: "singleLegSquat", sets: 3, target: 6, intensity: "kontrolliert", rest: "60 s"),
        ])

    static let prevention = StrengthProgram(
        id: "prevention", name: "Verletzungsprävention", subtitle: "Achillessehne, Oberschenkel, Leiste",
        icon: "cross.case.fill", level: "Alle Stufen",
        frequency: "2× pro Woche", duration: "25–30 min", equipment: "Matte, Bank, Stufe",
        description: "Übungen, die in Studien typische Läuferverletzungen verringert haben: Zerrungen der Oberschenkelrückseite, Leistenprobleme und Achillessehnenbeschwerden.",
        why: "Viele Laufverletzungen entstehen, wenn Muskeln und Sehnen der Belastung nicht gewachsen sind. Bremsendes (exzentrisches) Training macht sie belastbarer.",
        tips: [
            "Nordic Curls am Anfang mit wenigen Wiederholungen beginnen – der Muskelkater ist in den ersten Wochen stark.",
            "Bei bestehenden Beschwerden die Übungen mit Ärztin, Arzt oder Physiotherapie abstimmen.",
        ],
        studies: [
            StrengthStudy(citation: "van der Horst et al. (2015), Am J Sports Med",
                          finding: "Nordic Hamstring Curls verringerten bei Amateurfußballern die Zahl der Verletzungen der Oberschenkelrückseite deutlich."),
            StrengthStudy(citation: "Harøy et al. (2019), Br J Sports Med",
                          finding: "Das Adduktorenprogramm mit Copenhagen Plank senkte Leistenprobleme um 41 %."),
            StrengthStudy(citation: "Alfredson et al. (1998), Am J Sports Med",
                          finding: "12 Wochen schweres exzentrisches Wadentraining führten bei chronischen Achillessehnenbeschwerden zur Rückkehr zum Laufen."),
            StrengthStudy(citation: "Lauersen, Bertelsen & Andersen (2014), Br J Sports Med",
                          finding: "Krafttraining senkte Sportverletzungen auf weniger als ein Drittel."),
        ],
        items: [
            ProgramItem(exerciseID: "nordicCurl", sets: 3, target: 5, intensity: "so langsam wie möglich", rest: "90 s"),
            ProgramItem(exerciseID: "copenhagenPlank", sets: 3, target: 20, intensity: "Knie oder Knöchel aufgelegt", rest: "60 s"),
            ProgramItem(exerciseID: "heelDrop", sets: 3, target: 15, intensity: "langsam, 3 s absenken", rest: "60 s"),
            ProgramItem(exerciseID: "sideLyingAbduction", sets: 3, target: 15, intensity: "kontrolliert", rest: "45 s"),
            ProgramItem(exerciseID: "singleLegRDL", sets: 3, target: 8, intensity: "leicht bis mittel", rest: "60 s"),
        ])

    static let core = StrengthProgram(
        id: "core", name: "Rumpf & Stabilität", subtitle: "Ein ruhiges Becken bei jedem Schritt",
        icon: "figure.core.training", level: "Einsteiger",
        frequency: "2–3× pro Woche", duration: "15–20 min", equipment: "Matte",
        description: "Kurzes Programm ohne Geräte für Bauch, Rücken und Hüfte – lässt sich gut direkt nach dem Laufen anhängen.",
        why: "Ein stabiler Rumpf hält Becken und Oberkörper beim Laufen ruhig. Die Studienlage zur direkten Leistungssteigerung ist schwächer als bei Krafttraining der Beine, eine Studie fand aber eine schnellere 5-km-Zeit.",
        tips: [
            "Langsam und kontrolliert statt schnell und viele Wiederholungen.",
            "Ruhig weiteratmen, nicht pressen.",
        ],
        studies: [
            StrengthStudy(citation: "Sato & Mokha (2009), J Strength Cond Res",
                          finding: "6 Wochen Rumpfkrafttraining verbesserten bei Freizeitläufern die 5000-m-Zeit."),
        ],
        items: [
            ProgramItem(exerciseID: "plank", sets: 3, target: 45, intensity: "Körpergewicht", rest: "30 s"),
            ProgramItem(exerciseID: "sidePlank", sets: 3, target: 30, intensity: "Körpergewicht", rest: "30 s"),
            ProgramItem(exerciseID: "deadBug", sets: 3, target: 8, intensity: "langsam", rest: "30 s"),
            ProgramItem(exerciseID: "birdDog", sets: 3, target: 8, intensity: "langsam", rest: "30 s"),
            ProgramItem(exerciseID: "singleLegBridge", sets: 3, target: 10, intensity: "Körpergewicht", rest: "30 s"),
        ])

    static let hipKnee = StrengthProgram(
        id: "hipKnee", name: "Hüfte & Knie", subtitle: "Gegen Läuferknie und Knieschmerzen",
        icon: "figure.run", level: "Alle Stufen",
        frequency: "2–3× pro Woche", duration: "25–35 min", equipment: "Matte, Box, Kurzhantel",
        description: "Stärkt die seitlichen Hüftmuskeln und schult die Kontrolle des Knies auf einem Bein – die häufigsten Schwachstellen bei Läuferknie (ITBS) und Schmerzen hinter der Kniescheibe.",
        why: "Schwache Hüftabduktoren lassen das Knie beim Landen nach innen wandern. Gezieltes Hüfttraining hat in Studien Schmerzen bei Läufern deutlich verringert.",
        tips: [
            "Achte bei allen einbeinigen Übungen darauf, dass das Knie über dem Fuß bleibt.",
            "Bei Schmerzen die Übung abbrechen und Ursache abklären lassen.",
        ],
        studies: [
            StrengthStudy(citation: "Fredericson et al. (2000), Clin J Sport Med",
                          finding: "Läufer mit Läuferknie hatten schwächere Hüftabduktoren; nach 6 Wochen Hüfttraining waren 22 von 24 wieder schmerzfrei beim Laufen."),
            StrengthStudy(citation: "Ferber et al. (2015), J Athl Train",
                          finding: "Hüft- und Rumpftraining verringerte Schmerzen hinter der Kniescheibe genauso gut wie Knietraining und wirkte schneller."),
        ],
        items: [
            ProgramItem(exerciseID: "sideLyingAbduction", sets: 3, target: 15, intensity: "kontrolliert", rest: "45 s"),
            ProgramItem(exerciseID: "singleLegBridge", sets: 3, target: 12, intensity: "Körpergewicht", rest: "45 s"),
            ProgramItem(exerciseID: "singleLegSquat", sets: 3, target: 8, intensity: "kontrolliert", rest: "60 s"),
            ProgramItem(exerciseID: "stepUp", sets: 3, target: 10, intensity: "leicht bis mittel", rest: "60 s"),
            ProgramItem(exerciseID: "sidePlank", sets: 3, target: 30, intensity: "Körpergewicht", rest: "30 s"),
            ProgramItem(exerciseID: "singleLegRDL", sets: 3, target: 8, intensity: "leicht bis mittel", rest: "60 s"),
        ])
}
