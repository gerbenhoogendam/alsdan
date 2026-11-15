// Als-Dan: wat de app weet over de onderdelen, de triggers, de stappen en het programma voor de firmware
// (firmware/alsdan/alsdan.ino). Dezelfde regels als web/logic.js, zodat de web-app en de Mac-app hetzelfde sturen.
import Foundation

public let OUT_PINS = [2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33]
public let IN_PINS = OUT_PINS + [34, 35, 36, 39]
public let TOUCH_PINS = [4, 2, 15, 13, 12, 14, 27, 33, 32]

// De pinnen van het ESP32 DevKit V1 (30 pinnen), USB onder, antenne boven. Nummers als tekst, zodat '3V3' en 'GND' ertussen passen.
public let LEFT = ["EN", "36", "39", "34", "35", "32", "33", "25", "26", "27", "14", "12", "13", "GND", "VIN"]
public let RIGHT = ["23", "22", "1", "3", "21", "19", "18", "5", "17", "16", "4", "2", "15", "GND", "3V3"]
public let PIN_NAMES = [36: "VP", 39: "VN", 1: "TX0", 3: "RX0", 17: "TX2", 16: "RX2"]
public func pinName(_ p: Int) -> String { PIN_NAMES[p] ?? "D\(p)" }
public func pinName(_ p: String) -> String { Int(p).map(pinName) ?? p }
func D(_ p: Int?) -> String { p.map { "D\($0)" } ?? "?" }

// De kleuren van de jumperdraadjes.
public let WIRE_COLORS: [(name: String, hex: String)] = [("rood", "#e5484d"), ("zwart", "#222222"), ("geel", "#f2c200"), ("groen", "#1faa59"), ("blauw", "#2f7de1"),
                                                           ("wit", "#f7f7f7"), ("oranje", "#f58a1f"), ("bruin", "#8b5a2b"), ("paars", "#8e44ad"), ("grijs", "#9aa0a6")]
public func wireHex(_ name: String?) -> String? { WIRE_COLORS.first { $0.name == name }?.hex }

public struct WireSpec: Sendable {
    public let lab: String, pin: String, hint: String?, inline: String?
    init(_ lab: String, _ pin: String, _ hint: String? = nil, _ inline: String? = nil) { (self.lab, self.pin, self.hint, self.inline) = (lab, pin, hint, inline) }
}

public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
    case led, lamp, ring, speaker, motor, button, pir, tof, mic, touch
    public var id: String { rawValue }
    public var info: KindInfo { KindInfo.table[self]! }
}

public struct KindInfo: Sendable {
    public let label: String, color: String, type: String
    public var out = false
    public var pins: [Int] = []
    public var prefer: [Int] = []
    public var two = false, single = false
    public var fixed: [Int]? = nil
    public var fw = 1
    public var count: Int? = nil
    public var tests: [Step] = []
    public var needs: String? = nil      // eerst nodig, anders niet aansluiten
    public var must: String? = nil       // moet in het draadje
    public var colors: [String]? = nil   // zo zijn de draadjes aan het onderdeel gesoldeerd
    public var triggers: [TriggerKind] = []
    public var note = ""
    public var wiring: @Sendable (Device) -> [WireSpec] = { _ in [] }
    public var live: (@Sendable (Int) -> String)? = nil

