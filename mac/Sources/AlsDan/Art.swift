// Hoe elk onderdeel eruitziet in het aansluitplaatje: een foto van het echte onderdeel (uit Gerbens foto's, web/parts/) of een
// tekening, in eigen maten, met per draadje (volgorde van KindInfo.wiring) het punt waar dat draadje begint. Zelfde als web/parts.js.
import SwiftUI
import AlsDanCore

enum Art {
    struct Info {
        let w: CGFloat, h: CGFloat
        var photo: Kind? = nil
        var pins: [CGPoint] = []
        var marks: [(CGPoint, String)] = []
        var hold: String? = nil
    }

    static func info(_ d: Device) -> Info? {
        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: y) }
        switch d.kind {
        case .pir: return Info(w: 530, h: 280, photo: .pir, pins: [p(525, 157), p(525, 108), p(525, 57)], hold: "Wit bolletje links, zwart blokje onderaan.")
        case .ring: return Info(w: 660, h: 414, photo: .ring, pins: [p(660, 213), p(660, 256), p(660, 156)], hold: "De draadjes zitten al aan de ring vast.")
        case .lamp: return Info(w: 480, h: 420, photo: .lamp, marks: [(p(265, 82), "plus"), (p(189, 334), "min")], hold: "Plus bij het plusje, min bij het minnetje.")
        case .mic: return Info(w: 270, h: 270, photo: .mic, pins: [p(170, 159), p(179, 110), p(160, 207), p(51, 186), p(59, 139)], hold: "De kant met de lettertjes naar je toe.")
        case .led: return Info(w: 300, h: 180, pins: [p(290, 70), p(240, 112)])
        case .speaker: return Info(w: 300, h: 220, pins: [p(285, 88), p(285, 132)])
        case .button: return d.pin == 0 ? nil : Info(w: 300, h: 200, pins: [p(285, 78), p(285, 122)])
        case .touch: return Info(w: 300, h: 160, pins: [p(150, 80)])
        // shortcut: de volgorde van de gaatjes is die van de meeste VL53L1X-bordjes, niet nagekeken op dat van Gerben; vervang door een foto zodra die er is
        case .tof: return Info(w: 300, h: 260, pins: ["VIN", "GND", "SDA", "SCL"].map { p(232, tofY($0)) }, hold: "Zoek de lettertjes op het sensorbordje.")
        case .motor: return Info(w: 300, h: 180)
        }
    }
    static let tofPins = ["VIN", "GND", "SCL", "SDA", "GPIO1", "XSHUT"]
    static func tofY(_ n: String) -> CGFloat { 45 + CGFloat(tofPins.firstIndex(of: n)!) * 34 }

    private static var cache: [Kind: NSImage] = [:]
    static func photo(_ k: Kind) -> NSImage? {
        guard [.pir, .ring, .lamp, .mic].contains(k) else { return nil }
        if let i = cache[k] { return i }
        let i = Bundle.main.url(forResource: k.rawValue, withExtension: "jpg", subdirectory: "parts").flatMap(NSImage.init(contentsOf:))
        cache[k] = i
        return i
    }

    static func symbol(_ k: Kind?) -> String {
        switch k {
        case .led: "lightbulb.fill"; case .lamp: "sun.max.fill"; case .ring: "circle.dotted"; case .speaker: "speaker.wave.2.fill"
        case .motor: "fanblades.fill"; case .button: "button.programmable"; case .pir: "figure.walk.motion"; case .tof: "ruler"
        case .mic: "mic.fill"; case .touch: "hand.point.up.left.fill"; case nil: "shippingbox.fill"
        }
    }

    // De getekende onderdelen, in hun eigen maten (zoals de svg in web/parts.js).
    static func draw(_ k: Kind, _ c: GraphicsContext) {
        func leg(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y2))
            c.stroke(p, with: .color(Color(hex: "#a8adb5")), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: String, stroke: String? = nil, _ lw: CGFloat = 0) {
            let p = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
            c.fill(p, with: .color(Color(hex: fill)))
            if let stroke { c.stroke(p, with: .color(Color(hex: stroke)), lineWidth: lw) }
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ fill: String) { c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: fill))) }
        switch k {
        case .led:
            var dome = Path()
            dome.addArc(center: CGPoint(x: 75, y: 90), radius: 50, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
            dome.addLine(to: CGPoint(x: 120, y: 140)); dome.addLine(to: CGPoint(x: 120, y: 40)); dome.closeSubpath()
            c.fill(dome, with: .color(Color(hex: "#ffd84d"))); c.stroke(dome, with: .color(Color(hex: "#c9a400")), lineWidth: 3)
            rect(118, 32, 12, 116, 3, "#e0b82c")
            leg(130, 70, 290, 70); leg(130, 112, 240, 112)
        case .speaker:
            circle(110, 110, 95, "#2b2f36"); circle(110, 110, 78, "#3d434d"); circle(110, 110, 34, "#1d2026")
            rect(196, 76, 26, 68, 4, "#c9a23f")
            leg(215, 88, 285, 88); leg(215, 132, 285, 132)
        case .button:
            rect(60, 40, 130, 120, 12, "#30343b"); circle(125, 100, 38, "#111111"); circle(125, 100, 28, "#666666")
            leg(190, 78, 285, 78); leg(190, 122, 285, 122)
        case .touch:
            rect(30, 30, 120, 100, 6, "#d7dbe0", stroke: "#aab0b8", 2)
            c.draw(Text("folie").font(.ui(size: 17)).foregroundColor(Color(hex: "#555555")), at: CGPoint(x: 90, y: 80))
        case .tof:
            rect(60, 20, 190, 220, 10, "#5b3fa8"); rect(85, 100, 56, 44, 3, "#111111")
            for n in tofPins {
                let y = tofY(n)
                circle(232, y, 7, "#d9c47a")
                c.draw(Text(n).font(.ui(size: 14, weight: .bold)).foregroundColor(.white), at: CGPoint(x: 216, y: y), anchor: .trailing)
            }
        case .motor:
            rect(50, 50, 150, 80, 10, "#c7ccd4", stroke: "#8d949e", 3); rect(200, 62, 34, 56, 4, "#d6b24a"); rect(234, 84, 46, 12, 3, "#8d949e")
        default: break
        }
    }
}

