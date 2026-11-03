# LaufApp 🏃

Eine kostenlose, private Lauf-App für iOS (SwiftUI). Kein Konto, kein Abo und keine Cloud: Alle Daten bleiben auf deinem iPhone.

## Funktionen

**Aufzeichnen**
- GPS-Aufzeichnung mit Live-Karte, Zeit, Distanz, aktueller und durchschnittlicher Pace
- Pausieren und Fortsetzen (Pausen zählen nicht zur Bewegungszeit)
- Läuft im Hintergrund weiter, auch bei gesperrtem Bildschirm
- Sprachansagen auf Deutsch nach jedem Kilometer (Musik wird kurz leiser)
- Filter gegen GPS-Sprünge und -Zittern

**Routenplanung**
- Strecke auf der Karte planen: Wegpunkte antippen, die Route folgt automatisch Fußwegen (Apple Karten), wahlweise Luftlinie
- Rundkurs mit einem Tipp, Rückgängig, Umkehren; Distanz und geschätzte Dauer (aus deiner lockeren Pace)
- Routen speichern, bearbeiten und vor dem Lauf auswählen
- Optional „Am Wasser entlang“: Uferrunden an Flüssen (ein Ufer hin, anderes zurück) und Runden zu Seen; Wegpunkte im Wasser werden automatisch ans Ufer verschoben
- Höhenmeter und Höhenprofil jeder Route (Höhendaten: Open-Meteo / Copernicus DEM, bei Ausfall Valhalla der FOSSGIS oder OpenTopoData); beim Vorschlagen optional „Höhenmeter meiden“ für möglichst flache Runden
- Rundkurs vorschlagen: Wunschdistanz wählen, die App erzeugt Runden ab deinem Standort, bevorzugt durch Parks, Wälder und Grünflächen (Daten: © OpenStreetMap-Mitwirkende, ersatzweise Apple Karten)
- Beim Laufen: Route auf der Karte, „Noch x km bis zum Ziel“, Warnung bei Abweichung (Anzeige und Sprachansage)
- Gelaufene Strecken als Route speichern: in der Laufansicht über „⋯ › Als Route speichern“ oder in der Routenliste über „+ › Aus gelaufener Strecke“

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
- Export in die Kalender-App: eigener Kalender „LaufApp Training“, ganztägig oder mit Uhrzeit und Erinnerung; wird bei Änderungen am Plan automatisch aktualisiert
- Erkennt die App aus deinen Läufen eine bessere Form, schlägt sie neue Paces vor und zeigt eine aktualisierte Prognose

**Krafttraining für Läufer** (Trainingstab → „Krafttraining“)
- Sechs Programme auf Basis von Studien mit Läufern und Sportlern: Kraft-Basis, Maximalkraft & Laufökonomie, Plyometrie, Verletzungsprävention, Rumpf & Stabilität, Hüfte & Knie – jeweils mit Vorgaben zu Sätzen, Wiederholungen, Intensität und Pausen sowie der Studienlage
- 23 Übungen mit animierter 3D-Figur (Mensch mit Gesicht, Geräte wie Hanteln, Bank und Box), auf der die beanspruchten Muskeln rot hervorgehoben sind (Haupt- und unterstützende Muskeln), dazu Ausführung, häufige Fehler und der Nutzen fürs Laufen
- Tagebuch: Sätze mit Wiederholungen, Gewicht bzw. Haltezeit und Wiederholungen in Reserve eintragen, vorbelegt mit den Werten der letzten Einheit; Übungen frei hinzufügen oder entfernen
- Fortschritt je Übung als Diagramm (geschätztes 1RM, Gewicht, Volumen bzw. Wiederholungen oder Zeit)

**Apple Health**
- Lauftrainings aus Apple Health werden automatisch übernommen (Apple Watch, Garmin Connect, Nike Run Club …): Strecke, Herzfrequenz, Schrittfrequenz, Splits, Höhenmeter und Pausen
- Läufe, die schon von Strava importiert oder mit LaufApp aufgezeichnet wurden, werden nicht doppelt angelegt; liegt ein Lauf in beiden Quellen, wird er verknüpft
- Einrichtung im Profil unter „Apple Health“

**Live-Aktivität (Sperrbildschirm und Dynamic Island)**
- Während eines Laufs: Zeit, Distanz und Pace auf dem Sperrbildschirm und in der Dynamic Island, „Pausiert“ in der Pause
- Beim Folgen einer Route: die nächste Abzweigung mit Pfeil und Entfernung („In 120 m links abbiegen“), die Reststrecke und ein Hinweis, wenn du von der Route abkommst
- Abzweigungen werden zusätzlich etwa 50 m vorher angesagt
- Bei geführten Workouts steht der aktuelle Abschnitt in der Anzeige; im Profil abschaltbar