    static let table: [Kind: KindInfo] = [
        .led: KindInfo(label: "Lampje", color: "#f6b800", type: "LED", out: true, pins: OUT_PINS, prefer: [2, 25, 26, 33, 32, 23, 19, 18, 13, 14, 27, 16, 17, 4],
                       tests: [Step(.on), Step(.off)],
                       note: "Het lange pootje is de plus. Een weerstand hoeft niet: de pin staat op de zachtste stand. D2 is ook het blauwe lampje op het bordje zelf.",
                       wiring: { [WireSpec("Lange pootje", D($0.pin)), WireSpec("Korte pootje", "GND")] }),
        .lamp: KindInfo(label: "Grote lamp", color: "#ff7a00", type: "LED", out: true, pins: OUT_PINS, prefer: [17, 16, 23, 19, 18],
                        tests: [Step(.on), Step(.off)], needs: "een MOSFET (IRLZ44N) en een weerstand van 2,2 Ω",
                        note: "Deze lamp trekt veel te veel stroom voor een pin van de ESP32. Zonder MOSFET ertussen gaat de ESP32 kapot.",
                        wiring: { [WireSpec("Linker pootje van de MOSFET (gate)", D($0.pin)), WireSpec("Rechter pootje van de MOSFET (source)", "GND"),
                                   WireSpec("Min van de lamp", "het middelste pootje van de MOSFET"), WireSpec("Plus van de lamp", "VIN", "met de weerstand ertussen")] }),
        .ring: KindInfo(label: "Lichtring", color: "#e040fb", type: "RING", out: true, pins: OUT_PINS, prefer: [16, 17, 13, 27, 14], count: 12,
                        tests: [Step(.color, color: "#ff0000"), Step(.rainbow), Step(.ringoff)], colors: ["oranje", "rood", "wit"],
                        note: "De draadjes zitten al aan de ring vast. Let op: bij deze ring is het rode draadje de min.",
                        wiring: { [WireSpec("Plus", "3V3"), WireSpec("Min", "GND"), WireSpec("Seintje", D($0.pin))] }),
        .speaker: KindInfo(label: "Luidspreker", color: "#00b894", type: "SPK", out: true, pins: OUT_PINS, prefer: [14, 27, 12, 13],
                           tests: [Step(.beep), Step(.tada)], must: "een weerstand van 220 Ω",
                           note: "Zonder weerstand niet aansluiten: daar kan de pin van de ESP32 niet tegen. Welk draadje waar zit maakt niet uit.",
                           wiring: { [WireSpec("Draadje 1", D($0.pin), nil, "een weerstand van 220 Ω"), WireSpec("Draadje 2", "GND")] }),
        .motor: KindInfo(label: "Motor", color: "#636e72", type: "MOT", out: true, pins: OUT_PINS, prefer: [18, 19, 23, 5, 25, 26], two: true,
                         tests: [Step(.fwd, value: 60), Step(.stop)], needs: "een motordriver",
                         note: "De motor mag nooit rechtstreeks aan de ESP32. Er moet een motordriver tussen (DRV8833, L9110S of TB6612).",
                         wiring: { [WireSpec("IN1 van de driver", D($0.pin)), WireSpec("IN2 van de driver", D($0.pin2)), WireSpec("VCC van de driver", "VIN"),
                                    WireSpec("GND van de driver", "GND"), WireSpec("De motor", "de twee uitgangen van de driver")] }),
        .button: KindInfo(label: "Knop", color: "#0984e3", type: "BTN", pins: [0] + IN_PINS, prefer: [0, 32, 35, 34, 26, 25], triggers: [.PRESS, .RELEASE],
                          note: "Het knopje BOOT op het bordje is ook gewoon een knop.",
                          wiring: { $0.pin == 0 ? [WireSpec("Niets aansluiten", "BOOT", "dit is het knopje op het bordje zelf")]
                                                : [WireSpec("Het ene pootje", D($0.pin)), WireSpec("Het andere pootje", "GND")] },
                          live: { $0 != 0 ? "Ingedrukt" : "Los" }),
        // op VIN: het bordje van de melder maakt er zelf 3,3 volt van, en 3V3 blijft vrij
        .pir: KindInfo(label: "Bewegingsmelder", color: "#d63031", type: "PIR", pins: IN_PINS, prefer: [27, 26, 25, 33, 32, 34, 35], triggers: [.MOTION, .STILL],
                       note: "Na het aanzetten heeft hij een halve minuut nodig om wakker te worden.",
                       wiring: { [WireSpec("Plus", "VIN"), WireSpec("Seintje", D($0.pin)), WireSpec("Min", "GND")] },
                       live: { $0 != 0 ? "Beweging!" : "Rustig" }),
        .tof: KindInfo(label: "Afstandssensor", color: "#6c5ce7", type: "TOF", single: true, fixed: [21, 22], triggers: [.NEAR, .FAR],
                       note: "De lettertjes staan op het sensorbordje zelf. XSHUT en GPIO1 blijven leeg.",
                       wiring: { _ in [WireSpec("VIN (plus)", "3V3"), WireSpec("GND (min)", "GND"), WireSpec("SDA (seintje)", "D21"), WireSpec("SCL (seintje)", "D22")] },
                       live: { $0 < 0 ? "Niets in zicht" : "\($0) cm" }),
        .mic: KindInfo(label: "Microfoon", color: "#e17055", type: "MIC", single: true, fixed: [32, 33, 35], fw: 2, triggers: [.LOUD],
                       note: "Alleen op 3V3, nooit op VIN: daar gaat de microfoon stuk van. Het pinnetje L/R blijft leeg.",
                       wiring: { _ in [WireSpec("VDD (plus)", "3V3"), WireSpec("GND (min)", "GND"), WireSpec("SD", "D35"), WireSpec("SCK", "D32"), WireSpec("WS", "D33")] },
                       live: { "Geluid \($0)" }),
        .touch: KindInfo(label: "Toverdraadje", color: "#00a8ff", type: "TCH", pins: TOUCH_PINS, prefer: [4, 13, 15, 12], triggers: [.TOUCH, .UNTOUCH],
                         note: "De ESP32 voelt je vinger door het draadje. Staat het al op aangeraakt zonder dat je iets doet? Stuur het programma nog een keer, dan meet hij de ruststand opnieuw.",
                         wiring: { [WireSpec("Het ene eind", D($0.pin), "het andere eind raak je aan; met aluminiumfolie eraan heb je een groter raakvlak")] },
                         live: { $0 != 0 ? "Aangeraakt!" : "Niet aangeraakt" }),
    ]
}

