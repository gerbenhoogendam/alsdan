// Stap 2, Regels: elke regel is ALS iets gebeurt, DAN doen de onderdelen dit. Alles is aan te klikken en te veranderen.
import SwiftUI
import AlsDanCore

struct RulesView: View {
    @Environment(AppState.self) var app
    @State private var example: Example?

    var body: some View {
        let p = app.project, e = p.encode(), all = e.rules + e.macRules
        let buy = p.devices.filter { d in !d.onBoard && !app.parts.contains { $0.kind == d.kind && !$0.toBuy } }
        Page(title: "Regels", intro: "Zo werkt je project. Klik op iets om het te veranderen.") {
            HStack(spacing: 10) {
                Stat(label: "Regels", value: "\(p.rules.count)", color: Ink.orange, sub: e.skipped.isEmpty ? "allemaal af" : "\(e.skipped.count) nog niet af")
                Stat(label: "Onderdelen", value: "\(p.devices.count)", color: Ink.green, sub: buy.isEmpty ? "alles in huis" : "\(buy.count) nog kopen")
                Stat(label: "Geluiden", value: "\(p.rules.flatMap(\.steps).filter { $0.kind == .sound }.count)", color: Ink.pink, sub: "speelt de Mac")
                Stat(label: "Getest", value: "\(all.filter(p.fired.contains).count) van \(all.count)", color: Ink.cyan, sub: "op de echte ESP32")
            }
            ForEach(Array(p.rules.enumerated()), id: \.element.id) { i, r in
                RuleCard(rule: binding(r.id), number: i + 1, skipped: e.skipped.contains(r.id))
            }
            if p.rules.isEmpty { Text("Nog geen regels. Maak er een, kies een voorbeeld, of vertel je wens aan Claude.").foregroundStyle(Ink.dim) }
            HStack(spacing: 10) {
                Button { newRule() } label: { Label("Nieuwe regel", systemImage: "plus") }.buttonStyle(Filled())
                Menu("Voorbeeld") { ForEach(EXAMPLES, id: \.name) { ex in Button(ex.name) { example = ex } } }.fixedSize()
                Button { app.screen = .wish } label: { Label("Vraag Claude", systemImage: "sparkles") }.buttonStyle(Soft())
            }
            DisclosureGroup("Zo leest de ESP32 het") {
                Text(e.text).font(.ui(size: 12, design: .monospaced)).foregroundStyle(Ink.dim).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            .foregroundStyle(Ink.dim)
        }
        .confirmationDialog("Dit vervangt je regels en onderdelen door het voorbeeld.", isPresented: Binding(get: { example != nil }, set: { if !$0 { example = nil } })) {
            Button("Vervang door \(example?.name ?? "")") { if let ex = example { app.load(ex) } }
        }
        .onAppear { app.listenScreens = true }
        .onDisappear { app.listenScreens = false }
    }

    func binding(_ id: String) -> Binding<Rule> {
        Binding(get: { app.project.rules.first { $0.id == id } ?? Rule(id: id, trigger: Trigger(.START), steps: []) },
                set: { nv in if let i = app.project.rules.firstIndex(where: { $0.id == id }) { app.project.rules[i] = nv } })
    }

    func newRule() {
        let p = app.project
        let dev = p.devices.first { !$0.kind.info.triggers.isEmpty }
        let out = p.devices.first { $0.kind.info.out }
        let step = out.flatMap { d in StepKind.allCases.first { $0.kinds?.contains(d.kind) == true }.map { Step($0, dev: d.id) } } ?? Step(.wait)
        app.project.addRule(dev.map { Trigger($0.kind.info.triggers[0], dev: $0.id) } ?? Trigger(.START), [step])
    }
}

struct RuleCard: View {
    @Environment(AppState.self) var app
    @Binding var rule: Rule
    let number: Int, skipped: Bool

