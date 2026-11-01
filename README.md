# LaufApp 🏃

Eine kostenlose, private Lauf-App für iOS (SwiftUI). Kein Konto, kein Abo und keine Cloud: Alle Daten bleiben auf deinem iPhone.

## Funktionen

**Aufzeichnen**
- GPS-Aufzeichnung mit Live-Karte, Zeit, Distanz, aktueller und durchschnittlicher Pace
- Pausieren und Fortsetzen (Pausen zählen nicht zur Bewegungszeit)
- Läuft im Hintergrund weiter, auch bei gesperrtem Bildschirm
- Sprachansagen auf Deutsch nach jedem Kilometer (Musik wird kurz leiser)
- Filter gegen GPS-Sprünge und -Zittern

**Aktivitäten**
- Feed mit Karten-Vorschau und Wochenübersicht
- Detailansicht: Karte, Kilometer-Splits, Pace-Diagramm, Höhenprofil, Höhenmeter
- Bestleistungen pro Lauf (400 m, 1 km, Meile, 5 km, 10 km, HM, Marathon)
- Titel, Notizen und gefühlte Anstrengung (1–10)

**Training**
- Trainingspläne für 5 km, 10 km, Halbmarathon und Marathon
- Paces nach dem **VDOT-System von Jack Daniels**: locker (E), Marathon (M), Schwelle (T), Intervall (I), Wiederholung (R)
- Phasen: Grundlage → Aufbau → wettkampfspezifisch → Tapering
- Alle Trainingsarten im Wechsel: Wiederholungen (R) für Schnelligkeit, Intervalle (I) für VO2max, Schwelle (T) und Wettkampftempo – gewichtet nach Zieldistanz und Phase
- Umfang steigt höchstens ca. 10 % pro Woche, jede 4. Woche ist eine Entlastungswoche
- Workouts werden automatisch abgehakt, wenn du am selben Tag läufst
- Bei der Planerstellung wählst du Trainingstage, den Tag für den langen Lauf und deinen gewünschten Wochenumfang; reicht er für dein Ziel nicht, warnt die App
- Strukturierte Workouts (Einlaufen, Intervalle, Pausen, Auslaufen) mit Sprachführung: Ansage jedes Abschnitts, „Noch 200 Meter“, Hinweise bei zu schneller oder zu langsamer Pace
- Einheiten verschieben oder überspringen, Plan jederzeit anpassen (Tage, Umfang, Form), ohne Vergangenes zu verlieren
- Erkennt die App aus deinen Läufen eine bessere Form, schlägt sie neue Paces vor und zeigt eine aktualisierte Prognose

**Du (Profil)**
- Wochen-Diagramm der letzten 12 Wochen
- Summen für Woche, Monat, Jahr und gesamt
- Persönliche Bestleistungen

## Erste Schritte (für Einsteiger)

1. **Projekt öffnen:** Doppelklick auf `LaufApp.xcodeproj` (Xcode 16 oder neuer).
2. **Signieren einrichten:** Links oben in der Dateiliste auf das blaue Projekt **LaufApp** klicken, dann Target **LaufApp**, dann Tab **Signing & Capabilities**.
   - Bei **Team** deinen Apple-Developer-Account auswählen.
   - Meldet Xcode, dass der **Bundle Identifier** vergeben ist, ändere ihn in etwas Eindeutiges, z. B. `de.deinname.LaufApp`.
3. **Im Simulator testen:** Oben in der Leiste ein iPhone-Modell wählen und auf ▶︎ klicken (oder ⌘R).
   - GPS simulieren: im Simulator-Menü **Features → Location → City Run**.
   - Testdaten: Tab **Du** → ganz unten **Demo-Lauf hinzufügen** (nur in Debug-Builds).
4. **Auf dem iPhone installieren:** iPhone per Kabel anschließen und oben als Ziel auswählen, dann ▶︎.
   - Beim ersten Mal auf dem iPhone: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** aktivieren.
   - Beim Standort-Dialog **„Beim Verwenden der App erlauben“** wählen.

## Projektstruktur

```
LaufApp/
├── App/            App-Start und Tab-Leiste
├── Models/         Datenmodell eines Laufs (SwiftData) und Auswertung (Splits, Bestzeiten)
├── Services/       GPS-Recorder mit Sprachansagen, Demo-Daten
├── Training/       VDOT-Berechnung, Plangenerator, Plan-Datenmodell
├── Utilities/      Formatierung, Geo-Berechnungen
└── Views/          Oberflächen: Feed, Aufnehmen, Training, Profil
```

## Technik

- iOS 17+, SwiftUI, SwiftData, MapKit, Swift Charts, CoreLocation, AVFoundation
- Keine externen Abhängigkeiten

## Ideen für später

- Apple Health / Apple Watch (Herzfrequenz, Workouts in Health speichern)
- Live Activity auf dem Sperrbildschirm
- Auto-Pause
- Routenplanung und Segmente
- GPX-Import und -Export