public struct Param: Sendable { public let unit: String, def: Double, min: Double, max: Double, step: Double }

// HEARS doet de Mac zelf: hij luistert met zijn eigen microfoon en stuurt de stappen als hij het geluid hoort.
public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case START, EVERY, PRESS, RELEASE, MOTION, STILL, NEAR, FAR, TOUCH, UNTOUCH, LOUD, HEARS
    public var label: String {
        switch self {
        case .START: "de ESP32 aangaat"
        case .EVERY: "er weer"
        case .PRESS: "wordt ingedrukt"
        case .RELEASE, .UNTOUCH: "wordt losgelaten"
        case .MOTION: "ziet beweging"
        case .STILL: "ziet niets meer bewegen"
        case .NEAR: "ziet iets dichterbij dan"
        case .FAR: "ziet niets meer binnen"
        case .TOUCH: "wordt aangeraakt"
        case .LOUD: "hoort iets harder dan"
        case .HEARS: "De Mac hoort"
        }
    }
    public var param: Param? {
        switch self {
        case .EVERY: Param(unit: "seconden om zijn", def: 2, min: 0.1, max: 3600, step: 0.1)
        case .NEAR, .FAR: Param(unit: "cm", def: 20, min: 2, max: 400, step: 1)
        case .LOUD: Param(unit: "(van 0 tot 100)", def: 60, min: 5, max: 100, step: 5)
        default: nil
        }
    }
    public var needsDevice: Bool { ![.START, .EVERY, .HEARS].contains(self) }
}

public enum StepKind: String, Codable, CaseIterable, Sendable {
    case on, off, blink, dim, color, spin, rainbow, ringoff, beep, tada, alarm, siren, oei, fwd, back, stop, wait, sound
    public var kinds: [Kind]? {
        switch self {
        case .on, .off, .blink, .dim: [.led, .lamp]
        case .color, .spin, .rainbow, .ringoff: [.ring]
        case .beep, .tada, .alarm, .siren, .oei: [.speaker]
        case .fwd, .back, .stop: [.motor]
        case .wait, .sound: nil
        }
    }
    public var label: String {
        switch self {
        case .on: "gaat aan"; case .off, .ringoff: "gaat uit"; case .blink: "gaat knipperen"; case .dim: "gaat aan op"
        case .color: "wordt"; case .spin: "draait rondjes in"; case .rainbow: "wordt een regenboog"
        case .beep: "piept"; case .tada: "speelt tada"; case .alarm: "speelt alarm"; case .siren: "speelt sirene"; case .oei: "speelt oei"
        case .fwd: "draait vooruit op"; case .back: "draait achteruit op"; case .stop: "stopt"
        case .wait: "wacht"; case .sound: "De Mac speelt"
        }
    }
    public var param: Param? {
        switch self {
        case .dim: Param(unit: "%", def: 30, min: 0, max: 100, step: 5)
        case .fwd, .back: Param(unit: "%", def: 100, min: 10, max: 100, step: 10)
        case .wait: Param(unit: "seconden", def: 1, min: 0.1, max: 10, step: 0.1)
        default: nil
        }
    }
    public var defaultColor: String? { self == .color ? "#ff2d95" : self == .spin ? "#00c8ff" : nil }