    var body: some View {
        let p = app.project
        let today = app.events.filter { $0.rule == rule.id && Calendar.current.isDateInToday($0.time) }.count
        Card {
            HStack(spacing: 12) {
                Text("\(number)").font(.ui(size: 15, weight: .black, design: .rounded)).foregroundStyle(.black.opacity(0.85))
                    .frame(width: 30, height: 30).background(Ink.orange, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence(rule.trigger, p)).font(.ui(size: 15, weight: .bold))
                    Text(today > 0 ? "\(today) keer afgegaan vandaag" : p.fired.contains(rule.id) ? "getest" : "nog niet getest").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                }
                Spacer()
                Button { app.run(rule) } label: { Label("Probeer", systemImage: "play.fill") }.buttonStyle(Soft())
                    .help("Doe alsof de ALS net gebeurde: de ESP32 doet de stappen nu").disabled(!app.board.connected && !rule.steps.contains { $0.kind == .sound })
                Button(role: .destructive) { app.project.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Regel weg")
            }
            HStack(spacing: 10) {
                Tag("ALS")
                Picker("Als", selection: triggerTag) { ForEach(triggerOptions(p), id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().fixedSize()
                if rule.trigger.kind == .HEARS {
                    Picker("Geluid", selection: Binding(get: { rule.trigger.sound ?? "clapping" }, set: { rule.trigger.sound = $0 })) {
                        ForEach(MacEars.classes, id: \.id) { Text($0.label).tag($0.id) }
                    }.labelsHidden().fixedSize()
                } else if let param = rule.trigger.kind.param {
                    NumberField(value: $rule.trigger.value, param: param)
                }
            }
            if rule.trigger.kind == .HEARS || rule.trigger.kind == .LOUD { micChoice(p) }
            ForEach(Array(rule.steps.enumerated()), id: \.offset) { i, _ in
                HStack(spacing: 10) {
                    Tag("DAN")
                    StepEditor(step: Binding(get: { i < rule.steps.count ? rule.steps[i] : Step(.wait) }, set: { if i < rule.steps.count { rule.steps[i] = $0 } }))
                    Button { rule.steps.remove(at: i) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Stap weg")
                }
            }
            Button { rule.steps.append(rule.steps.last ?? Step(.wait)) } label: { Label("Stap erbij", systemImage: "plus") }.buttonStyle(.borderless).foregroundStyle(Ink.cyan)
            if skipped {
                Text(rule.trigger.kind == .HEARS && rule.trigger.sound == nil ? "Kies welk geluid de Mac moet horen." : "Deze regel gaat nog niet mee: kies een stap, en een onderdeel dat bestaat.")
                    .font(.ui(size: 14)).foregroundStyle(Ink.orange)
            }
        }
    }

    var triggerTag: Binding<String> {
        Binding(get: { "\(rule.trigger.kind.rawValue)|\(rule.trigger.dev ?? "")" }, set: { tag in
            let parts = tag.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let k = TriggerKind(rawValue: parts[0]) else { return }
            rule.trigger = Trigger(k, dev: parts[1].isEmpty ? nil : parts[1], sound: k == .HEARS ? "clapping" : nil)
        })
    }

    func triggerOptions(_ p: Project) -> [(String, String)] {
        var o = [("START|", "De ESP32 gaat aan"), ("EVERY|", "Elke zoveel seconden")]
        for d in p.devices { for t in d.kind.info.triggers { o.append(("\(t.rawValue)|\(d.id)", "\(d.name) \(t.label)")) } }
        o.append(("HEARS|", "De Mac hoort een geluid"))
        let now = "\(rule.trigger.kind.rawValue)|\(rule.trigger.dev ?? "")"
        if !o.contains(where: { $0.0 == now }) { o.insert((now, "kies…"), at: 0) }
        return o
    }

    // Twee soorten luisteren: hoe hard (de microfoon op de ESP32) of wat voor geluid (de Mac luistert, alleen met de kabel eraan).
    func micChoice(_ p: Project) -> some View {
        let hears = rule.trigger.kind == .HEARS
        let micIndex = p.devices.firstIndex { $0.kind == .mic }
        let now = micIndex.flatMap { app.board.values[$0] } ?? app.ears.level
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Luisteren", selection: Binding(get: { hears }, set: { want in
                if want { rule.trigger = Trigger(.HEARS, sound: "clapping") } else {
                    let mic = app.project.devices.first { $0.kind == .mic } ?? app.project.addDevice(.mic)
                    rule.trigger = Trigger(.LOUD, dev: mic.id, value: 60)
                }
            })) {
                Text("Hoe hard").tag(false)
                Text("Wat voor geluid").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            Text(hears ? "De Mac luistert mee met zijn eigen microfoon. Dat werkt alleen als de ESP32 aan de Mac hangt."
                       : "Nu: \(now) · praten is ongeveer 30, een klap vlakbij 75 of meer")
                .font(.ui(size: 12)).foregroundStyle(Ink.dim)
        }
        .padding(.leading, 44)
    }
}

struct StepEditor: View {
    @Environment(AppState.self) var app
    @Binding var step: Step

    var body: some View {
        let p = app.project
        HStack(spacing: 10) {
            Picker("Dan", selection: tag) { ForEach(options(p), id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().fixedSize()
            if step.kind == .sound {
                Picker("Geluid", selection: Binding(get: { step.sound ?? "" }, set: { step.sound = $0 })) {
                    if step.sound == nil { Text("kies…").tag("") }
                    ForEach(app.allSounds) { Text($0.name).tag($0.id) }
                }.labelsHidden().fixedSize()
                if let s = app.sound(step.sound) { Button { app.player.play(s, folder: AppState.recordings) } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless) }
            } else if let def = step.kind.defaultColor {
                ColorPicker("Kleur", selection: Binding(get: { Color(hex: step.color ?? def) }, set: { step.color = hex($0) }), supportsOpacity: false).labelsHidden()
                Text(colorName(step.color ?? def)).foregroundStyle(Ink.dim)
            } else if let param = step.kind.param {
                NumberField(value: $step.value, param: param)
            }
        }
    }

    var tag: Binding<String> {
        Binding(get: { "\(step.kind.rawValue)|\(step.dev ?? "")" }, set: { t in
            let parts = t.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if let k = StepKind(rawValue: parts[0]) { step = Step(k, dev: parts[1].isEmpty ? nil : parts[1]) }
        })
    }

    func options(_ p: Project) -> [(String, String)] {
        var o: [(String, String)] = []
        for d in p.devices { for k in StepKind.allCases where k.kinds?.contains(d.kind) == true { o.append(("\(k.rawValue)|\(d.id)", "\(d.name) \(k.label)")) } }
        o += [("wait|", "Wacht"), ("sound|", "De Mac speelt een geluid")]
        let now = "\(step.kind.rawValue)|\(step.dev ?? "")"
        if !o.contains(where: { $0.0 == now }) { o.insert((now, "kies…"), at: 0) }
        return o
    }
}

struct NumberField: View {
    @Binding var value: Double?
    let param: Param
    var body: some View {
        let v = Binding<Double>(get: { value ?? param.def }, set: { value = min(max($0, param.min), param.max) })
        HStack(spacing: 6) {
            TextField("", value: v, format: .number.precision(.fractionLength(0...1))).frame(width: 64).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
            Stepper("", value: v, in: param.min...param.max, step: param.step).labelsHidden()
            Text(param.unit).foregroundStyle(Ink.dim)
        }
    }
}

func hex(_ c: Color) -> String {
    let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
    return String(format: "#%02x%02x%02x", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
}

