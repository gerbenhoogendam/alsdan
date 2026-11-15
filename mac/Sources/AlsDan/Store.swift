// Wat de app onthoudt: projecten, de inventaris en de geluiden. In ~/Library/Application Support/AlsDan/state.json; foto's en
// opnames in mapjes ernaast. Hier komt ook samen wat er gebeurt als een regel afgaat (op de ESP32 of in de oren van de Mac).
import SwiftUI
import AlsDanCore

struct Part: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var kind: Kind?                    // nil: iets anders, daar tekent de app (nog) geen schema voor
    var count = 1
    var photo: String? = nil           // in Photos
    var colors: [Int: String] = [:]    // per draadje (volgorde van Aansluiten) de kleur die echt aan het onderdeel zit
    var toBuy = false
}

// Het BOOT-knopje zit al op de ESP32: dat hoef je niet te kopen of aan te sluiten.
extension Device { var onBoard: Bool { kind == .button && pin == 0 } }

struct Event: Identifiable, Codable { var id = UUID(); let time: Date; let rule: String; var viaMac = false }

enum Screen: String, CaseIterable, Identifiable {
    case wish, rules, sounds, wiring, board, live, inventory
    var id: String { rawValue }
    var title: String { ["Wens", "Regels", "Geluiden", "Aansluiten", "Op de ESP32", "Live", "Inventaris"][Screen.allCases.firstIndex(of: self)!] }
    var symbol: String { ["sparkles", "arrow.triangle.branch", "waveform", "powerplug", "cpu", "waveform.path.ecg", "shippingbox"][Screen.allCases.firstIndex(of: self)!] }
    var tint: Color { [Ink.purple, Ink.orange, Ink.pink, Ink.green, Ink.cyan, Ink.red, Ink.indigo][Screen.allCases.firstIndex(of: self)!] }
}

@Observable @MainActor final class AppState {
    var projects: [Project] { didSet { save() } }
    var currentID: String { didSet { save(); board.dirty = true } }
    var parts: [Part] { didSet { save() } }
    var sounds: [Sound] { didSet { save() } }
    var events: [Event] = []   // vandaag; niet bewaard
    var screen = Screen.wish
    var thinking = false       // Claude is bezig
    var claudeProblem: String?

    let board = Board()
    let ears = MacEars()
    let recorder = Recorder()
    @ObservationIgnored let player = Player()
    @ObservationIgnored private var lastHeard: [String: Date] = [:]

