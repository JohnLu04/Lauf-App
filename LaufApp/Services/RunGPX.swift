import Foundation

/// Läufe aus LaufApp (aufgezeichnet oder eingetragen) zu Strava hochladen bzw. in Apple Health speichern.
enum RunExport {
    /// Nur eigene Läufe: Läufe aus Strava oder Apple Health liegen dort schon.
    static func canUploadToStrava(_ run: Run) -> Bool {
        (run.source.isEmpty || run.isManual) && run.stravaID == nil
    }

    static func canSaveToHealth(_ run: Run) -> Bool {
        (run.source.isEmpty || run.isManual) && run.healthID == nil
    }

    /// GPX-Datei der aufgezeichneten Strecke (Pausen als eigene Abschnitte).
    static func gpx(for run: Run) -> Data {
        let time = ISO8601DateFormatter()
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LaufApp" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><time>\(time.string(from: run.startDate))</time></metadata>
        <trk><name>\(escape(run.title))</name><type>running</type>

        """
        for segment in RunAnalysis.segments(run.route) where !segment.isEmpty {
            xml += "<trkseg>\n"
            for point in segment {
                xml += "<trkpt lat=\"\(String(format: "%.7f", point.latitude))\" lon=\"\(String(format: "%.7f", point.longitude))\">"
                if let altitude = point.altitude { xml += "<ele>\(String(format: "%.1f", altitude))</ele>" }
                xml += "<time>\(time.string(from: point.timestamp))</time></trkpt>\n"
            }
            xml += "</trkseg>\n"
        }
        xml += "</trk>\n</gpx>\n"
        return Data(xml.utf8)
    }
}
