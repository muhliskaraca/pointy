// Pointy: auf etwas zeigen, ^ halten + 1, und Claude Code in einer Blase am
// Mauszeiger eine Anweisung geben. Inoffiziell, nicht von Anthropic. Lizenz: MIT.
import AppKit
import SwiftUI
import Carbon.HIToolbox
import Speech
import AVFoundation
import ApplicationServices

let home = FileManager.default.homeDirectoryForCurrentUser
/// Name der App, überall sichtbar. Umbenennen: hier, in Info.plist und in build.sh.
let appName = "Pointy"
let kennung = Bundle.main.bundleIdentifier ?? "local.pointy.app"
let cache = home.appendingPathComponent("Library/Caches/\(appName)", isDirectory: true)
let logDatei = home.appendingPathComponent("Library/Logs/\(appName).log")
let umgebung = ProcessInfo.processInfo.environment
/// Claude Code wird über die Login-Shell gesucht (PATH). Anderer Ort: POINTY_CLAUDE=/pfad/zu/claude
let claudePfad = umgebung["POINTY_CLAUDE"] ?? "claude"
/// Was Claude ohne Rückfrage tun darf. Standard: nur lesen. Mehr Freiheit: POINTY_PERMISSION_MODE=acceptEdits oder auto
let rechteModus = umgebung["POINTY_PERMISSION_MODE"] ?? "default"

func log(_ s: String) {
    let z = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logDatei) {
        h.seekToEndOfFile(); h.write(z.data(using: .utf8)!); try? h.close()
    } else {
        try? z.write(to: logDatei, atomically: true, encoding: .utf8)
    }
}

extension String {
    var getrimmt: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Zwischenablage und Tasten

let eigeneMarke: Int64 = 0x5A53_5052

enum Ablage {
    typealias Stand = [[NSPasteboard.PasteboardType: Data]]
    static func sichern() -> Stand {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let x = item.data(forType: t) { d[t] = x } }
            return d
        }
    }
    static func zurueck(_ s: Stand) {
        guard !s.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(s.map { d -> NSPasteboardItem in
            let i = NSPasteboardItem()
            for (t, x) in d { i.setData(x, forType: t) }
            return i
        })
    }
    /// ⌘ + Taste an die vordere App schicken (mit eigener Marke, damit das Kürzel es durchlässt).
    static func befehl(_ taste: Int) {
        let quelle = CGEventSource(stateID: .combinedSessionState)
        for runter in [true, false] {
            let e = CGEvent(keyboardEventSource: quelle, virtualKey: CGKeyCode(taste), keyDown: runter)
            e?.flags = .maskCommand
            e?.setIntegerValueField(.eventSourceUserData, value: eigeneMarke)
            e?.post(tap: .cghidEventTap)
        }
    }
    /// Markierten Text per ⌘C holen, wenn die App ihn nicht über die Bedienungshilfen verrät
    /// (Webseiten in Chrome). Die alte Zwischenablage kommt danach zurück.
    static func markierungKopieren() -> String {
        let pb = NSPasteboard.general
        let vorher = pb.changeCount
        let alt = sichern()
        befehl(kVK_ANSI_C)
        for _ in 0..<10 where pb.changeCount == vorher { Thread.sleep(forTimeInterval: 0.035) }
        guard pb.changeCount != vorher else { return "" }
        let s = pb.string(forType: .string)?.getrimmt ?? ""
        zurueck(alt)
        return s
    }
}

// MARK: - Was unter dem Mauszeiger ist

struct Kontext {
    var app = ""
    var fenster = ""
    var adresse = ""
    var markiert = ""
    var direkt = ""
    var umgebung = ""
    var bild = ""
    var ausschnitt = ""      // selbst aufgezogener Bildausschnitt (^ + 2)
    var pid: pid_t = 0
    var ziel: AXUIElement?   // Eingabefeld unter dem Mauszeiger, falls es eins ist

    var kurz: String { [app, fenster].filter { !$0.isEmpty }.joined(separator: " · ") }

    var alsText: String {
        var z: [String] = []
        if !app.isEmpty { z.append("- App: \(app)") }
        if !fenster.isEmpty { z.append("- Fenster: \(fenster)") }
        if !adresse.isEmpty { z.append("- Adresse: \(adresse)") }
        if !ausschnitt.isEmpty { z.append("- Aufgezogener Bildausschnitt, darum geht es: \(ausschnitt) (unbedingt zuerst mit Read ansehen)") }
        if !markiert.isEmpty { z.append("- Markierter Text, darum geht es:\n\(markiert)") }
        if !direkt.isEmpty { z.append("- Direkt unter dem Mauszeiger: \(direkt)") }
        if !umgebung.isEmpty { z.append("- Text um den Mauszeiger herum:\n\(umgebung)") }
        if !bild.isEmpty { z.append("- Bildausschnitt um den Mauszeiger: \(bild) (nur mit Read ansehen, wenn der Text nicht reicht)") }
        return z.isEmpty ? "- (nichts erfasst, Bedienungshilfen evtl. nicht erlaubt)" : z.joined(separator: "\n")
    }
}

enum Erfassen {
    static var geweckt = Set<pid_t>()

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func text(_ el: AXUIElement, _ name: String) -> String? {
        guard let s = attr(el, name) as? String else { return nil }
        let t = s.getrimmt
        return t.isEmpty ? nil : t
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func eigenerText(_ el: AXUIElement) -> String? {
        for a in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] as [String] {
            if let s = text(el, a) { return s }
        }
        return nil
    }