// Eén plaatje: links het echte onderdeel, rechts het bordje van achteren gezien (waar de pinnetjes uitsteken, dus links en rechts
// gespiegeld ten opzichte van de opdruk aan de voorkant), en elk draadje ertussen in zijn eigen kleur. Port van wiringSvg in web/app.js.
struct WiringDrawing: View {
    let project: Project
    let device: Device?
    let plan: (rows: [String: [Wire]], users: [String: [Device]])
    var highlight: Int? = nil

    static let vb = CGSize(width: 790, height: 600)
    static let bx: CGFloat = 560, bw: CGFloat = 150, top: CGFloat = 110, pitch: CGFloat = 28
    static let part = CGRect(x: 10, y: 0, width: 340, height: 470)
    static let dark = Color(hex: "#1d2433"), boardInk = Color(hex: "#1f2a44")

    struct Pos { let p: String, x: CGFloat, y: CGFloat, side: String }
    static let pos: [String: Pos] = {
        var pos: [String: Pos] = [:]
        for (i, p) in RIGHT.enumerated() { pos[p == "GND" ? "GND:L" : p] = Pos(p: p, x: bx, y: top + CGFloat(i) * pitch, side: "L") }
        for (i, p) in LEFT.enumerated() { pos[p == "GND" ? "GND:R" : p] = Pos(p: p, x: bx + bw, y: top + CGFloat(i) * pitch, side: "R") }
        return pos
    }()

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / Self.vb.width, size.height / Self.vb.height)
            ctx.translateBy(x: (size.width - Self.vb.width * s) / 2, y: (size.height - Self.vb.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            draw(ctx)
        }
        .aspectRatio(Self.vb.width / Self.vb.height, contentMode: .fit)
        .accessibilityLabel("Het onderdeel, de ESP32 van achteren gezien, en de draadjes ertussen")
    }

    private func text(_ c: GraphicsContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 13, weight: Font.Weight = .regular, color: Color = Color(hex: "#666677"), anchor: UnitPoint = .center) {
        c.draw(Text(s).font(.ui(size: size, weight: weight)).foregroundColor(color), at: CGPoint(x: x, y: y), anchor: anchor)
    }

    private static func edge(_ hex: String) -> Color { hex == wireHex("wit") ? Color(hex: "#8b93a1") : Color(hex: hex) }   // een wit draadje heeft een rand nodig

    private func chip(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ t: String, _ hex: String) {
        let w = CGFloat(t.count) * 7.2 + 18, r = Path(roundedRect: CGRect(x: x, y: y - 11, width: w, height: 22), cornerRadius: 11)
        c.fill(r, with: .color(.white))
        c.stroke(r, with: .color(Self.edge(hex)), lineWidth: 2.5)
        text(c, t, x + w / 2, y, size: 12.5, weight: .bold, color: Self.dark)
    }

    private func draw(_ c: GraphicsContext) {
        let bx = Self.bx, bw = Self.bw
        let rows = device.flatMap { plan.rows[$0.id] } ?? []
        let k = device?.kind.info
        let mine = Set(k?.needs != nil ? [] : rows.compactMap(\.key))
        var taken: [String: [Device]] = [:]
        for o in project.devices where o.id != device?.id { for w in plan.rows[o.id] ?? [] { if let key = w.key { taken[key, default: []].append(o) } } }

        // het bordje
        text(c, "achterkant van de ESP32", bx + bw / 2, 20)
        c.fill(Path(roundedRect: CGRect(x: bx, y: 30, width: bw, height: 540), cornerRadius: 8), with: .color(Self.boardInk))
        let ant = Path(roundedRect: CGRect(x: bx + 30, y: 40, width: bw - 60, height: 48), cornerRadius: 4)
        c.fill(ant, with: .color(Color(hex: "#2d3a5c")))
        c.stroke(ant, with: .color(Color(hex: "#8fa3d9")), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        text(c, "antenne", bx + bw / 2, 64, size: 11, color: Color(hex: "#b7c4ea"))
        c.fill(Path(roundedRect: CGRect(x: bx + bw / 2 - 18, y: 556, width: 36, height: 24), cornerRadius: 3), with: .color(Color(hex: "#9aa5b8")))
        text(c, "USB", bx + bw / 2, 592, size: 11)
        for (x, lab) in [(bx + 24, "BOOT"), (bx + bw - 24, "EN")] {
            let st = StrokeStyle(lineWidth: 1, dash: [3, 3])
            c.stroke(Path(roundedRect: CGRect(x: x - 12, y: 522, width: 24, height: 24), cornerRadius: 4), with: .color(Color(hex: "#cfd6e6")), style: st)
            c.stroke(Path(ellipseIn: CGRect(x: x - 6, y: 528, width: 12, height: 12)), with: .color(Color(hex: "#cfd6e6")), style: st)
            text(c, lab, x, 558, size: 10, color: Color(hex: "#e8ecf7"))
        }
        if device?.pin == 0 && device?.kind == .button {
            c.stroke(Path(ellipseIn: CGRect(x: bx + 24 - 17, y: 534 - 17, width: 34, height: 34)), with: .color(Color(hex: "#ffd84d")), lineWidth: 4)
        }

        // de stipjes liggen onder de draadjes
        for (key, at) in Self.pos {
            let others = taken[key], r: CGFloat = others != nil ? 6.5 : 5
            let dot = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
            c.fill(dot, with: .color(others.map { Color(hex: $0[0].kind.info.color) } ?? Color(hex: "#d9c47a")))
            c.stroke(dot, with: .color(Color(hex: "#333333")), lineWidth: 1)
        }

        // het onderdeel
        let cx = Self.part.minX + Self.part.width / 2
        if let d = device {
            if let a = Art.info(d) {
                let s = min(Self.part.width / a.w, Self.part.height / a.h)
                let ox = Self.part.maxX - a.w * s, oy = Self.vb.height / 2 - a.h * s / 2
                if let pk = a.photo, let img = Art.photo(pk) {
                    var l = c
                    l.clip(to: Path(roundedRect: CGRect(x: ox, y: oy, width: a.w * s, height: a.h * s), cornerRadius: 12))
                    l.draw(Image(nsImage: img), in: CGRect(x: ox, y: oy, width: a.w * s, height: a.h * s))
                } else {
                    var l = c
                    l.translateBy(x: ox, y: oy)
                    l.scaleBy(x: s, y: s)
                    Art.draw(d.kind, l)
                }
                if let hold = a.hold { text(c, hold, cx, oy + a.h * s + 26, size: 15, color: Color(hex: "#4a5265")) }
                for (m, t) in a.marks {
                    let x = ox + m.x * s, y = oy + m.y * s, ring = Path(ellipseIn: CGRect(x: x - 16, y: y - 16, width: 32, height: 32))
                    c.stroke(ring, with: .color(.white), lineWidth: 4)
                    c.stroke(ring, with: .color(Color(hex: "#e5484d")), lineWidth: 2)
                    chip(c, x + 22, y, t, "#e5484d")
                }
                if k?.needs == nil { drawWires(c, rows, a, s, ox, oy) }
            } else {
                for (i, l) in ["Dit knopje zit al op het bordje,", "aan de andere kant.", "Je hoeft niets aan te sluiten."].enumerated() { text(c, l, cx, 270 + CGFloat(i) * 22, size: 15, color: Color(hex: "#4a5265")) }
            }
        } else {
            text(c, "Kies links een onderdeel.", cx, 290, size: 15, color: Color(hex: "#4a5265"))
        }

        // de namen van de pinnen erboven. Rechts loopt een draadje over het bordje heen: die naam staat buiten het bordje.
        for (key, at) in Self.pos {
            let hit = mine.contains(key)
            let label = pinName(at.p) + (["GND": " −", "3V3": " +", "VIN": " +"][at.p] ?? "")
            if hit && at.side == "R" {
                text(c, label, at.x + 14, at.y, size: 16, weight: .heavy, color: Self.dark, anchor: .leading)
            } else {
                text(c, label, at.side == "L" ? at.x + 13 : at.x - 13, at.y, size: hit ? 16 : 11.5, weight: hit ? .heavy : .regular,
                     color: hit ? .white : Color(hex: "#aebbd8"), anchor: at.side == "L" ? .leading : .trailing)
            }
        }
    }

    private func drawWires(_ c: GraphicsContext, _ rows: [Wire], _ a: Art.Info, _ s: CGFloat, _ ox: CGFloat, _ oy: CGFloat) {
        let live = rows.filter { $0.key != nil && $0.i < a.pins.count }.sorted { a.pins[$0.i].y < a.pins[$1.i].y }
        var prevY: CGFloat = -99, prevShift: CGFloat = 0
        for w in live {
            guard let hex = w.color, let b = Self.pos[w.key!] else { continue }
            var l = c
            if let h = highlight, h != w.i { l.opacity = 0.18 }
            let x0 = ox + a.pins[w.i].x * s, y0 = oy + a.pins[w.i].y * s, x1 = b.x - 18
            let shift: CGFloat = y0 - prevY < 26 && prevShift == 0 ? 1 : 0   // labels die te dicht op elkaar zitten verspringen
            prevY = y0; prevShift = shift
            let c1 = max(x0 + 110, ox + a.w * s + 60), c2 = x1 - 110
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y0))
            path.addCurve(to: CGPoint(x: x1, y: b.y), control1: CGPoint(x: c1, y: y0), control2: CGPoint(x: c2, y: b.y))
            let outline = ["zwart", "bruin", "paars"].contains(w.name) ? Color.white : Self.dark.opacity(0.7)
            l.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            l.stroke(path, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
            let start = Path(ellipseIn: CGRect(x: x0 - 6, y: y0 - 6, width: 12, height: 12))
            l.fill(start, with: .color(Color(hex: hex))); l.stroke(start, with: .color(.white), lineWidth: 2)
            let lx = max(x0 + 12, ox + a.w * s + 6) + shift * 78   // het label staat naast het plaatje
            chip(l, lx, y0, w.lab, hex)
            if w.inline != nil {   // wat ertussen moet zit vlak achter het label
                let rx = lx + CGFloat(w.lab.count) * 7.2 + 18 + 12
                func bez(_ t: CGFloat, _ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
                    let u = 1 - t; return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
                }
                let t = (0...40).map { CGFloat($0) / 40 }.first { bez($0, x0, c1, c2, x1) >= rx + 40 } ?? 0.5
                let ry = bez(t, y0, y0, b.y, b.y)
                let box = Path(roundedRect: CGRect(x: rx, y: ry - 11, width: 80, height: 22), cornerRadius: 8)
                l.fill(box, with: .color(Color(hex: "#e8d3a0"))); l.stroke(box, with: .color(Color(hex: "#7a6126")), lineWidth: 2)
                text(l, "weerstand", rx + 40, ry, size: 12.5, weight: .bold, color: Color(hex: "#4a3a12"))
            }
            let plug = Path(roundedRect: CGRect(x: x1 - 2, y: b.y - 6.5, width: 17, height: 13), cornerRadius: 3)
            l.fill(plug, with: .color(Color(hex: "#222222"))); l.stroke(plug, with: .color(.white), lineWidth: 1)
            let end = Path(ellipseIn: CGRect(x: b.x - 7.5, y: b.y - 7.5, width: 15, height: 15))
            l.fill(end, with: .color(Color(hex: hex))); l.stroke(end, with: .color(.white), lineWidth: 2)
        }
    }
}
