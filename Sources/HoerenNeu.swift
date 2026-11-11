import Foundation
import Speech
import AVFoundation

/// Apples neue Spracherkennung (macOS 26): für längeres Sprechen mit Pausen gebaut, setzt Satzzeichen.
/// Die alte Erkennung verschluckte live nach jeder Pause den Anfang des nächsten Abschnitts (Muhlis 11.11.2026).
@available(macOS 26.0, *)
final class HoerenNeu {
    private let engine = AVAudioEngine()
    private var analysierer: SpeechAnalyzer?
    private var zufluss: AsyncStream<AnalyzerInput>.Continuation?
    private var leser: Task<Void, Never>?
    private var wandler: AVAudioConverter?
    private var ein: AVAudioFormat?
    private var ziel: AVAudioFormat?
    private(set) var laeuft = false
    private(set) var gesamt = ""

    /// Mikrofon an, Text kommt laufend über `teil` (bisher Gesagtes komplett).
    func start(teil: @escaping (String) -> Void, fehler: @escaping (String) -> Void, bereit: @escaping () -> Void) {
        laeuft = true
        Task { @MainActor in
            do {
                let knoten = engine.inputNode
                let format = knoten.outputFormat(forBus: 0)
                try await vorbereiten(ein: format, teil: teil)
                guard laeuft else { aufraeumen(); return }
                knoten.removeTap(onBus: 0)
                knoten.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] puffer, _ in self?.fuettern(puffer) }
                engine.prepare()
                try engine.start()
                guard laeuft else { stop(); return }
                bereit()
            } catch {
                log("Hören (neu): \(error.localizedDescription)")
                aufraeumen()
                fehler(error.localizedDescription)
            }
        }
    }

    /// Alles außer dem Mikrofon: Sprachmodell, Analysierer, Ergebnisse. Auch für den Test mit einer Tondatei.
    func vorbereiten(ein format: AVAudioFormat, teil: @escaping (String) -> Void) async throws {
        laeuft = true
        let erste = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current)
        let deutsch = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "de-DE"))
        guard let sprache = erste ?? deutsch else { throw NSError(domain: "Pointy", code: 1, userInfo: [NSLocalizedDescriptionKey: "keine passende Sprache"]) }
        let tr = DictationTranscriber(locale: sprache, preset: .progressiveLongDictation)
        if let auftrag = try await AssetInventory.assetInstallationRequest(supporting: [tr]) {
            log("Hören: lade Sprachmodell \(sprache.identifier)")
            try await auftrag.downloadAndInstall()
        }
        guard let z = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [tr], considering: format) else {
            throw NSError(domain: "Pointy", code: 2, userInfo: [NSLocalizedDescriptionKey: "kein passendes Tonformat"])
        }
        let an = SpeechAnalyzer(modules: [tr])
        try await an.prepareToAnalyze(in: z)
        let (strom, zu) = AsyncStream<AnalyzerInput>.makeStream()
        ein = format; ziel = z
        wandler = format == z ? nil : AVAudioConverter(from: format, to: z)
        analysierer = an; zufluss = zu
        leser = Task { @MainActor in
            var fest = "", fluechtig = ""
            do {
                for try await r in tr.results {
                    let t = String(r.text.characters)
                    if r.isFinal { fest += t; fluechtig = "" } else { fluechtig = t }
                    self.gesamt = (fest + fluechtig).getrimmt
                    teil(self.gesamt)
                }
            } catch { log("Hören (neu): Ergebnisse brechen ab: \(error.localizedDescription)") }
        }
        try await an.start(inputSequence: strom)
        log("Hören: gestartet (neue Apple-Erkennung), Sprache \(sprache.identifier)")
    }

    /// Ein Stück Ton weiterreichen, bei Bedarf ins Format des Analysierers gewandelt.
    func fuettern(_ puffer: AVAudioPCMBuffer) {
        guard let zu = zufluss else { return }
        guard let wandler, let ein, let ziel else { zu.yield(AnalyzerInput(buffer: puffer)); return }
        let platz = AVAudioFrameCount(Double(puffer.frameLength) * ziel.sampleRate / ein.sampleRate) + 64
        guard let aus = AVAudioPCMBuffer(pcmFormat: ziel, frameCapacity: platz) else { return }
        var gegeben = false
        var fehler: NSError?
        wandler.convert(to: aus, error: &fehler) { _, status in
            if gegeben { status.pointee = .noDataNow; return nil }
            gegeben = true
            status.pointee = .haveData
            return puffer
        }
        if fehler == nil, aus.frameLength > 0 { zu.yield(AnalyzerInput(buffer: aus)) }
    }

    /// Mikrofon aus; der Analysierer schreibt den Rest noch fertig, `fertig` bekommt den ganzen Text (höchstens 3 s Wartezeit).
    func stop(fertig: ((String) -> Void)? = nil) {
        laeuft = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        zufluss?.finish(); zufluss = nil
        let an = analysierer; analysierer = nil
        let l = leser
        var gemeldet = false
        let melde = { [weak self] in
            guard !gemeldet else { return }
            gemeldet = true
            fertig?(self?.gesamt ?? "")
        }
        Task { @MainActor in
            try? await an?.finalizeAndFinishThroughEndOfInput()
            await l?.value
            melde()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { melde() }
    }

    private func aufraeumen() {
        laeuft = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        zufluss?.finish(); zufluss = nil
        leser?.cancel(); leser = nil
        let an = analysierer; analysierer = nil
        Task { await an?.cancelAndFinishNow() }
    }
}