    static func sammle(_ el: AXUIElement, _ out: inout [String], _ budget: inout Int, _ knoten: inout Int, tiefe: Int) {
        guard budget > 0, knoten < 800, tiefe < 30 else { return }
        knoten += 1
        if let s = eigenerText(el), out.last != s { out.append(s); budget -= s.count }
        if let kinder = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            for k in kinder { sammle(k, &out, &budget, &knoten, tiefe: tiefe + 1) }
        }
    }

    static func treffer(_ p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        let sys = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &el) == .success else { return nil }
        return el
    }

    /// Eingabefeld am Element oder darüber (Webseiten melden es als AXEditableAncestor).
    static func eingabefeld(_ e: AXUIElement) -> AXUIElement? {
        if let a = element(e, "AXEditableAncestor") { return a }
        let felder: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        var p: AXUIElement? = e
        for _ in 0..<6 {
            guard let x = p else { break }
            if let r = attr(x, kAXRoleAttribute) as? String, felder.contains(r) { return x }
            p = element(x, kAXParentAttribute)
        }
        return nil
    }

    /// `punkt` in Bildschirmkoordinaten mit Ursprung oben links.
    static func jetzt(punkt: CGPoint) -> Kontext {
        var k = Kontext()
        guard var e = treffer(punkt) else {
            k.app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            return k
        }
        var pid: pid_t = 0
        AXUIElementGetPid(e, &pid)
        let appEl = AXUIElementCreateApplication(pid)
        // Chrome und Electron bauen ihren Baum für Webinhalte erst auf Nachfrage
        if !geweckt.contains(pid) {
            geweckt.insert(pid)
            AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            Thread.sleep(forTimeInterval: 0.35)
            if let neu = treffer(punkt) { e = neu }
        }
        k.app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        if let w = element(e, kAXWindowAttribute) ?? element(appEl, kAXFocusedWindowAttribute) {
            k.fenster = text(w, kAXTitleAttribute) ?? ""
        }
        if let f = element(appEl, kAXFocusedUIElementAttribute), let sel = text(f, kAXSelectedTextAttribute) {
            k.markiert = String(sel.prefix(4000))
        }
        k.direkt = String((eigenerText(e) ?? "").prefix(500))
        k.pid = pid
        k.ziel = eingabefeld(e)

        // Adresse der Webseite: der Webbereich trägt sie selbst (kein Fernsteuern nötig)
        var p: AXUIElement? = e
        var web: AXUIElement?
        for _ in 0..<40 {
            guard let x = p else { break }
            if (attr(x, kAXRoleAttribute) as? String) == "AXWebArea" {
                web = x
                if let u = attr(x, "AXURL") as? URL { k.adresse = u.absoluteString }
                else if let u = attr(x, "AXURL") as? NSURL { k.adresse = u.absoluteString ?? "" }
                break
            }
            p = element(x, kAXParentAttribute)
        }
        var weg = k.markiert.isEmpty ? "" : "Feld"
        // Markierung auf Webseiten (Chrome, Safari): über die Textmarken des Webbereichs
        if k.markiert.isEmpty, let web, let r = attr(web, "AXSelectedTextMarkerRange") {
            var v: AnyObject?
            if AXUIElementCopyParameterizedAttributeValue(web, "AXStringForTextMarkerRange" as CFString, r, &v) == .success,
               let s = (v as? String)?.getrimmt, !s.isEmpty {
                k.markiert = String(s.prefix(4000)); weg = "Web"
            }
        }
        // Rückfall: ⌘C, nur wenn die App unter dem Mauszeiger vorne ist (sonst ginge es an die falsche App)
        if k.markiert.isEmpty, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            k.markiert = String(Ablage.markierungKopieren().prefix(4000))
            if !k.markiert.isEmpty { weg = "Kopieren" }
        }
        if !weg.isEmpty { log("Markierung über \(weg)") }

        // Umgebung: so weit nach oben, bis genug Text zusammenkommt
        var basis = e
        var gesammelt: [String] = []
        for _ in 0..<8 {
            var out: [String] = []
            var budget = 4000
            var n = 0
            sammle(basis, &out, &budget, &n, tiefe: 0)
            gesammelt = out
            if out.joined(separator: " ").count >= 500 { break }
            guard let hoch = element(basis, kAXParentAttribute),
                  (attr(hoch, kAXRoleAttribute) as? String) != "AXApplication" else { break }
            basis = hoch
        }
        k.umgebung = String(gesammelt.joined(separator: "\n").prefix(4000))
        return k
    }

    /// Bildausschnitt um den Mauszeiger, vor dem Öffnen der Blase.
    static func bild(punkt: CGPoint) -> String {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // alte Ausschnitte wegräumen, die letzten 10 bleiben
        if let alle = try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter({ $0.lastPathComponent.hasPrefix("bild-") }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }), alle.count > 10 {
            for f in alle.dropFirst(10) { try? FileManager.default.removeItem(at: f) }
        }
        let ziel = cache.appendingPathComponent("bild-\(Int(Date().timeIntervalSince1970)).png")
        let w = 1000.0, h = 700.0
        let r = "\(Int(max(0, punkt.x - w / 2))),\(Int(max(0, punkt.y - h / 2))),\(Int(w)),\(Int(h))"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R", r, ziel.path]
        do { try p.run(); p.waitUntilExit() } catch { return "" }
        return FileManager.default.fileExists(atPath: ziel.path) ? ziel.path : ""
    }
}

// MARK: - Sprechen

