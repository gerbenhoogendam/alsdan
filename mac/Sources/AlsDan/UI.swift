// De stijl: Werkbanks Telemetrie (panelen met de rechterbovenhoek schuin afgesneden, smalle Barlow-letters) in de kleuren van een
// testopstelling: warm wit of bijna zwart, één signaaloranje voor wat je kunt doen, kleine kapitalen in mono als bijschrift.
// Elke kleur heeft een lichte en een donkere versie; Weergave (menu Weergave of Instellingen) kiest, of de Mac.
import SwiftUI
import AlsDanCore

enum Ink {
    static let page = c(0xEEEAE3, 0x0E0D0C), card = c(0xFAF8F4, 0x1A1816), well = c(0xF2EEE7, 0x252220), line = c(0xDCD5CA, 0x36322D)
    static let text = c(0x1C1A17, 0xEFEBE4), dim = c(0x655F57, 0xA19B92)   // dim haalt 5:1 op de kaarten, dus goed leesbaar
    static let accent = c(0xEA4A1F, 0xFF6336)
    static let purple = c(0x8E3FC8, 0xBF5AF2), orange = c(0xD9730D, 0xFF9F0A), pink = c(0xD92650, 0xFF375F), green = c(0x1F9A47, 0x30D158)
    static let cyan = c(0x0B84B5, 0x64D2FF), red = c(0xD3322A, 0xFF453A), indigo = c(0x5552D1, 0x7D7AFF), yellow = c(0xF2B807, 0xFFD60A), blue = c(0x1F6FD6, 0x409CFF)
    static let ringThought = c(0xE5244F, 0xFF2E63), ringWired = c(0x5FA816, 0xA6F33A), ringTested = c(0x0FA3B5, 0x2CE5F2)

    // macOS kiest bij het tekenen de lichte of de donkere kleur
    private static func c(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        })
    }
}

enum Look: Int, CaseIterable {
    case system, light, dark
    var title: String { ["Zoals de Mac", "Licht", "Donker"][rawValue] }
    static func apply(_ v: Int) { NSApp.appearance = v == 1 ? NSAppearance(named: .aqua) : v == 2 ? NSAppearance(named: .darkAqua) : nil }
}

extension Color {
    init(hex: String) {
        let v = Int(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0), radix: 16) ?? 0
        self.init(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
    }
}

extension Font {
    // Barlow Semi Condensed voor tekst, Barlow Condensed Bold voor koppen en cijfers (de letters van Werkbank, OFL); mono blijft SF Mono.
    // Eén stap zwaarder dan gevraagd: Gerben wil het duidelijk en niet te dun, Barlow Regular is op het scherm te licht.
    static func ui(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        if design == .monospaced { return .system(size: size, weight: weight, design: .monospaced) }
        let s = size * 1.1   // Barlow is kleiner dan SF bij dezelfde maat
        if design == .rounded || [.bold, .heavy, .black].contains(weight) { return .custom("BarlowCondensed-Bold", size: s) }
        return .custom([.semibold, .medium].contains(weight) ? "BarlowSemiCondensed-SemiBold" : "BarlowSemiCondensed-Medium", size: s)
    }
    static func registerBarlow() {
        for u in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
    }
}

// Rechthoek met de rechterbovenhoek schuin afgesneden (uit Werkbank, Telemetrie).
struct ChamferedRect: InsettableShape {
    var cut: CGFloat = 12
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let f = rect.insetBy(dx: inset, dy: inset), c = min(cut, f.width / 2, f.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: f.minX, y: f.minY))
        p.addLine(to: CGPoint(x: f.maxX - c, y: f.minY))
        p.addLine(to: CGPoint(x: f.maxX, y: f.minY + c))
        p.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> ChamferedRect { var s = self; s.inset += amount; return s }
}

struct Card<C: View>: View {
    var border: Color? = nil
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: ChamferedRect(cut: 18))
            .overlay(ChamferedRect(cut: 18).strokeBorder(border ?? Ink.line, lineWidth: border == nil ? 1 : 1.5))
    }
}

struct Well<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.well, in: ChamferedRect(cut: 12))
    }
}

// Kop van een paneel: een oranje streepje en de titel in smalle kapitalen.
struct Head: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        HStack(spacing: 9) {
            Rectangle().fill(Ink.accent).frame(width: 3, height: 16)
            Text(title.uppercased()).font(.ui(size: 17, weight: .bold)).tracking(1.4).lineLimit(1)
        }
    }
}

// Klein bijschrift in kapitalen, zoals op een meetinstrument.
struct Caps: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text.uppercased()).font(.ui(size: 11, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Ink.dim) }
}

struct Tag: View {
    let text: String
    var color: Color { text == "ALS" ? Ink.yellow : text == "DAN" ? Ink.blue : Ink.purple }
    init(_ t: String) { text = t }
    var body: some View {
        Text(text).font(.ui(size: 12, weight: .bold)).tracking(1.2)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(text == "DAN" ? .white : .black.opacity(0.85))
            .background(color, in: ChamferedRect(cut: 5))
    }
}