    func encode(_ i: Int, _ v: Double?, _ c: String?) -> String {
        let n = Int((v ?? param?.def ?? 0).rounded()), ms = Int(((v ?? param?.def ?? 0) * 1000).rounded())
        switch self {
        case .on: return "SET \(i) 100"
        case .off: return "SET \(i) 0"
        case .blink: return "BLINK \(i) 400"
        case .dim: return "SET \(i) \(n)"
        case .color: return "COLOR \(i) \(rgb(c ?? defaultColor!))"
        case .spin: return "SPIN \(i) \(rgb(c ?? defaultColor!))"
        case .rainbow: return "RAINBOW \(i)"
        case .ringoff: return "COLOR \(i) 0 0 0"
        case .beep: return "BEEP \(i) 880 150"
        case .tada: return "TUNE \(i) 0"
        case .alarm: return "TUNE \(i) 1"
        case .siren: return "TUNE \(i) 2"
        case .oei: return "TUNE \(i) 3"
        case .fwd: return "MOTOR \(i) \(n)"
        case .back: return "MOTOR \(i) -\(n)"
        case .stop: return "MOTOR \(i) 0"
        case .wait: return "WAIT \(ms)"
        case .sound: return "WAIT 0"   // het geluid speelt de Mac; dit houdt de regel in het programma, zodat de ESP32 meldt dat hij afgaat
        }
    }
}

public func rgb(_ hex: String) -> String {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    let v = Int(h, radix: 16) ?? 0
    return "\(v >> 16 & 255) \(v >> 8 & 255) \(v & 255)"
}

public struct Device: Codable, Identifiable, Hashable, Sendable {
    public var id: String, kind: Kind, name: String
    public var pin: Int? = nil, pin2: Int? = nil
    public var colors: [Int: String] = [:]   // de kleur die de gebruiker koos, per draadje
    public init(id: String, kind: Kind, name: String) { (self.id, self.kind, self.name) = (id, kind, name) }
}

public struct Trigger: Codable, Hashable, Sendable {
    public var kind: TriggerKind, dev: String? = nil, value: Double? = nil
    public var sound: String? = nil   // HEARS: welk geluid de Mac moet horen
    public init(_ kind: TriggerKind, dev: String? = nil, value: Double? = nil, sound: String? = nil) { (self.kind, self.dev, self.value, self.sound) = (kind, dev, value, sound) }
}

public struct Step: Codable, Hashable, Sendable {
    public var kind: StepKind, dev: String? = nil, value: Double? = nil, color: String? = nil
    public var sound: String? = nil   // .sound: welk geluid uit de bibliotheek
    public init(_ kind: StepKind, dev: String? = nil, value: Double? = nil, color: String? = nil, sound: String? = nil) {
        (self.kind, self.dev, self.value, self.color, self.sound) = (kind, dev, value, color, sound)
    }
}

public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id: String, trigger: Trigger, steps: [Step]
    public init(id: String, trigger: Trigger, steps: [Step]) { (self.id, self.trigger, self.steps) = (id, trigger, steps) }
}

public struct Question: Codable, Hashable, Sendable { public var question: String, answers: [String] }

public struct Wire: Hashable, Sendable {
    public let i: Int, lab: String, pin: String, hint: String?, inline: String?
    public let num: Int?, esp: String, name: String?, color: String?
    public var key: String? = nil   // waar hij op het bordje komt: het pinnummer, '3V3', 'VIN', 'GND:L' of 'GND:R'
}