final class Hoeren {
    private let erkenner = (SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "de-DE")))
    private let engine = AVAudioEngine()
    private var anfrage: SFSpeechAudioBufferRecognitionRequest?
    private var aufgabe: SFSpeechRecognitionTask?
    private(set) var aktiv = false

    func start(teil: @escaping (String) -> Void, fehler: @escaping (String) -> Void, bereit: @escaping () -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else {
                    fehler("Spracherkennung nicht erlaubt: Systemeinstellungen › Datenschutz › Spracherkennung")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        guard ok else { fehler("Mikrofon nicht erlaubt: Systemeinstellungen › Datenschutz › Mikrofon"); return }
                        self.los(teil: teil, fehler: fehler, bereit: bereit)
                    }
                }
            }
        }
    }

    private func los(teil: @escaping (String) -> Void, fehler: @escaping (String) -> Void, bereit: @escaping () -> Void) {
        guard !aktiv else { return }
        guard let erkenner, erkenner.isAvailable else { fehler("Spracherkennung gerade nicht verfügbar, bitte tippen"); return }
        let a = SFSpeechAudioBufferRecognitionRequest()
        a.shouldReportPartialResults = true
        if erkenner.supportsOnDeviceRecognition { a.requiresOnDeviceRecognition = true }
        anfrage = a
        let node = engine.inputNode
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buf, _ in a.append(buf) }
        engine.prepare()
        do { try engine.start() } catch {
            node.removeTap(onBus: 0)
            fehler("Mikrofon startet nicht, bitte tippen")
            return
        }
        aktiv = true
        bereit()
        aufgabe = erkenner.recognitionTask(with: a) { [weak self] res, err in
            if let res { DispatchQueue.main.async { teil(res.bestTranscription.formattedString) } }
            if err != nil || (res?.isFinal ?? false) { DispatchQueue.main.async { self?.stop() } }
        }
    }

    func stop() {
        guard aktiv else { return }
        aktiv = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        anfrage?.endAudio()
        aufgabe?.finish()
        anfrage = nil
        aufgabe = nil
    }
}

// MARK: - Claude im Hintergrund

enum Ereignis {
    case session(String)
    case zwischentext(String)
    case werkzeug(String)
    case fertig(antwort: String, fehler: String?)
}

final class ClaudeLauf {
    private var prozess: Process?
    private var fertigGemeldet = false

    var laeuft: Bool { prozess?.isRunning ?? false }

    func abbrechen() {
        if let p = prozess, p.isRunning { p.terminate() }
        prozess = nil
    }

    func start(prompt: String, session: String?, system: String, melde: @escaping (Ereignis) -> Void) {
        fertigGemeldet = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var args = ["-lc", "exec \"$0\" \"$@\"", claudePfad, "-p", prompt,
                    "--output-format", "stream-json", "--verbose",
                    "--permission-mode", rechteModus, "--allowedTools", "Read", "--append-system-prompt", system]
        if let session { args += ["--resume", session] }
        p.arguments = args
        p.currentDirectoryURL = home
        var env = ProcessInfo.processInfo.environment
        env["POINTY"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        var puffer = Data()
        var fehlerText = Data()
        let sende: (Ereignis) -> Void = { e in DispatchQueue.main.async { melde(e) } }
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            puffer.append(d)
            while let i = puffer.firstIndex(of: 0x0A) {
                let zeile = puffer.subdata(in: puffer.startIndex..<i)
                puffer.removeSubrange(puffer.startIndex...i)
                self?.lies(zeile, sende)
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { fehlerText.append(d) }
        }
        p.terminationHandler = { [weak self] pr in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, !self.fertigGemeldet else { return }
                self.fertigGemeldet = true
                let t = String(data: fehlerText, encoding: .utf8)?.getrimmt ?? ""
                let grund = pr.terminationReason == .uncaughtSignal ? "abgebrochen" : (t.isEmpty ? "Claude hat sich ohne Antwort beendet (Code \(pr.terminationStatus))" : String(t.suffix(300)))
                melde(.fertig(antwort: "", fehler: grund))
            }
        }
        do { try p.run() } catch {
            melde(.fertig(antwort: "", fehler: "Claude startet nicht: \(error.localizedDescription)"))
            return
        }
        prozess = p
    }

    private var sessionGemeldet = false

    private func lies(_ zeile: Data, _ sende: (Ereignis) -> Void) {
        guard let o = (try? JSONSerialization.jsonObject(with: zeile)) as? [String: Any] else { return }
        let typ = o["type"] as? String
        if let sid = o["session_id"] as? String, typ == "system" || typ == "result" { sende(.session(sid)) }
        switch typ {
        case "assistant":
            guard let m = o["message"] as? [String: Any], let teile = m["content"] as? [[String: Any]] else { return }
            for t in teile {
                if t["type"] as? String == "text", let s = t["text"] as? String, !s.getrimmt.isEmpty { sende(.zwischentext(s.getrimmt)) }
                if t["type"] as? String == "tool_use", let n = t["name"] as? String { sende(.werkzeug(n)) }
            }
        case "result":
            let istFehler = (o["is_error"] as? Bool) == true
            let text = (o["result"] as? String ?? "").getrimmt
            DispatchQueue.main.async { self.fertigGemeldet = true }
            sende(.fertig(antwort: istFehler ? "" : text, fehler: istFehler ? (text.isEmpty ? "Fehler bei Claude" : text) : nil))
        default:
            break
        }
    }

