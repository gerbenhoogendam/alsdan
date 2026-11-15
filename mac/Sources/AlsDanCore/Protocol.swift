// Wat de ESP32 terugzegt, en hoe je dat in gewone woorden zegt.
import Foundation

public enum Msg: Equatable, Sendable {
    case hi(fw: Int, chip: String)   // HI alsdan 2 ESP32-D0WD-V3
    case ok(String)                  // OK 3 onderdelen, 2 regels | OK (na X)
    case err(String)                 // ERR regel 2: … | ERR programma te lang | ERR onbekend: …
    case note(String)                // L <tekst>
    case sensor(dev: Int, value: Int)
    case fired(rule: Int)
    case other(String)               // opstartpraat van de ESP32 zelf

    public static func parse(_ line: String) -> Msg {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let w = parts.first ?? "", rest = parts.count > 1 ? parts[1] : ""
        let nums = rest.split(separator: " ").compactMap { Int($0) }
        switch w {
        case "HI":
            let a = rest.split(separator: " ").map(String.init)
            return .hi(fw: a.count > 1 ? Int(a[1]) ?? 1 : 1, chip: a.count > 2 ? a[2] : "ESP32")
        case "OK": return .ok(rest)
        case "ERR": return .err(rest)
        case "L": return .note(rest)
        case "S" where nums.count == 2: return .sensor(dev: nums[0], value: nums[1])
        case "E" where nums.count == 1: return .fired(rule: nums[0])
        default: return .other(line)
        }
    }
}

// Iets dat mis is, met wat je eraan doet. `fix` zegt welke knop de app erbij zet.
public struct Problem: Equatable, Sendable, Identifiable {
    public enum Fix: Sendable { case flash, reconnect, unplugRing, none }
    public let title: String, text: String, fix: Fix
    public var id: String { title }
}

public enum Plain {
    // Eén regel van de ESP32 (of van ons naar de ESP32, `out`) in gewone woorden.
    public static func say(_ line: String, out: Bool = false, deviceName: (Int) -> String? = { _ in nil }) -> String {
        if out {
            if line == "HELLO" { return "De Mac zegt hallo." }
            if line == "PROG" { return "De Mac stuurt je regels." }
            if line == "RUN" { return "De Mac zegt: zo, dat was alles." }
            if line.hasPrefix("X ") { return "De Mac test: " + line.dropFirst(2) }
            return "De Mac stuurt: " + line
        }
        switch Msg.parse(line) {
        case .hi(let fw, _): return "De ESP32 zegt hallo. Hij heeft firmware \(fw)."
        case .ok(let s) where s.isEmpty: return "Gedaan."
        case .ok(let s):
            let n = s.split(separator: " ").compactMap { Int($0) }
            return n.count == 2 ? "Gelukt: \(n[0]) onderdelen en \(n[1]) regels staan op de ESP32." : "Gelukt."
        case .err(let s):
            if s.hasPrefix("programma te lang") { return "Je programma is te lang voor de ESP32. Haal een paar regels weg." }
            if s.hasPrefix("onbekend") { return "De ESP32 kent een woord niet. Zijn firmware is waarschijnlijk te oud." }
            if s.hasPrefix("regel") { return "De ESP32 begrijpt een regel niet (\(s))." }
            return "De ESP32 zegt dat er iets mis is: " + s
        case .note(let s): return "De ESP32 meldt: " + s
        case .sensor(let d, let v): return "\(deviceName(d) ?? "Onderdeel \(d)") meet \(v)."
        case .fired(let r): return "Regel \(r + 1) ging af."
        case .other(let s):
            if s.contains("Brownout") { return "De ESP32 kreeg even te weinig stroom en startte opnieuw." }
            if s.hasPrefix("rst:") || s.hasPrefix("ets ") { return "De ESP32 start op." }
            if s.contains("Guru Meditation") || s.contains("Backtrace") { return "De ESP32 liep vast en start opnieuw." }
            return "De ESP32 zegt: " + s
        }
    }

    // Wat er mis is, uit de laatste regels van het logboek.
    public static func problems(_ lines: [String]) -> [Problem] {
        var found: [Problem] = []
        func add(_ p: Problem) { if !found.contains(p) { found.append(p) } }
        for l in lines {
            if l.contains("Brownout") {
                add(Problem(title: "Te weinig stroom", text: "De ESP32 kreeg te weinig stroom en startte opnieuw. Dat komt vaak door de lichtring die veel licht geeft, of door een dunne USB-kabel. Probeer een andere kabel of een andere USB-poort, of haal de lichtring even los.", fix: .unplugRing))
            } else if l.contains("afstandssensor niet gevonden") {
                add(Problem(title: "Afstandssensor niet gevonden", text: "De ESP32 ziet de afstandssensor niet. Kijk de vier draadjes na: plus op 3V3, min op GND, SDA op D21 en SCL op D22. Zitten SDA en SCL misschien omgedraaid?", fix: .none))
            } else if l.contains("microfoon start niet") {
                add(Problem(title: "De microfoon start niet", text: "Kijk de draadjes van de microfoon na: VDD op 3V3 (nooit op VIN), GND, SD op D35, SCK op D32 en WS op D33.", fix: .none))
            } else if l.hasPrefix("ERR onbekend") {
                add(Problem(title: "Firmware te oud", text: "De ESP32 kent een woord uit je regels niet. Zet de nieuwe firmware erop, daarna begrijpt hij het wel.", fix: .flash))
            } else if l.hasPrefix("ERR programma te lang") {
                add(Problem(title: "Te veel regels", text: "Er past niet meer op de ESP32. Haal een paar regels of stappen weg.", fix: .none))
            } else if l.contains("Guru Meditation") {
                add(Problem(title: "De ESP32 liep vast", text: "De ESP32 liep vast en startte opnieuw. Gebeurt het steeds? Haal de onderdelen een voor een los om te zien welke het doet.", fix: .none))
            } else if l.contains("Failed to connect") || l.contains("Wrong boot mode") {
                add(Problem(title: "Firmware zetten lukt niet", text: "De ESP32 wil niet luisteren. Houd het knopje BOOT op het bordje ingedrukt, klik nog een keer op Zet de firmware erop en laat het knopje los als de balk begint te lopen.", fix: .flash))
            } else if l.contains("Resource busy") || l.contains("Permission denied") {
                add(Problem(title: "Een ander programma gebruikt de ESP32", text: "Sluit Chrome (de web-app), de Arduino-app of een terminal die met de ESP32 praat, en verbind opnieuw.", fix: .reconnect))
            }
        }
        return found
    }
}