public struct Encoded: Sendable {
    public let text: String
    public let rules: [String]      // de regels die meegingen, in de volgorde die de firmware in `E <n>` gebruikt
    public let skipped: [String]    // nog niet af
    public let macRules: [String]   // ALS De Mac hoort …: die doet de Mac zelf
}

public struct Project: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var wish = ""
    public var summary = ""
    public var nextId = 1
    public var devices: [Device] = []
    public var rules: [Rule] = []
    public var questions: [Question] = []
    public var shopping: [String] = []
    public var doneWires: Set<String> = []   // "d3:1": dat draadje zit erin
    public var fired: Set<String> = []       // regels die al een keer afgingen
    public init(name: String) { self.name = name }

    public func device(_ id: String?) -> Device? { devices.first { $0.id == id } }

    public func usedPins(except: String? = nil) -> [Int: Device] {
        var used: [Int: Device] = [:]
        for d in devices where d.id != except {
            for p in d.kind.info.fixed ?? [d.pin, d.pin2].compactMap({ $0 }) { used[p] = d }
        }
        return used
    }

    public func freePin(_ kind: Kind, except: String? = nil, avoid: [Int] = []) -> Int? {
        let k = kind.info, used = usedPins(except: except)
        return (k.prefer + k.pins).first { used[$0] == nil && !avoid.contains($0) }
    }

    @discardableResult public mutating func addDevice(_ kind: Kind, name: String? = nil) -> Device {
        let k = kind.info
        let same = devices.filter { $0.kind == kind }.count
        var d = Device(id: "d\(nextId)", kind: kind, name: name ?? (same > 0 ? "\(k.label) \(same + 1)" : k.label))
        nextId += 1
        if !k.pins.isEmpty { d.pin = freePin(kind) }
        if k.two { d.pin2 = freePin(kind, avoid: [d.pin].compactMap { $0 }) }
        devices.append(d)
        // een onderdeel met vaste pinnen: wie daar al op zat verhuist naar een vrije pin
        if let fixed = k.fixed {
            for i in devices.indices where devices[i].id != d.id {
                for key in [\Device.pin, \Device.pin2] where devices[i][keyPath: key].map(fixed.contains) == true {
                    devices[i][keyPath: key] = freePin(devices[i].kind, except: devices[i].id, avoid: [devices[i].pin, devices[i].pin2].compactMap { $0 })
                }
            }
        }
        return d
    }

    @discardableResult public mutating func addRule(_ trigger: Trigger = Trigger(.START), _ steps: [Step] = []) -> Rule {
        let r = Rule(id: "r\(nextId)", trigger: trigger, steps: steps)
        nextId += 1
        rules.append(r)
        return r
    }

    public mutating func removeDevice(_ id: String) {
        devices.removeAll { $0.id == id }
        doneWires = doneWires.filter { !$0.hasPrefix(id + ":") }
    }

    // Elk draadje met zijn twee kanten: `lab` op het onderdeel, `esp` op het bordje. Kleur: wat de gebruiker hier koos, anders wat
    // in de inventaris staat (`owned`), anders hoe het onderdeel gesoldeerd is, anders de gewoonte (rood plus, zwart min, geel, groen
    // en blauw seintjes). Zonder kleur gaat het draadje niet naar de ESP32.
    public static func wires(_ d: Device, owned: [Int: String] = [:]) -> [Wire] {
        let k = d.kind.info
        var signals = 0
        return k.wiring(d).enumerated().map { i, w in
            let num = w.pin.hasPrefix("D") ? Int(w.pin.dropFirst()) : nil
            var usual: String? = nil
            if num != nil { usual = ["geel", "groen", "blauw"][signals % 3]; signals += 1 }
            else if w.pin == "GND" { usual = "zwart" }
            else if w.pin == "3V3" || w.pin == "VIN" { usual = "rood" }
            let soldered = k.colors.flatMap { i < $0.count ? $0[i] : nil }
            let name = usual == nil ? nil : [d.colors[i], owned[i], soldered].compactMap { $0 }.first { wireHex($0) != nil } ?? usual
            return Wire(i: i, lab: w.lab, pin: w.pin, hint: w.hint, inline: w.inline, num: num, esp: num.map(pinName) ?? w.pin, name: name, color: wireHex(name))
        }
    }

    // Welke pin elk draadje krijgt en wie er op elke pin zit. Van achteren gezien staat de rij van D23 links. GND zit er twee keer op:
    // een onderdeel krijgt de GND aan zijn eigen kant, is die bezet dan de andere, en pas als beide bezet zijn wordt er gedeeld.
    public func plan(owned: [Kind: [Int: String]] = [:]) -> (rows: [String: [Wire]], users: [String: [Device]]) {
        var taken = ["L": 0, "R": 0], rows: [String: [Wire]] = [:], users: [String: [Device]] = [:]
        for d in devices {
            let mine = Project.wires(d, owned: owned[d.kind] ?? [:])
            let own = mine.first { $0.num != nil }
            let side = own.map { !RIGHT.contains(String($0.num!)) } == true ? "R" : "L", other = side == "L" ? "R" : "L"
            rows[d.id] = mine.map { w in
                guard w.color != nil else { return w }
                var w = w
                var key = w.num.map(String.init) ?? w.pin
                if w.pin == "GND" {
                    let s = taken[side] == 0 ? side : taken[other] == 0 ? other : side
                    taken[s]! += 1
                    key = "GND:" + s
                }
                users[key, default: []].append(d)
                w.key = key
                return w
            }
        }
        return (rows, users)
    }

    public static func devicePins(_ d: Device) -> [Int] {
        d.kind.info.fixed ?? (d.kind == .ring ? [d.pin, d.kind.info.count] : d.kind == .motor ? [d.pin, d.pin2] : [d.pin]).compactMap { $0 }
    }

    func index(_ id: String?) -> Int { devices.firstIndex { $0.id == id } ?? -1 }

    // Het programma zoals de firmware het leest. Regels zonder trigger of zonder geldige stappen gaan niet mee.
    public func encode() -> Encoded {
        var lines = ["PROG"]
        for (i, d) in devices.enumerated() {
            lines.append(("D \(i) \(d.kind.info.type) " + Project.devicePins(d).map(String.init).joined(separator: " ")).trimmingCharacters(in: .whitespaces))
        }
        var sent: [String] = [], skipped: [String] = [], mac: [String] = []
        for r in rules {
            let steps = r.steps.compactMap { encode($0) }
            if r.trigger.kind == .HEARS {
                if r.trigger.sound?.isEmpty == false && !steps.isEmpty { mac.append(r.id) } else { skipped.append(r.id) }
                continue
            }
            guard let trig = encode(r.trigger), !steps.isEmpty else { skipped.append(r.id); continue }
            lines.append("R \(trig) ; " + steps.joined(separator: " ; "))
            sent.append(r.id)
        }
        lines.append("RUN")
        return Encoded(text: lines.joined(separator: "\n") + "\n", rules: sent, skipped: skipped, macRules: mac)
    }

    func encode(_ t: Trigger) -> String? {
        let i = index(t.dev), v = t.value ?? t.kind.param?.def ?? 0
        if t.kind.needsDevice && i < 0 { return nil }
        switch t.kind {
        case .START: return "START"
        case .EVERY: return "EVERY \(Int((v * 1000).rounded()))"
        case .NEAR, .FAR, .LOUD: return "\(t.kind.rawValue) \(i) \(Int(v.rounded()))"
        case .HEARS: return nil
        default: return "\(t.kind.rawValue) \(i)"
        }
    }

    public func encode(_ s: Step) -> String? {
        var i = -1
        if let kinds = s.kind.kinds {
            i = index(s.dev)
            if i < 0 || !kinds.contains(devices[i].kind) { return nil }
        }
        if s.kind == .sound && (s.sound ?? "").isEmpty { return nil }
        return s.kind.encode(i, s.value, s.color)
    }

    // Hoeveel seconden na het afgaan van de regel stap `n` begint: de WAITs ervoor bij elkaar (de firmware wacht hooguit 10 s per WAIT).
    public static func delay(before n: Int, in steps: [Step]) -> Double {
        steps.prefix(n).filter { $0.kind == .wait }.reduce(0) { $0 + min($1.value ?? 1, 10) }
    }
}