    static func freundlich(_ n: String) -> String {
        if n.contains("Gmail") { return "arbeitet in Gmail" }
        if n.contains("Google_Drive") { return "arbeitet in Google Drive" }
        switch n {
        case "Read": return "liest"
        case "Bash": return "führt einen Befehl aus"
        case "ToolSearch": return "lädt ein Werkzeug"
        case "WebSearch", "WebFetch": return "sucht im Netz"
        case "Edit", "Write": return "schreibt eine Datei"
        case "Grep", "Glob": return "sucht in Dateien"
        default: return "arbeitet"
        }
    }
}

let blasenRegeln = """
Du läufst in der Sprechblase „\(appName)“ direkt am Mauszeiger. \
Jemand hat auf etwas auf dem Bildschirm gezeigt und dir eine Anweisung gesprochen oder getippt. \
In der ersten Nachricht steht, worauf gezeigt wird (App, Fenster, Webadresse, Text um den Mauszeiger, Bildausschnitt).

Regeln für die Blase:
- Antworte kurz in der Sprache der Anweisung, höchstens 5 Sätze, keine Tabellen, keine Überschriften. Gesprochene Anweisungen können Hörfehler haben, deute sie sinnvoll.
- Nichts senden, posten, kaufen oder löschen. Nachrichten und Mails nur formulieren oder als Entwurf ablegen.
- Unklar? Eine kurze Rückfrage. Wird die Aufgabe groß, schlag vor, unten „Im Terminal weiter“ zu drücken.
- Sag am Ende in einem Satz, was du getan hast.
- Die Blase hat einen Knopf „Einsetzen“, der Text an die Stelle schreibt, auf die gezeigt wird (Nachrichtenfeld, Notiz, Formular). \
Formulierst du einen Text zum Einfügen (Antwort, Nachricht, Umformulierung, Übersetzung), setze genau diesen Text, ohne Vorrede, \
zwischen <einsetzen> und </einsetzen>. Kommentar gehört außerhalb der Marken. Ohne Marken setzt der Knopf deine ganze Antwort ein.
"""

/// Teilt eine Antwort in Anzeige und einzusetzenden Text.
func zerlege(_ antwort: String) -> (anzeige: String, einsetzen: String) {
    guard let a = antwort.range(of: "<einsetzen>"), let b = antwort.range(of: "</einsetzen>", range: a.upperBound..<antwort.endIndex) else {
        return (antwort, antwort)
    }
    let kern = String(antwort[a.upperBound..<b.lowerBound]).getrimmt
    let anzeige = (String(antwort[..<a.lowerBound]) + kern + String(antwort[b.upperBound...]))
        .replacingOccurrences(of: "\n\n\n", with: "\n\n").getrimmt
    return (anzeige, kern)
}

// MARK: - Blase

// MARK: - Randfarbe

/// Leuchtender Rand der Blase. „Automatisch“ richtet sich nach dem Hintergrund am Mauszeiger.
enum Randfarbe: String, CaseIterable {
    case automatisch, neongruen, pink, cyan, orange, lila, weiss
    var name: String {
        switch self {
        case .automatisch: return "Automatisch (nach Hintergrund)"
        case .neongruen: return "Neon-Grün"
        case .pink: return "Pink"
        case .cyan: return "Cyan"
        case .orange: return "Orange"
        case .lila: return "Lila"
        case .weiss: return "Weiß"
        }
    }
    var farbe: Color {
        switch self {
        case .automatisch, .neongruen: return Color(red: 0.22, green: 1.0, blue: 0.08)
        case .pink: return Color(red: 1.0, green: 0.12, blue: 0.62)
        case .cyan: return Color(red: 0.0, green: 0.9, blue: 1.0)
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.0)
        case .lila: return Color(red: 0.62, green: 0.25, blue: 1.0)
        case .weiss: return Color.white
        }
    }
    static var gewaehlt: Randfarbe {
        get { Randfarbe(rawValue: UserDefaults.standard.string(forKey: "randfarbe") ?? "") ?? .automatisch }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "randfarbe") }
    }
    /// Farbe für diesen Hintergrund: dunkel → Neon-Grün, hell → kräftiges Pink (Neon geht auf Hell unter).
    static func fuer(helligkeit: Double?) -> Color {
        let wahl = gewaehlt
        guard wahl == .automatisch else { return wahl.farbe }
        guard let h = helligkeit else { return Randfarbe.neongruen.farbe }
        return h < 0.55 ? Randfarbe.neongruen.farbe : Color(red: 0.90, green: 0.0, blue: 0.50)
    }
}

/// Mittlere Helligkeit (0 bis 1) eines Bildes, z. B. des Bildes um den Mauszeiger.
func helligkeit(_ pfad: String) -> Double? {
    guard !pfad.isEmpty, let img = NSImage(contentsOfFile: pfad),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let n = 16
    var px = [UInt8](repeating: 0, count: n * n * 4)
    let ok = px.withUnsafeMutableBytes { puffer -> Bool in
        guard let ctx = CGContext(data: puffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        return true
    }
    guard ok else { return nil }
    var summe = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
        summe += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
    }
    return summe / Double(n * n) / 255
}

final class Blase: ObservableObject {
    struct Zeile: Identifiable {
        let id = UUID()
        let vonMir: Bool
        let text: String
        var fehler = false
        var einsetzen = ""
    }
    @Published var eingabe = ""
    @Published var zeilen: [Zeile] = []
    @Published var status = ""
    @Published var laeuft = false
    @Published var hoert = false
    @Published var hinweis = ""
    @Published var session: String?
    @Published var kontextKurz = ""
    @Published var fokus = 0
    @Published var markiertZeichen = 0
    @Published var ausschnittBild: NSImage?
    @Published var rand: Color = Randfarbe.fuer(helligkeit: nil)
    var ausschnittNeu = ""   // nach der ersten Nachricht aufgezogen, geht mit der nächsten mit
    var kontext = Kontext()
    var vorText = ""

