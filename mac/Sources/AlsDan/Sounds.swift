// Geluiden op de Mac: de geluiden van macOS zelf (de bibliotheek), eigen opnames en de computerstem. En de oren van de Mac:
// SoundAnalysis herkent soorten geluid (klappen, de deurbel, een hond) voor de trigger "De Mac hoort".
import AppKit
import AVFoundation
import SoundAnalysis

struct Sound: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var system: String? = nil    // een geluid van macOS (/System/Library/Sounds)
    var file: String? = nil      // eigen opname, in Recordings
    var text: String? = nil      // de computerstem zegt dit
    var voice: String? = nil     // welke stem
    var seconds: Double? = nil

    var kindLabel: String { system != nil ? "Van de Mac" : file != nil ? "Jouw opname" : "Computerstem" }

    static let library: [Sound] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return names.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
            .map { Sound(id: "sys:" + $0, name: $0, system: $0, seconds: NSSound(named: $0)?.duration) }
    }()
}

@MainActor final class Player {
    private var playing: [NSSound] = []
    private let synth = AVSpeechSynthesizer()

    static var voices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("nl") }.sorted { $0.name < $1.name } }

    func play(_ s: Sound, folder: URL) {
        if let t = s.text {
            let u = AVSpeechUtterance(string: t)
            u.voice = s.voice.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: "nl-NL")
            synth.speak(u)
            return
        }
        let sound = s.system.flatMap { NSSound(named: $0) } ?? s.file.flatMap { NSSound(contentsOf: folder.appendingPathComponent($0), byReference: true) }
        guard let sound else { return }
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)   // NSSound moet vastgehouden worden zolang hij speelt
        sound.play()
    }
}

@Observable @MainActor final class Recorder {
    var recording = false
    var level: Float = 0
    @ObservationIgnored private var rec: AVAudioRecorder?
    @ObservationIgnored private var meter: Timer?

    func start(to url: URL) async -> String? {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return "De Mac mag de microfoon niet gebruiken. Zet het aan in Systeeminstellingen > Privacy en beveiliging > Microfoon." }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return "Opnemen lukt niet." }
        r.isMeteringEnabled = true
        r.record()
        rec = r
        recording = true
        meter = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let r = self.rec else { return }
                r.updateMeters()
                self.level = max(0, (r.averagePower(forChannel: 0) + 50) / 50)
            }
        }
        return nil
    }

    func stop() -> Double {
        let t = rec?.currentTime ?? 0
        rec?.stop()
        rec = nil
        meter?.invalidate()
        recording = false
        level = 0
        return t
    }
}

// De oren van de Mac. Luistert alleen als `start` is aangeroepen (er is een regel met "De Mac hoort", of het scherm Live of
// Regels is open), en meldt wat hij hoort met hoe zeker hij is.
@Observable @MainActor final class MacEars: NSObject {
    nonisolated static let classes: [(id: String, label: String)] = [
        ("clapping", "klappen"), ("finger_snapping", "vingerknippen"), ("whistling", "fluiten"), ("laughter", "lachen"), ("speech", "praten"),
        ("shout", "roepen"), ("screaming", "gillen"), ("singing", "zingen"), ("cough", "hoesten"), ("sneeze", "niezen"), ("baby_crying", "een huilende baby"),
        ("dog_bark", "een blaffende hond"), ("cat_meow", "een miauwende kat"), ("door_bell", "de deurbel"), ("knock", "kloppen"),
        ("door_slam", "een deur die dichtslaat"), ("glass_breaking", "brekend glas"), ("keys_jangling", "rammelende sleutels"), ("typing", "typen"),
        ("alarm_clock", "een wekker"), ("siren", "een sirene"), ("bell", "een bel"), ("music", "muziek"), ("piano", "piano"), ("drum", "een trommel"),
        ("guitar", "een gitaar"), ("rain", "regen"), ("thunder", "onweer"), ("water", "stromend water"), ("whoosh_swoosh_swish", "een zoef"), ("thump_thud", "een bons"),
    ]
    nonisolated static func label(_ id: String?) -> String { classes.first { $0.id == id }?.label ?? id ?? "kies een geluid" }

    var listening = false
    var heard: (id: String, confidence: Double)?
    var level = 0   // hoe hard, 0-100, zoals de microfoon van de ESP32 het meet
    var problem: String?
    @ObservationIgnored var onHear: (String, Double) -> Void = { _, _ in }
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var analyzer: SNAudioStreamAnalyzer?
    @ObservationIgnored private var observer: Observer?
    @ObservationIgnored private let queue = DispatchQueue(label: "alsdan.ears")

    func start() async {
        guard !listening else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { problem = "De Mac mag de microfoon niet gebruiken. Zet het aan in Systeeminstellingen > Privacy en beveiliging > Microfoon."; return }
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { problem = "Deze Mac heeft geen microfoon."; return }
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            req.overlapFactor = 0.5
            let o = Observer(self)
            observer = o   // de analyzer houdt hem niet vast
            try analyzer.add(req, withObserver: o)
        } catch { problem = "Geluiden herkennen lukt niet op deze Mac."; return }
        self.analyzer = analyzer
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [queue, weak self] buf, when in
            let level = Self.loudness(buf)
            queue.async { analyzer.analyze(buf, atAudioFramePosition: when.sampleTime) }
            Task { @MainActor in self?.level = level }
        }
        do { try engine.start(); listening = true; problem = nil } catch { input.removeTap(onBus: 0); problem = "De microfoon start niet." }
    }

    func stop() {
        guard listening else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        analyzer = nil
        listening = false
        heard = nil
        level = 0
    }

    // Ongeveer de schaal van de ESP32: praten 30, een klap vlakbij 75 of meer.
    nonisolated static func loudness(_ buf: AVAudioPCMBuffer) -> Int {
        guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) }
        return Int(max(0, min(100, (20 * log10(max(peak, 1e-6)) + 60) * 100 / 60)))
    }

    fileprivate func got(_ id: String, _ c: Double) {
        heard = (id, c)
        onHear(id, c)
    }

    private final class Observer: NSObject, SNResultsObserving {
        weak var ears: MacEars?
        init(_ e: MacEars) { ears = e }
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let top = (result as? SNClassificationResult)?.classifications.first else { return }
            let (id, c) = (top.identifier, top.confidence)
            Task { @MainActor in self.ears?.got(id, c) }
        }
    }
}