// ---- voorbeelden ----------------------------------------------------------

// devices: (soort, pin?, naam?); rules: ((trigger, onderdeel-nummer?, waarde?), [(stap, onderdeel-nummer?, waarde of kleur?)])
public struct Example: @unchecked Sendable {
    public let name: String
    let devices: [(Kind, Int?, String?)]
    let rules: [((TriggerKind, Int?, Double?), [(StepKind, Int?, Any?)])]
}

public let EXAMPLES: [Example] = [
    Example(name: "Knop en lampje", devices: [(.button, 0, "Knop BOOT"), (.led, 2, "Blauw lampje")],
            rules: [((.PRESS, 0, nil), [(.on, 1, nil), (.wait, nil, 1.0), (.off, 1, nil)])]),
    Example(name: "Knipperlicht", devices: [(.led, 2, "Blauw lampje")], rules: [((.START, nil, nil), [(.blink, 0, nil)])]),
    Example(name: "Inbrekersalarm", devices: [(.pir, 27, nil), (.ring, 16, nil), (.speaker, 14, nil)],
            rules: [((.MOTION, 0, nil), [(.spin, 1, "#ff0000"), (.alarm, 2, nil)]), ((.STILL, 0, nil), [(.ringoff, 1, nil)])]),
    Example(name: "Afstandsmeter", devices: [(.tof, nil, nil), (.ring, 16, nil), (.speaker, 14, nil)],
            rules: [((.NEAR, 0, 20), [(.color, 1, "#ff6a00"), (.beep, 2, nil)]), ((.FAR, 0, 20), [(.color, 1, "#00c853")])]),
    Example(name: "Klap voor licht", devices: [(.mic, nil, nil), (.ring, 16, nil)],
            rules: [((.LOUD, 0, 60), [(.rainbow, 1, nil), (.wait, nil, 3.0), (.ringoff, 1, nil)])]),
    Example(name: "Toverstaf", devices: [(.touch, 4, nil), (.ring, 16, nil), (.speaker, 14, nil)],
            rules: [((.TOUCH, 0, nil), [(.rainbow, 1, nil), (.tada, 2, nil)]), ((.UNTOUCH, 0, nil), [(.ringoff, 1, nil)])]),
    Example(name: "Alles van de bestelling", devices: [(.button, 0, "Knop BOOT"), (.led, 2, "Blauw lampje"), (.led, 25, "Rood lampje"), (.led, 26, "Groen lampje"),
                                                       (.ring, 16, nil), (.speaker, 14, nil), (.pir, 27, nil), (.tof, nil, nil), (.touch, 4, nil), (.motor, 18, nil), (.lamp, 17, nil)],
            rules: [((.PRESS, 0, nil), [(.on, 1, nil), (.tada, 5, nil), (.wait, nil, 1.0), (.off, 1, nil)]), ((.MOTION, 6, nil), [(.on, 2, nil)]), ((.STILL, 6, nil), [(.off, 2, nil)]),
                    ((.NEAR, 7, 30), [(.color, 4, "#ff6a00")]), ((.FAR, 7, 30), [(.ringoff, 4, nil)]),
                    ((.TOUCH, 8, nil), [(.on, 3, nil), (.fwd, 9, 80.0), (.wait, nil, 2.0), (.stop, 9, nil), (.off, 3, nil)])]),
]

extension Example {
    public func project() -> Project {
        var m = Project(name: name)
        var ids: [String] = []
        for (kind, pin, name) in devices {
            let d = m.addDevice(kind)
            let i = m.devices.firstIndex { $0.id == d.id }!
            if let pin { m.devices[i].pin = pin; if kind.info.two { m.devices[i].pin2 = pin + 1 } }
            if let name { m.devices[i].name = name }
            ids.append(d.id)
        }
        for ((tk, td, tv), steps) in rules {
            m.addRule(Trigger(tk, dev: td.map { ids[$0] }, value: tv),
                      steps.map { sk, sd, sv in Step(sk, dev: sd.map { ids[$0] }, value: sv as? Double, color: sv as? String) })
        }
        return m
    }
}