    func zuruecksetzen() {
        eingabe = ""; zeilen = []; status = ""; laeuft = false; hoert = false
        hinweis = ""; session = nil; kontextKurz = ""; vorText = ""
        markiertZeichen = 0; ausschnittBild = nil; ausschnittNeu = ""
    }
}

struct Glas: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BlasenAnsicht: View {
    @ObservedObject var m: Blase
    var schliessen: () -> Void
    var mikro: () -> Void
    var ausschnitt: () -> Void
    var senden: () -> Void
    var terminal: () -> Void
    var einsetzen: (String) -> Void
    @FocusState private var fokus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.rays").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(m.kontextKurz.isEmpty ? appName : m.kontextKurz)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button(action: schliessen) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Schließen (Esc)")
            }

            if m.markiertZeichen > 0 || m.ausschnittBild != nil {
                HStack(spacing: 8) {
                    if let b = m.ausschnittBild {
                        Image(nsImage: b).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 120, maxHeight: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor.opacity(0.7)))
                    }
                    if m.markiertZeichen > 0 {
                        Label("Markierung · \(m.markiertZeichen) Zeichen", systemImage: "text.cursor")
                            .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                    Spacer(minLength: 0)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(m.zeilen) { z in
                            Text(z.text)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .foregroundStyle(z.fehler ? Color.orange : (z.vonMir ? Color.secondary : Color.primary))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: z.vonMir ? .trailing : .leading)
                                .multilineTextAlignment(z.vonMir ? .trailing : .leading)
                                .id(z.id)
                            if !z.vonMir && !z.fehler && !z.einsetzen.isEmpty {
                                Button { einsetzen(z.einsetzen) } label: {
                                    Label("Einsetzen", systemImage: "text.insert").font(.system(size: 11.5, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                                .foregroundStyle(Color.accentColor)
                                .help("Text an die Stelle schreiben, auf die du gezeigt hast (⌘ Enter)")
                                .disabled(m.laeuft)
                            }
                        }
                        if !m.status.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(m.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .id("status")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: m.zeilen.count) {
                    withAnimation { proxy.scrollTo(m.zeilen.last?.id, anchor: .bottom) }
                }
                .onChange(of: m.status) {
                    withAnimation { proxy.scrollTo("status", anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(m.hoert ? "Ich höre zu …" : "Anweisung sprechen oder tippen", text: $m.eingabe, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .focused($fokus)
                    .onSubmit(senden)
                Button(action: ausschnitt) {
                    Image(systemName: "viewfinder").font(.system(size: 15)).foregroundStyle(Color.secondary).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).help("Bildausschnitt aufziehen (^ + 2)")
                Button(action: mikro) {
                    Image(systemName: m.hoert ? "mic.fill" : "mic")
                        .font(.system(size: 15))
                        .foregroundStyle(m.hoert ? Color.red : Color.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).help(m.hoert ? "Zuhören beenden" : "Sprechen")
                Button(action: senden) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 21))
                }
                .buttonStyle(.plain)
                .foregroundStyle(m.eingabe.getrimmt.isEmpty || m.laeuft ? Color.secondary.opacity(0.5) : Color.accentColor)
                .disabled(m.eingabe.getrimmt.isEmpty || m.laeuft)
                .help("Abschicken (Enter oder ^ + 1)")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))

            HStack(spacing: 8) {
                Text(m.hinweis.isEmpty ? "^ + 1 oder Enter schickt ab · Esc schließt" : m.hinweis)
                    .font(.system(size: 10.5))
                    .foregroundStyle(m.hinweis.isEmpty ? Color.secondary.opacity(0.8) : Color.orange)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if m.session != nil {
                    Button("Im Terminal weiter", action: terminal)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .disabled(m.laeuft)
                }
            }
        }
        .padding(14)
        .background(ZStack { Glas(); Color(red: 0.10, green: 0.10, blue: 0.11).opacity(0.94) }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(m.rand.opacity(0.45), lineWidth: 7).blur(radius: 5)
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(m.rand, lineWidth: 1.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
        )
        .environment(\.colorScheme, .dark)
        .onChange(of: m.fokus) { fokus = true }
    }
}

final class BlasenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Kürzel ^ halten + 1 (linke Hand)

final class Kuerzel {
    static let shared = Kuerzel()
    var ausgeloest: (Int) -> Void = { _ in }  // 1 = Blase, 2 = Ausschnitt
    private(set) var tap: CFMachPort?
    private let marke: Int64 = 0x5A53_5052
    private var zirkumflex: Int64 = Int64(kVK_ISO_Section)
    private let eins: Int64 = Int64(kVK_ANSI_1)
    private let zwei: Int64 = Int64(kVK_ANSI_2)
    private var wartet = false      // ^ gedrückt, noch zurückgehalten
    private var verbraucht = false  // ^ + 1 ausgelöst, ^ loslassen schlucken

    func starten() -> Bool {
        if tap != nil { return true }
        // ISO-Tastatur (deutsch): Taste links neben der 1 ist kVK_ISO_Section, sonst kVK_ANSI_Grave
        zirkumflex = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO ? Int64(kVK_ISO_Section) : Int64(kVK_ANSI_Grave)
        let maske = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: CGEventMask(maske),
                                        callback: { _, typ, ev, _ in Kuerzel.shared.behandle(typ, ev) },
                                        userInfo: nil) else { return false }
        let quelle = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), quelle, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        log("Kürzel aktiv, Taste \(zirkumflex)")
        return true
    }

    private func poste(_ code: Int64, runter: Bool, wie vorlage: CGEvent? = nil) {
        let e = vorlage?.copy() ?? CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: runter)
        e?.setIntegerValueField(.eventSourceUserData, value: marke)
        e?.post(tap: .cgSessionEventTap)
    }

    private func behandle(_ typ: CGEventType, _ ev: CGEvent) -> Unmanaged<CGEvent>? {
        if typ == .tapDisabledByTimeout || typ == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(ev)
        }
        if ev.getIntegerValueField(.eventSourceUserData) == marke { return Unmanaged.passUnretained(ev) }
        let code = ev.getIntegerValueField(.keyboardEventKeycode)
        let wiederholt = ev.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let modifikatoren = ev.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])

        if code == zirkumflex {
            if typ == .keyDown {
                if verbraucht || wartet { return nil }               // Wiederholung beim Halten
                if !modifikatoren.isEmpty || wiederholt { return Unmanaged.passUnretained(ev) } // ° und Co. normal
                wartet = true
                return nil
            }
            if typ == .keyUp {
                if verbraucht { verbraucht = false; return nil }
                if wartet {                                           // ^ allein getippt: nachreichen
                    wartet = false
                    poste(zirkumflex, runter: true)
                    poste(zirkumflex, runter: false)
                    return nil
                }
            }
            return Unmanaged.passUnretained(ev)
        }

        if (wartet || verbraucht) && typ == .keyDown && (code == eins || code == zwei) {
            wartet = false
            verbraucht = true
            if !wiederholt {
                let welche = code == eins ? 1 : 2
                DispatchQueue.main.async { self.ausgeloest(welche) }
            }
            return nil
        }
        if wartet && typ == .keyDown {
            // andere Taste: ^ zuerst nachreichen, dann die Taste in richtiger Reihenfolge
            wartet = false
            poste(zirkumflex, runter: true)
            poste(zirkumflex, runter: false)
            poste(code, runter: true, wie: ev)
            return nil
        }
        if verbraucht && typ == .keyUp && (code == eins || code == zwei) { return nil }
        return Unmanaged.passUnretained(ev)
    }
}