**Läufe nachtragen**
- Über „+“ auf der Startseite einen Lauf ohne Aufzeichnung eintragen: Datum, Distanz, Zeit, optional eine gespeicherte Route (mit Karte und Höhenprofil), Höhenmeter, Herzfrequenz, Anstrengung und Notizen
- Wird auf Wunsch der Einheit des Trainingsplans an diesem Tag zugeordnet; Distanz und Zeit lassen sich später bearbeiten

**Herkunft im Feed**
- Jede Aktivität zeigt, woher sie stammt: LaufApp, Manuell, Strava oder Apple Health

**Garmin & Strava**
- Läufe deiner Garmin-Uhr automatisch übernehmen: Garmin Connect → Strava → LaufApp
- Herzfrequenz-Verlauf mit Zeit in den 5 Herzfrequenzzonen, Schrittfrequenz-Verlauf, Route, Splits und Höhe
- Einrichtung mit Schritt-für-Schritt-Anleitung im Profil unter „Strava & Garmin“ (eigene, kostenlose Strava-API-Anwendung; das Client-Secret liegt nur im Schlüsselbund)
- Bereits mit der App aufgezeichnete Läufe werden nicht doppelt importiert
- Fotos und Videos deiner Strava-Posts werden mit importiert: Galerie mit Vollbildansicht in der Laufansicht, Vorschaubild im Feed. Videos spielt die App ab, wenn Strava die Datei herausgibt, sonst öffnet sie sie in Strava
- Kudos und Kommentare deiner Strava-Posts: Anzahl im Feed, in der Laufansicht die Namen der Kudos-Geber und alle Kommentare. Läufe der letzten 7 Tage werden beim Öffnen der App aktualisiert, sonst über „Von Strava aktualisieren“ (nur lesen; antworten geht über den Link zu Strava)

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
├── Models/         Datenmodelle (SwiftData): Läufe, Routen, Krafttraining-Tagebuch, Fotos, Kudos
├── Services/       GPS-Aufzeichnung mit Sprachansagen, Strava- und Apple-Health-Import,
│                   Routenplanung und Rundkurs-Vorschläge, Höhendaten, Live-Aktivität
├── Strength/       Krafttraining: Programme, Übungen, 3D-Figur (SceneKit)
├── Training/       VDOT-Berechnung, Plangenerator, Plan-Datenmodell
├── Utilities/      Formatierung, Geo-Berechnungen, Schlüsselbund
├── Resources/      3D-Modell der Übungsfigur
└── Views/          Oberflächen: Feed, Aufnehmen, Routen, Training, Krafttraining, Profil
LaufAppWidget/      Widget-Erweiterung für die Live-Aktivität
Shared/             Gemeinsamer Code von App und Erweiterung
```

## Technik

- iOS 17+, SwiftUI, SwiftData, MapKit, Swift Charts, CoreLocation, AVFoundation, EventKit,
  HealthKit, ActivityKit/WidgetKit, SceneKit
- Externe Dienste ohne Schlüssel: OpenStreetMap (Overpass), Open-Meteo, Valhalla (FOSSGIS), OpenTopoData;
  Strava über die eigene API-Anwendung
- Keine externen Bibliotheken

## Ideen für später

**Laufen und Aufzeichnung**
- Auto-Pause: Aufzeichnung pausiert automatisch an Ampeln und läuft beim Weiterlaufen weiter
- Läufe in Apple Health speichern (damit sie in Fitness und bei Ringen mitzählen)
- Apple-Watch-App zum Aufzeichnen ohne iPhone
- Herzfrequenz-Brustgurt per Bluetooth direkt in der App
- Intervall-Ansagen per Vibration (Haptik) statt nur per Sprache

**Routen und Strecken**
- GPX-Import und -Export (Routen aus Komoot, Strava oder Garmin übernehmen und weitergeben)
- Segmente: Bestzeiten auf wiederkehrenden Abschnitten, z. B. „Saarufer Staden–Brücke“
- Hinweise zu Wetter, Sonnenuntergang und Beleuchtung bei der Routenwahl

**Training**
- Krafteinheiten in den Laufplan einplanen (an lockeren Tagen) und in den Kalender exportieren
- Trainingsbelastung und Erholung (akute vs. chronische Belastung) mit Warnung bei zu schneller Steigerung
- Schuh-Kilometer zählen mit Hinweis, wenn ein Paar ausgetauscht werden sollte
- Widget für den Home-Bildschirm: Wochenkilometer und nächste Einheit
- Siri-Kurzbefehle („Starte einen lockeren Lauf“)

**Teilen und Strava**
- Strava-Anmeldung für alle Nutzer über einen kleinen Token-Server (ohne eigene API-Anwendung)
- Mit LaufApp aufgezeichnete Läufe zu Strava hochladen
- Teilen-Bild eines Laufs (Karte und Kennzahlen) für Instagram oder WhatsApp

## Lizenzen

- 3D-Figur: „Universal Base Characters“ von Quaternius (quaternius.com), CC0 1.0 (gemeinfrei)
