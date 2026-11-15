// Stap 6, Live: wat de ESP32 nu voelt en hoort, wat de Mac hoort, wat de onderdelen doen, en welke regels vandaag afgingen.
import SwiftUI
import AlsDanCore

struct LiveView: View {
    @Environment(AppState.self) var app

    var body: some View {
        let p = app.project, b = app.board
        let index = { (d: Device) -> Int? in b.dirty ? nil : b.sent?.devices.firstIndex(of: d.id) }
        let inputs = p.devices.filter { $0.kind.info.live != nil }, outputs = p.devices.filter { $0.kind.info.out }
        Page(title: "Live", intro: "Wat de ESP32 nu voelt en hoort, en wat hij daarmee doet. Klinkt het geluid via de Mac, dan staat dat erbij.") {
            if !b.connected || b.dirty {
                Label(!b.connected ? "De ESP32 zit niet aan de Mac. Steek de USB-kabel erin." : "Je regels staan nog niet op de ESP32. Klik op Zet op ESP32, dan zie je hier wat hij voelt.",
                      systemImage: "info.circle").foregroundStyle(Ink.orange)
            }
            HStack(spacing: 8) {
                Text("Probeer het uit:").foregroundStyle(Ink.dim)
                ForEach(p.rules) { r in
                    Button { app.run(r) } label: { HStack(spacing: 6) { Tag("ALS"); Text(sentence(r.trigger, p)).lineLimit(1) } }.buttonStyle(Chip())
                }
            }

            section("ALS", "wat hij voelt en hoort")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(inputs) { d in sensor(d, index(d)) }
                ears
            }

            section("DAN", "wat hij doet")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(outputs) { d in output(d) }
            }

            HStack(alignment: .top, spacing: 20) {
                today.frame(maxWidth: .infinity)
                feed.frame(width: 420)
            }
        }
        .onAppear { app.listenScreens = true }
        .onDisappear { app.listenScreens = false }
    }

    func section(_ tag: String, _ text: String) -> some View {
        HStack(spacing: 10) { Tag(tag); Text(text).font(.ui(size: 15, weight: .bold)) }
    }

    func sensor(_ d: Device, _ i: Int?) -> some View {
        let k = d.kind.info, v = i.flatMap { app.board.values[$0] }
        let hist = i.flatMap { app.board.history[$0] } ?? []
        return Card {
            HStack { PartPicture(kind: d.kind, photo: app.part(for: d.kind)?.photo, size: 36); Text(d.name).font(.ui(size: 15, weight: .bold)) }
            Text(v.map { k.live!($0) } ?? "–").font(.ui(size: 28, weight: .black, design: .rounded)).foregroundStyle(Color(hex: k.color))
            Spark(points: hist, top: d.kind == .tof ? 200 : d.kind == .mic ? 100 : 1, color: Color(hex: k.color))
                .frame(height: 40)
            HStack { Text("1 minuut geleden"); Spacer(); Text("nu") }.font(.ui(size: 11)).foregroundStyle(Ink.dim)
        }
    }

    var ears: some View {
        let e = app.ears
        return Card {
            HStack { Image(systemName: "ear").foregroundStyle(Ink.pink).frame(width: 36, height: 36).background(Ink.well, in: ChamferedRect(cut: 8)); Text("De Mac luistert").font(.system(size: 15, weight: .bold)) }
            Text("\(e.level)").font(.ui(size: 28, weight: .black, design: .rounded)).foregroundStyle(Ink.pink)
            Text("hoe hard · hoort nu: " + (e.heard.map { MacEars.label($0.id) } ?? "niets")).font(.ui(size: 12)).foregroundStyle(Ink.dim)
            if let p = e.problem { Text(p).font(.ui(size: 12)).foregroundStyle(Ink.orange) }
        }
    }

    func output(_ d: Device) -> some View {
        let k = d.kind.info
        return Card {
            HStack { PartPicture(kind: d.kind, photo: app.part(for: d.kind)?.photo, size: 36); Text(d.name).font(.ui(size: 15, weight: .bold)) }
            if let n = k.needs { Text("Nog niet aangesloten: eerst \(n).").font(.ui(size: 12)).foregroundStyle(Ink.orange) }
            HStack {
                ForEach(k.tests, id: \.self) { t in
                    Button(WiringView.testLabels[t.kind] ?? t.kind.rawValue) {
                        var s = t
                        s.dev = d.id
                        Task { await app.board.test([app.project.encode(s)].compactMap { $0 }, project: app.project) }
                    }
                    .buttonStyle(Soft()).disabled(!app.board.connected || k.needs != nil)
                }
            }
        }
    }

    var today: some View {
        let events = app.events.filter { Calendar.current.isDateInToday($0.time) }
        var perHour = [Int](repeating: 0, count: 24)
        for e in events { perHour[Calendar.current.component(.hour, from: e.time)] += 1 }
        let top = max(perHour.max() ?? 1, 1)
        let counts = Dictionary(grouping: events, by: \.rule).mapValues(\.count)
        return Card {
            Head("Vandaag")
            Text("zo vaak ging een regel af, per uur").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    ChamferedRect(cut: 2).fill(perHour[h] > 0 ? Ink.ringWired : Ink.well).frame(height: max(4, 70 * CGFloat(perHour[h]) / CGFloat(top)))
                }
            }
            .frame(height: 70)
            HStack { ForEach(["00", "06", "12", "18", "24"], id: \.self) { Text($0); if $0 != "24" { Spacer() } } }.font(.ui(size: 11)).foregroundStyle(Ink.dim)
            ForEach(app.project.rules) { r in
                HStack { Text(sentence(r.trigger, app.project)).font(.ui(size: 13)); Spacer(); Text("\(counts[r.id] ?? 0)×").font(.ui(size: 15, weight: .black, design: .rounded)).foregroundStyle(Ink.ringWired) }
            }
        }
    }

    var feed: some View {
        let p = app.project
        return Card {
            HStack { Head("Wat er gebeurde"); Spacer(); Text("nieuwste boven").font(.ui(size: 12)).foregroundStyle(Ink.dim) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(app.events.reversed()) { e in
                        if let r = p.rules.first(where: { $0.id == e.rule }) {
                            Well {
                                HStack { Text(e.time, format: .dateTime.hour().minute().second()).font(.ui(size: 12, design: .monospaced)).foregroundStyle(Ink.dim); if e.viaMac { Text("geprobeerd of gehoord door de Mac").font(.ui(size: 12)).foregroundStyle(Ink.pink) } }
                                HStack(spacing: 8) { Tag("ALS"); Text(sentence(r.trigger, p)).font(.ui(size: 13)) }
                                ForEach(Array(r.steps.enumerated()), id: \.offset) { _, s in HStack(spacing: 8) { Tag("DAN"); Text(sentence(s, p, sound: app.sound)).font(.ui(size: 13)) } }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 420)
            if app.events.isEmpty { Text("Nog niets gebeurd vandaag.").font(.ui(size: 14)).foregroundStyle(Ink.dim) }
        }
    }
}

// Een lijntje van de laatste minuut.
struct Spark: View {
    let points: [(Date, Int)]
    let top: Int
    let color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Canvas { c, size in
                let now = ctx.date
                var path = Path()
                for (i, (t, v)) in points.enumerated() {
                    let x = size.width * CGFloat(1 - now.timeIntervalSince(t) / 60)
                    let y = size.height * (1 - CGFloat(min(max(v, 0), top)) / CGFloat(top))
                    i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                c.stroke(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(Ink.well))
            }
        }
    }
}