// MARK: - App

final class Steuerung: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let m = Blase()
    let hoeren = Hoeren()
    let lauf = ClaudeLauf()
    var panel: BlasenPanel!
    var status: NSStatusItem!
    var escMonitor: Any?
    var kuerzelTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        baueMenue()
        bauePanel()
        Kuerzel.shared.ausgeloest = { [weak self] n in n == 1 ? self?.kuerzel() : self?.ausschnitt() }
        let vertraut = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        log("Start, Bedienungshilfen \(vertraut ? "erlaubt" : "fehlen")")
        if !Kuerzel.shared.starten() {
            // Warten, bis der Nutzer die Bedienungshilfen erlaubt
            kuerzelTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
                if Kuerzel.shared.starten() { t.invalidate(); self?.kuerzelTimer = nil }
            }
        }
        let dz = DistributedNotificationCenter.default()
        dz.addObserver(forName: .init("\(kennung).oeffnen"), object: nil, queue: .main) { [weak self] _ in self?.kuerzel() }
        dz.addObserver(forName: .init("\(kennung).still"), object: nil, queue: .main) { [weak self] _ in self?.oeffnen(zuhoeren: false) }
        dz.addObserver(forName: .init("\(kennung).ausschnitt"), object: nil, queue: .main) { [weak self] _ in self?.ausschnitt() }
        dz.addObserver(forName: .init("\(kennung).einsetzen"), object: nil, queue: .main) { [weak self] _ in
            guard let self, let t = self.m.zeilen.last(where: { !$0.vonMir && !$0.fehler && !$0.einsetzen.isEmpty })?.einsetzen else { return }
            self.einsetzen(t)
        }
        dz.addObserver(forName: .init("\(kennung).test"), object: nil, queue: .main) { [weak self] note in
            guard let self, let text = note.object as? String else { return }
            if !self.panel.isVisible || self.m.session != nil {
                self.schliessen()
                self.oeffnen(zuhoeren: false)
            }
            self.m.eingabe = text
            self.senden()
        }
    }

    // Menüleiste
    func baueMenue() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: appName)
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Blase öffnen (^ halten + 1)", action: #selector(menuOeffnen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let ax = AXIsProcessTrusted()
        let i = menu.addItem(withTitle: ax ? "Bedienungshilfen: erlaubt" : "Bedienungshilfen fehlen: hier erlauben", action: ax ? nil : #selector(rechte), keyEquivalent: "")
        i.target = self
        if Kuerzel.shared.tap == nil { menu.addItem(withTitle: "Kürzel ^ + 1 wartet auf Bedienungshilfen", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let farbe = NSMenuItem(title: "Randfarbe", action: nil, keyEquivalent: "")
        let unter = NSMenu()
        for f in Randfarbe.allCases {
            let e = unter.addItem(withTitle: f.name, action: #selector(randfarbeWaehlen(_:)), keyEquivalent: "")
            e.target = self
            e.representedObject = f.rawValue
            e.state = f == Randfarbe.gewaehlt ? .on : .off
        }
        farbe.submenu = unter
        menu.addItem(farbe)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Autostart ausschalten", action: #selector(autostartAus), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Beenden", action: #selector(beenden), keyEquivalent: "").target = self
    }

    @objc func menuOeffnen() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.oeffnen(zuhoeren: true) } }
    @objc func rechte() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func beenden() { NSApp.terminate(nil) }
    @objc func randfarbeWaehlen(_ e: NSMenuItem) {
        guard let roh = e.representedObject as? String, let f = Randfarbe(rawValue: roh) else { return }
        Randfarbe.gewaehlt = f
        m.rand = Randfarbe.fuer(helligkeit: helligkeit(m.kontext.bild))
        log("Randfarbe: \(f.rawValue)")
    }
    @objc func autostartAus() {
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(kennung).plist")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())", plist.path]
        try? p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: plist)
        log("Autostart aus")
    }

    func bauePanel() {
        panel = BlasenPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let ansicht = BlasenAnsicht(m: m,
                                    schliessen: { [weak self] in self?.schliessen() },
                                    mikro: { [weak self] in self?.mikro() },
                                    ausschnitt: { [weak self] in self?.ausschnitt() },
                                    senden: { [weak self] in self?.senden() },
                                    terminal: { [weak self] in self?.imTerminal() },
                                    einsetzen: { [weak self] t in self?.einsetzen(t) })
        panel.contentView = NSHostingView(rootView: ansicht)
    }

    // ^ + 1: öffnen, sonst abschicken oder zuhören
    func kuerzel() {
        if !panel.isVisible { oeffnen(zuhoeren: true); return }
        if !m.eingabe.getrimmt.isEmpty { senden(); return }
        if !hoeren.aktiv && !m.laeuft { mikro() }
    }

    // ^ + 2 oder Knopf: Bildausschnitt aufziehen, Esc bricht ab
    var schneidet = false
    @objc func ausschnitt() {
        guard !schneidet else { return }
        schneidet = true
        let war = panel.isVisible
        hoeren.stop()
        m.hoert = false
        if war { panel.orderOut(nil) }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let ziel = cache.appendingPathComponent("ausschnitt-\(Int(Date().timeIntervalSince1970)).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-s", "-x", ziel.path]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.schneidet = false
                guard FileManager.default.fileExists(atPath: ziel.path) else {
                    log("Ausschnitt abgebrochen")
                    if war { self.panel.orderFrontRegardless(); self.panel.makeKey() }
                    return
                }
                if !war { self.oeffnen(zuhoeren: true) }
                if self.m.session == nil { self.m.kontext.ausschnitt = ziel.path } else { self.m.ausschnittNeu = ziel.path }
                self.m.ausschnittBild = NSImage(contentsOf: ziel)
                log("Ausschnitt: \(ziel.lastPathComponent)")
                if war {
                    self.panel.orderFrontRegardless()
                    self.panel.makeKey()
                    self.m.fokus += 1
                }
            }
        }
        do { try p.run() } catch { schneidet = false; if war { panel.orderFrontRegardless() } }
    }

    func oeffnen(zuhoeren: Bool) {
        let maus = NSEvent.mouseLocation
        let hauptHoehe = NSScreen.screens.first?.frame.height ?? 0
        let oben = CGPoint(x: maus.x, y: hauptHoehe - maus.y)
        lauf.abbrechen()
        hoeren.stop()
        m.zuruecksetzen()
        m.kontext = Erfassen.jetzt(punkt: oben)
        m.kontext.bild = Erfassen.bild(punkt: oben)
        m.rand = Randfarbe.fuer(helligkeit: helligkeit(m.kontext.bild))
        m.kontextKurz = m.kontext.kurz
        m.markiertZeichen = m.kontext.markiert.count
        log("Geöffnet über \(m.kontext.kurz) | Adresse \(m.kontext.adresse.isEmpty ? "-" : String(m.kontext.adresse.prefix(80))) | Text \(m.kontext.umgebung.count) Zeichen, markiert \(m.kontext.markiert.count), Bild \(m.kontext.bild.isEmpty ? "nein" : "ja")")

        // neben den Mauszeiger, im sichtbaren Bereich
        let groesse = panel.frame.size
        let schirm = NSScreen.screens.first(where: { NSMouseInRect(maus, $0.frame, false) }) ?? NSScreen.main!
        let vis = schirm.visibleFrame
        var x = maus.x + 18
        var y = maus.y - 18 - groesse.height
        if x + groesse.width > vis.maxX { x = maus.x - 18 - groesse.width }
        if y < vis.minY { y = maus.y + 18 }
        x = min(max(x, vis.minX + 8), vis.maxX - groesse.width - 8)
        y = min(max(y, vis.minY + 8), vis.maxY - groesse.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        panel.makeKey()
        m.fokus += 1
        if escMonitor == nil {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == UInt16(kVK_Escape), self?.panel.isKeyWindow == true { self?.schliessen(); return nil }
                if e.keyCode == UInt16(kVK_Return), e.modifierFlags.contains(.command), let self, self.panel.isKeyWindow, !self.m.laeuft,
                   let t = self.m.zeilen.last(where: { !$0.vonMir && !$0.fehler && !$0.einsetzen.isEmpty })?.einsetzen {
                    self.einsetzen(t); return nil
                }
                return e
            }
        }
        if zuhoeren { mikro() }
    }

    func schliessen() {
        hoeren.stop()
        m.hoert = false
        if lauf.laeuft { log("Abgebrochen durch Schließen") }
        lauf.abbrechen()
        panel.orderOut(nil)
    }

    func mikro() {
        if hoeren.aktiv {
            hoeren.stop()
            m.hoert = false
            return
        }
        m.vorText = m.eingabe.getrimmt
        m.hinweis = ""
        hoeren.start(teil: { [weak self] t in
            guard let self, self.hoeren.aktiv else { return }
            self.m.eingabe = self.m.vorText.isEmpty ? t : self.m.vorText + " " + t
        }, fehler: { [weak self] f in
            self?.m.hoert = false
            self?.m.hinweis = f
            log("Hören: \(f)")
        }, bereit: { [weak self] in
            self?.m.hoert = true
        })
    }

    func senden() {
        let text = m.eingabe.getrimmt
        guard !text.isEmpty, !m.laeuft else { return }
        hoeren.stop()
        m.hoert = false
        m.hinweis = ""
        m.zeilen.append(.init(vonMir: true, text: text))
        m.eingabe = ""
        let prompt = m.session == nil
            ? "Anweisung: \(text)\n\nWorauf gezeigt wird:\n\(m.kontext.alsText)"
            : "Anweisung: \(text)" + (m.ausschnittNeu.isEmpty ? "" : "\n\nDazu wurde jetzt dieser Bildausschnitt aufgezogen, unbedingt mit Read ansehen: \(m.ausschnittNeu)")
        m.ausschnittNeu = ""
        m.laeuft = true
        m.status = "Claude denkt …"
        log("Gesendet (\(m.session == nil ? "neu" : "Folge")): \(text.prefix(200))")
        lauf.start(prompt: prompt, session: m.session, system: blasenRegeln) { [weak self] e in
            guard let self else { return }
            switch e {
            case .session(let s): self.m.session = s
            case .zwischentext(let t): self.m.status = String(t.prefix(140))
            case .werkzeug(let n): self.m.status = "Claude \(ClaudeLauf.freundlich(n)) …"
            case .fertig(let antwort, let fehler):
                self.m.laeuft = false
                self.m.status = ""
                if let fehler {
                    if fehler != "abgebrochen" { self.m.zeilen.append(.init(vonMir: false, text: fehler, fehler: true)) }
                    log("Fehler: \(fehler.prefix(300))")
                } else {
                    let (anzeige, kern) = zerlege(antwort)
                    self.m.zeilen.append(.init(vonMir: false, text: anzeige.isEmpty ? "Erledigt." : anzeige, einsetzen: kern))
                    log("Antwort: \(antwort.prefix(400).replacingOccurrences(of: "\n", with: " "))")
                }
                self.m.fokus += 1
            }
        }
    }

    /// Schreibt den Text an die Stelle, auf die der Nutzer gezeigt hat: Blase weg, Ziel-App nach vorn,
    /// Eingabefeld fokussieren, über die Zwischenablage einfügen, alte Zwischenablage zurück.
    func einsetzen(_ text: String) {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else { m.hinweis = "Einsetzen braucht die Bedienungshilfen"; return }
        let k = m.kontext
        let pb = NSPasteboard.general
        let alt = Ablage.sichern()
        pb.clearContents()
        pb.setString(text, forType: .string)
        let marke = pb.changeCount
        hoeren.stop()
        m.hoert = false
        panel.orderOut(nil)
        NSRunningApplication(processIdentifier: k.pid)?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let f = k.ziel { AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Ablage.befehl(kVK_ANSI_V)
                log("Eingesetzt in \(k.app) (\(text.count) Zeichen, Feld \(k.ziel == nil ? "fokussiert" : "unter Maus"))")
                // Zwischenablage zurück, wenn niemand sie inzwischen geändert hat
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if pb.changeCount == marke { Ablage.zurueck(alt) }
                }
            }
        }
    }

    func imTerminal() {
        guard let sid = m.session else { return }
        let datei = cache.appendingPathComponent("weiter-\(sid.prefix(8)).command")
        let inhalt = "#!/bin/zsh -il\ncd ~\nclaude --resume \(sid)\n"
        do {
            try inhalt.write(to: datei, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: datei.path)
        } catch { m.hinweis = "Terminal-Datei ging nicht"; return }
        NSWorkspace.shared.open([datei], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
        log("Im Terminal weiter: \(sid)")
        hoeren.stop()
        panel.orderOut(nil)
    }
}