struct Stat: View {
    let label: String, value: String, color: Color
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Caps(label)
            Text(value).font(.ui(size: 36, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
            if let sub { Caps(sub).lineLimit(1) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.well, in: ChamferedRect(cut: 12))
    }
}

struct Rings: View {
    let thought: Double, wired: Double, tested: Double
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            ring(thought, Ink.ringThought, 0)
            ring(wired, Ink.ringWired, 1)
            ring(tested, Ink.ringTested, 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Bedacht \(Int(thought * 100)) procent, aangesloten \(Int(wired * 100)) procent, getest \(Int(tested * 100)) procent")
    }
    func ring(_ v: Double, _ c: Color, _ n: CGFloat) -> some View {
        let w = size * 0.11, inset = n * (w + size * 0.02)
        return ZStack {
            Circle().stroke(c.opacity(0.25), lineWidth: w)
            Circle().trim(from: 0, to: max(0.001, v)).stroke(c, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(inset + w / 2)
        .animation(.spring(duration: 0.6), value: v)
    }
}

// Wat je kunt doen: signaaloranje, witte kapitalen.
struct Filled: ButtonStyle {
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: big ? 16 : 14, weight: .bold)).tracking(1).textCase(.uppercase)
            .padding(.horizontal, big ? 20 : 16).frame(minHeight: big ? 44 : 34)
            .foregroundStyle(.white)
            .background(Ink.accent.opacity(configuration.isPressed ? 0.8 : 1), in: ChamferedRect(cut: big ? 10 : 8))
            .modifier(Dim())
    }
}

// Een knop die nu niets kan doen, ziet er ook zo uit.
private struct Dim: ViewModifier {
    @Environment(\.isEnabled) var enabled
    func body(content: Content) -> some View { content.opacity(enabled ? 1 : 0.35) }
}

struct Soft: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 14, weight: .semibold)).tracking(0.8).textCase(.uppercase)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .foregroundStyle(Ink.text)
            .background(configuration.isPressed ? Ink.line : Ink.well, in: ChamferedRect(cut: 8))
            .overlay(ChamferedRect(cut: 8).strokeBorder(Ink.line))
            .modifier(Dim())
    }
}

struct Chip: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 14, weight: on ? .semibold : .regular))
            .padding(.horizontal, 14).frame(minHeight: 32)
            .foregroundStyle(on ? .white : Ink.text)
            .background(on ? Ink.accent : .clear, in: ChamferedRect(cut: 7))
            .overlay(ChamferedRect(cut: 7).strokeBorder(on ? Ink.accent : Ink.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// Een pagina: grote titel, een zin uitleg, en de inhoud. Alleen als het venster te klein is schuift de pagina.
struct Page<C: View>: View {
    let title: String, intro: String
    @ViewBuilder var content: C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    (Text(title) + Text(" /").foregroundStyle(Ink.accent)).font(.ui(size: 40, weight: .bold))
                    Text(intro).font(.ui(size: 15)).foregroundStyle(Ink.dim)
                }
                content
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.page)
    }
}

// Een plaatje van een onderdeel: jouw eigen foto uit de inventaris, anders de foto uit de app, anders het symbool.
struct PartPicture: View {
    let kind: Kind?
    var photo: String? = nil
    var size: CGFloat = 64
    var body: some View {
        // alleen de foto afsnijden: een symbool van meer laagjes binnen clipShape(ChamferedRect) tekent wit in plaats van in zijn kleur
        if let img = photo.flatMap({ NSImage(contentsOf: AppState.photos.appendingPathComponent($0)) }) ?? kind.flatMap(Art.photo) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(ChamferedRect(cut: size * 0.22))
        } else {
            Image(systemName: Art.symbol(kind)).font(.system(size: size * 0.42)).foregroundStyle(kind.map { Color(hex: $0.info.color) } ?? Ink.dim)
                .frame(width: size, height: size).background(Ink.well, in: ChamferedRect(cut: size * 0.22))
        }
    }
}

// De zin van een regel zoals het kind hem leest.
func sentence(_ t: Trigger, _ p: Project) -> String {
    if t.kind == .HEARS { return "De Mac hoort \(MacEars.label(t.sound))" }
    let who = p.device(t.dev)?.name ?? (t.kind.needsDevice ? "(kies een onderdeel)" : "")
    let v = t.value ?? t.kind.param?.def
    switch t.kind {
    case .START: return "De ESP32 gaat aan"
    case .EVERY: return v == 1 ? "Elke seconde" : "Elke \(num(v ?? 2)) seconden"
    default: return "\(who) \(t.kind.label)" + (t.kind.param.map { " \(num(v ?? 0)) \($0.unit)" } ?? "")
    }
}

func sentence(_ s: Step, _ p: Project, sound: (String?) -> Sound?) -> String {
    switch s.kind {
    case .wait: return "Wacht \(num(s.value ?? 1)) " + ((s.value ?? 1) == 1 ? "seconde" : "seconden")
    case .sound: return "De Mac speelt " + (sound(s.sound).map { "\u{201C}\($0.name)\u{201D}" } ?? "(kies een geluid)")
    default:
        let who = p.device(s.dev)?.name ?? "(kies een onderdeel)"
        if s.kind.defaultColor != nil { return "\(who) \(s.kind.label) \(colorName(s.color ?? s.kind.defaultColor!))" }
        return "\(who) \(s.kind.label)" + (s.kind.param.map { " \(num(s.value ?? $0.def)) \($0.unit)" } ?? "")
    }
}

func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }

// Een kleur in woorden, de dichtstbijzijnde uit een handvol.
func colorName(_ hex: String) -> String {
    let names: [(String, Int)] = [("rood", 0xff0000), ("oranje", 0xff6a00), ("geel", 0xffd000), ("groen", 0x00c853), ("lichtblauw", 0x00c8ff), ("blauw", 0x0040ff),
                                  ("paars", 0x8e44ad), ("roze", 0xff2d95), ("wit", 0xffffff), ("uit", 0x000000)]
    let v = Int(hex.dropFirst(), radix: 16) ?? 0
    func d(_ a: Int, _ b: Int) -> Int { [16, 8, 0].reduce(0) { let x = (a >> $1 & 255) - (b >> $1 & 255); return $0 + x * x } }
    return names.min { d($0.1, v) < d($1.1, v) }!.0
}