    static let folder: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AlsDan")
        for sub in ["Photos", "Recordings"] { try? FileManager.default.createDirectory(at: u.appendingPathComponent(sub), withIntermediateDirectories: true) }
        return u
    }()
    static let photos = folder.appendingPathComponent("Photos"), recordings = folder.appendingPathComponent("Recordings")

    private struct Saved: Codable { var projects: [Project]; var current: String; var parts: [Part]; var sounds: [Sound] }

    init() {
        let s = (try? Data(contentsOf: AppState.folder.appendingPathComponent("state.json"))).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        let first = EXAMPLES[0].project()
        projects = s?.projects.isEmpty == false ? s!.projects : [first]
        currentID = s?.current ?? first.id
        parts = s?.parts ?? AppState.order
        sounds = s?.sounds ?? [Sound(name: "Wie ben jij?", text: "Wie ben jij?")]
        board.onFired = { [weak self] in self?.fired($0, viaMac: false) }
        ears.onHear = { [weak self] id, c in self?.heard(id, c) }
        board.start()
        listenIfNeeded()
    }

    // Wat er in de doos van de TinyTronics-bestelling zat (nov 2026), met de draadjes zoals ze aan de ring gesoldeerd zijn.
    static let order: [Part] = [
        Part(name: "Lampjes (blauw, rood, groen)", kind: .led, count: 3), Part(name: "Lichtring", kind: .ring, colors: [0: "oranje", 1: "rood", 2: "wit"]),
        Part(name: "Luidspreker 4 Ω", kind: .speaker), Part(name: "Bewegingsmelder", kind: .pir), Part(name: "Afstandssensor", kind: .tof),
        Part(name: "Microfoon INMP441", kind: .mic), Part(name: "Toverdraadje", kind: .touch), Part(name: "Weerstand 220 Ω", count: 10),
        Part(name: "Motor N20", kind: .motor, toBuy: true), Part(name: "Grote lamp", kind: .lamp, toBuy: true),
        Part(name: "Versterker MAX98357A", toBuy: true),
    ]

    private var saving: Task<Void, Never>?
    private func save() {
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let s = Saved(projects: projects, current: currentID, parts: parts, sounds: sounds)
            if let d = try? JSONEncoder().encode(s) { try? d.write(to: AppState.folder.appendingPathComponent("state.json"), options: .atomic) }
        }
    }

    var project: Project {
        get { projects.first { $0.id == currentID } ?? projects[0] }
        set {
            guard let i = projects.firstIndex(where: { $0.id == newValue.id }) else { return }
            if projects[i].devices != newValue.devices || projects[i].rules != newValue.rules { board.dirty = true }
            projects[i] = newValue
            listenIfNeeded()
        }
    }

    var allSounds: [Sound] { Sound.library + sounds }
    func sound(_ id: String?) -> Sound? { allSounds.first { $0.id == id } }

    // De kleuren uit de inventaris, per soort onderdeel: die tekent Aansluiten als je daar zelf niets koos.
    var owned: [Kind: [Int: String]] {
        var o: [Kind: [Int: String]] = [:]
        for p in parts where !p.toBuy { if let k = p.kind, o[k] == nil, !p.colors.isEmpty { o[k] = p.colors } }
        return o
    }
    func part(for k: Kind) -> Part? { parts.first { $0.kind == k && $0.photo != nil } ?? parts.first { $0.kind == k } }

    // ---- de drie ringen ----

    var thought: Double {
        let e = project.encode(), n = project.rules.count
        return n == 0 ? 0 : Double(e.rules.count + e.macRules.count) / Double(n)
    }
    var wiresToDo: [String] {
        let p = project.plan(owned: owned)
        return project.devices.filter { $0.kind.info.needs == nil }.flatMap { d in (p.rows[d.id] ?? []).filter { $0.key != nil }.map { "\(d.id):\($0.i)" } }
    }
    var wired: Double { let all = wiresToDo; return all.isEmpty ? 0 : Double(all.filter(project.doneWires.contains).count) / Double(all.count) }
    var tested: Double {
        let e = project.encode(), all = e.rules + e.macRules
        return all.isEmpty ? 0 : Double(all.filter(project.fired.contains).count) / Double(all.count)
    }

    // ---- projecten ----

    func newProject() {
        var p = Project(name: "Nieuw project")
        p.wish = ""
        projects.append(p)
        currentID = p.id
        screen = .wish
    }

    func load(_ ex: Example) {
        var p = ex.project()
        p.id = project.id
        p.wish = project.wish
        project = p
    }

    // ---- regels afgaan ----

    func fired(_ ruleID: String, viaMac: Bool) {
        events.append(Event(time: Date(), rule: ruleID, viaMac: viaMac))
        if events.count > 2000 { events.removeFirst(500) }
        if !project.fired.contains(ruleID) { project.fired.insert(ruleID) }
        guard let r = project.rules.first(where: { $0.id == ruleID }) else { return }
        // de geluiden in die regel speelt de Mac, na de WAITs die ervoor staan
        for (n, s) in r.steps.enumerated() where s.kind == .sound {
            guard let snd = sound(s.sound) else { continue }
            let delay = Project.delay(before: n, in: r.steps)
            Task { try? await Task.sleep(for: .seconds(delay)); self.player.play(snd, folder: AppState.recordings) }
        }
    }

    // Een regel nu laten gebeuren, alsof zijn ALS net gebeurde (testknop, en wat de Mac hoort).
    func run(_ r: Rule, viaMac: Bool = true) {
        let steps = r.steps.compactMap { s in s.kind == .sound ? nil : project.encode(s) }
        Task { await board.test(steps, project: project) }
        fired(r.id, viaMac: viaMac)
    }

    private func heard(_ id: String, _ c: Double) {
        guard c >= 0.7 else { return }
        for r in project.rules where r.trigger.kind == .HEARS && r.trigger.sound == id {
            if let t = lastHeard[r.id], Date().timeIntervalSince(t) < 2 { continue }   // één klap telt één keer
            lastHeard[r.id] = Date()
            run(r)
        }
    }

    var listenScreens = false { didSet { listenIfNeeded() } }
    func listenIfNeeded() {
        let need = (listenScreens || project.rules.contains { $0.trigger.kind == .HEARS }) && Snapshot.folder == nil
        if need && !ears.listening { Task { await ears.start() } } else if !need && ears.listening { ears.stop() }
    }

    // ---- Claude ----

    func makeRules() async {
        thinking = true
        claudeProblem = nil
        defer { thinking = false }
        do {
            let plan = try await Claude.plan(wish: project.wish, inventory: parts, sounds: allSounds)
            apply(plan)
        } catch { claudeProblem = error.localizedDescription }
    }

    func apply(_ plan: Claude.Plan) {
        var p = Project(name: project.name)
        p.id = project.id
        p.wish = project.wish
        p.summary = plan.summary
        p.questions = plan.questions
        p.shopping = plan.shopping
        if p.name == "Nieuw project", let first = plan.summary.split(separator: ".").first { p.name = String(first.prefix(32)) }
        var refs: [String: String] = [:]
        for d in plan.devices {
            guard let k = Kind(rawValue: d.kind), !(k.info.single && p.devices.contains { $0.kind == k }) else {
                if let k = Kind(rawValue: d.kind), let same = p.devices.first(where: { $0.kind == k }) { refs[d.ref] = same.id }
                continue
            }
            refs[d.ref] = p.addDevice(k, name: d.name.isEmpty ? nil : d.name).id
        }
        for r in plan.rules {
            guard let tk = TriggerKind(rawValue: r.trigger.kind) else { continue }
            let t = Trigger(tk, dev: refs[r.trigger.device], value: r.trigger.value > 0 ? r.trigger.value : nil,
                            sound: tk == .HEARS ? r.trigger.sound : nil)
            let steps: [Step] = r.steps.compactMap { s in
                if s.kind == "say" {
                    let snd = sounds.first { $0.text == s.sound } ?? Sound(name: s.sound, text: s.sound)
                    if !sounds.contains(snd) { sounds.append(snd) }
                    return Step(.sound, sound: snd.id)
                }
                guard let k = StepKind(rawValue: s.kind) else { return nil }
                if k == .sound { return allSounds.first { $0.name.lowercased() == s.sound.lowercased() }.map { Step(.sound, sound: $0.id) } }
                return Step(k, dev: refs[s.device], value: k.param != nil && s.value > 0 ? s.value : nil, color: s.color.hasPrefix("#") ? s.color : nil)
            }
            p.addRule(t, steps)
        }
        project = p
    }

    func answer(_ q: Question, _ a: String) async {
        project.wish += "\n\(q.question) \(a)"
        await makeRules()
    }
}