// MARK: - Start

let argumente = CommandLine.arguments
if let i = argumente.firstIndex(of: "--test"), i + 1 < argumente.count {
    DistributedNotificationCenter.default().postNotificationName(.init("\(kennung).test"), object: argumente[i + 1], userInfo: nil, deliverImmediately: true)
    exit(0)
}
if argumente.contains("--ausschnitt") {
    DistributedNotificationCenter.default().postNotificationName(.init("\(kennung).ausschnitt"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if argumente.contains("--einsetzen") {
    DistributedNotificationCenter.default().postNotificationName(.init("\(kennung).einsetzen"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if argumente.contains("--still") {   // Blase öffnen, ohne zuzuhören (zum Tippen)
    DistributedNotificationCenter.default().postNotificationName(.init("\(kennung).still"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
if argumente.contains("--oeffnen") {
    DistributedNotificationCenter.default().postNotificationName(.init("\(kennung).oeffnen"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
// nur einmal laufen
let eigene = kennung
if NSRunningApplication.runningApplications(withBundleIdentifier: eigene).filter({ $0.processIdentifier != getpid() }).count > 0 {
    exit(0)
}
let app = NSApplication.shared
let steuerung = Steuerung()
app.delegate = steuerung
app.setActivationPolicy(.accessory)
app.run()
