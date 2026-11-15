// Stap 4, Aansluiten: draadje voor draadje, met het plaatje van het onderdeel en de achterkant van de ESP32. Vink af wat vastzit.
import SwiftUI
import AlsDanCore

struct WiringView: View {
    @Environment(AppState.self) var app
    @State private var selected: String?
    @State private var hover: Int?

    static let testLabels: [StepKind: String] = [.on: "Aan", .off: "Uit", .color: "Rood", .rainbow: "Regenboog", .ringoff: "Uit", .beep: "Piep", .tada: "Tada", .fwd: "Vooruit", .stop: "Stop"]

    var body: some View {
        let p = app.project, plan = p.plan(owned: app.owned), todo = app.wiresToDo
        let d = p.device(selected) ?? p.devices.first { plan.rows[$0.id]?.contains { $0.key != nil } == true } ?? p.devices.first
        Page(title: "Aansluiten", intro: "Draadje voor draadje. Je kijkt tegen de achterkant van de ESP32, met de pinnetjes naar je toe.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    Stat(label: "Draadjes", value: "\(todo.filter(p.doneWires.contains).count) van \(todo.count)", color: Ink.ringWired, sub: "zitten al vast")
                    ForEach(p.devices) { dev in deviceRow(dev, plan: plan, on: dev.id == d?.id) }
                }
                .frame(width: 250)

                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        WiringDrawing(project: p, device: d, plan: plan, highlight: hover)
                            .padding(10).background(Color(hex: "#EEF0F4"), in: ChamferedRect(cut: 14))
                    }
                    if let d { steps(d, plan: plan) }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    if let d { test(d) }
                    if p.devices.contains(where: { $0.kind == .speaker || $0.kind == .led }) { resistor }
                    needs(p)
                }
                .frame(width: 300)
            }
        }
    }

    func deviceRow(_ d: Device, plan: (rows: [String: [Wire]], users: [String: [Device]]), on: Bool) -> some View {
        let rows = (plan.rows[d.id] ?? []).filter { $0.key != nil }
        let done = rows.filter { app.project.doneWires.contains("\(d.id):\($0.i)") }.count
        let sub = d.kind.info.needs != nil ? "eerst nodig: \(d.kind.info.needs!)" : rows.isEmpty ? "niets aansluiten" : done == rows.count ? "\(done) van \(rows.count) klaar" : "\(done) van \(rows.count)"
        return Button { selected = d.id; hover = nil } label: {
            HStack(spacing: 12) {
                PartPicture(kind: d.kind, photo: app.part(for: d.kind)?.photo, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.ui(size: 14, weight: .semibold)).lineLimit(1)
                    Text(sub).font(.ui(size: 12)).foregroundStyle(d.kind.info.needs != nil ? Ink.orange : done == rows.count && !rows.isEmpty ? Ink.green : Ink.dim).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Ink.accent.opacity(0.14) : Ink.card, in: ChamferedRect(cut: 14))
        }
        .buttonStyle(.plain)
    }

    func steps(_ d: Device, plan: (rows: [String: [Wire]], users: [String: [Device]])) -> some View {
        let k = d.kind.info, rows = plan.rows[d.id] ?? []
        let shared = rows.filter { $0.key != nil && $0.num == nil && (plan.users[$0.key!]?.count ?? 0) > 1 }
        return Card {
            Head("Zo sluit je \(d.name) aan")
            if let n = k.needs { Label("Nog niet aansluiten. Eerst nodig: \(n).", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Ink.orange) }
            else if let m = k.must { Label("Hiervoor heb je \(m) nodig. Zonder niet aansluiten.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Ink.orange) }
            ForEach(rows, id: \.i) { w in wireRow(d, w) }
            if !shared.isEmpty && k.needs == nil {
                Text("Delen: " + shared.map { w in "\(w.esp) met " + (plan.users[w.key!] ?? []).filter { $0.id != d.id }.map(\.name).joined(separator: " en ") }.joined(separator: ", ")
                     + ". Op een pinnetje past maar één draadje: draai ze samen vast in een lasdopje, met één draadje naar de pin.")
                    .font(.ui(size: 14)).foregroundStyle(Ink.cyan)
            }
            Text(k.note).font(.ui(size: 14)).foregroundStyle(Ink.dim)
        }
    }

    @ViewBuilder func wireRow(_ d: Device, _ w: Wire) -> some View {
        let id = "\(d.id):\(w.i)"
        let done = app.project.doneWires.contains(id)
        if w.pin == "BOOT" {
            Text("\(w.lab): \(w.hint ?? "").").font(.ui(size: 14))
        } else if w.color == nil {
            Text("\(w.lab) gaat naar \(w.pin)").font(.ui(size: 14)).foregroundStyle(Ink.dim)
        } else {
            HStack(spacing: 10) {
                Button {
                    if done { app.project.doneWires.remove(id) } else { app.project.doneWires.insert(id) }
                } label: { Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done ? Ink.green : Ink.dim) }
                    .buttonStyle(.plain).help(done ? "Zit vast" : "Klik als dit draadje vastzit").disabled(d.kind.info.needs != nil)
                Menu {
                    ForEach(WIRE_COLORS, id: \.name) { c in Button(c.name) { setColor(d, w.i, c.name) } }
                } label: {
                    HStack(spacing: 6) { Circle().fill(Color(hex: w.color!)).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white.opacity(0.4))); Text(w.name ?? "") }
                }
                .fixedSize().help("De kleur van je draadje")
                Text("\(w.lab)  →").font(.ui(size: 14, weight: .semibold))
                pinPicker(d, w)
                if let i = w.inline { Text("met \(i) ertussen").font(.ui(size: 12)).foregroundStyle(Ink.orange) }
                if let h = w.hint { Text(h).font(.ui(size: 12)).foregroundStyle(Ink.dim) }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(hover == w.i ? Ink.accent.opacity(0.08) : .clear, in: ChamferedRect(cut: 10))
            .onHover { hover = $0 ? w.i : (hover == w.i ? nil : hover) }   // wijs een draadje aan en alleen dat draadje blijft helder
        }
    }

    @ViewBuilder func pinPicker(_ d: Device, _ w: Wire) -> some View {
        // alleen een seintje-draadje (w.num) heeft een pin om te kiezen; GND en plus niet (nil == pin2 van een lampje is geen match)
        let key: WritableKeyPath<Device, Int?>? = d.kind.info.pins.isEmpty || w.num == nil ? nil : w.num == d.pin ? \.pin : w.num == d.pin2 ? \.pin2 : nil
        if let key, let i = app.project.devices.firstIndex(where: { $0.id == d.id }) {
            let used = app.project.usedPins(except: d.id), other = key == \.pin ? d.pin2 : d.pin
            Picker("Pin", selection: Binding(get: { d[keyPath: key] ?? -1 }, set: { app.project.devices[i][keyPath: key] = $0 })) {
                ForEach(d.kind.info.pins, id: \.self) { p in
                    Text((p == 0 ? "BOOT-knopje" : pinName(p)) + (used[p].map { " (\($0.name))" } ?? "")).tag(p).disabled(used[p] != nil || p == other)
                }
            }
            .labelsHidden().fixedSize()
        } else {
            Text(w.esp).font(.ui(size: 14, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 3).background(Ink.well, in: ChamferedRect(cut: 6))
        }
    }

    func setColor(_ d: Device, _ i: Int, _ name: String) {
        guard let n = app.project.devices.firstIndex(where: { $0.id == d.id }) else { return }
        app.project.devices[n].colors[i] = name
    }

    func test(_ d: Device) -> some View {
        let k = d.kind.info, idx = app.project.devices.firstIndex { $0.id == d.id }
        return Card {
            Head("Test \(d.name)")
            if k.out {
                Text(app.board.connected ? "Klik en kijk of het werkt." : "Steek eerst de USB-kabel van de ESP32 in de Mac.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                HStack {
                    ForEach(k.tests, id: \.self) { t in
                        Button(Self.testLabels[t.kind] ?? t.kind.rawValue) {
                            var s = t
                            s.dev = d.id
                            Task { await app.board.test([app.project.encode(s)].compactMap { $0 }, project: app.project) }
                        }
                        .buttonStyle(Soft()).disabled(!app.board.connected || k.needs != nil)
                    }
                }
            } else if let live = k.live {
                Text("Wat hij nu voelt").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                if let v = idx.flatMap({ app.board.dirty ? nil : app.board.values[$0] }) {
                    Text(live(v)).font(.ui(size: 22, weight: .black, design: .rounded)).foregroundStyle(Color(hex: k.color))
                } else {
                    Text("Zet eerst je regels op de ESP32, dan zie je het hier.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                }
            }
        }
    }

    // Zo lees je een weerstand van 220 Ω: rood, rood, bruin (en goud).
    var resistor: some View {
        Card {
            Head("Zo lees je een weerstand")
            HStack(spacing: 8) {
                band("2", "rood", "#e5484d"); band("2", "rood", "#e5484d"); band("×10", "bruin", "#8b5a2b")
                Text("= 220 Ω").font(.ui(size: 20, weight: .black, design: .rounded)).foregroundStyle(Ink.orange)
            }
            Text("Begin aan de kant zonder het gouden ringetje. Een weerstand zorgt dat er niet te veel stroom door gaat, anders gaat de pin van de ESP32 stuk.")
                .font(.ui(size: 12)).foregroundStyle(Ink.dim)
        }
    }
    func band(_ n: String, _ name: String, _ hex: String) -> some View {
        VStack(spacing: 4) {
            Text(n).font(.ui(size: 18, weight: .black, design: .rounded))
            ChamferedRect(cut: 3).fill(Color(hex: hex)).frame(width: 14, height: 34)
            Text(name).font(.ui(size: 11)).foregroundStyle(Ink.dim)
        }
    }

    func needs(_ p: Project) -> some View {
        let kinds = Array(Set(p.devices.filter { !$0.onBoard }.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        let have = kinds.filter { k in app.parts.contains { $0.kind == k && !$0.toBuy } }
        var buy = kinds.filter { !have.contains($0) }.map(\.info.label)
        buy += p.devices.compactMap(\.kind.info.needs) + p.shopping
        let resistor = app.parts.contains { $0.name.lowercased().contains("220") && !$0.toBuy }
        let extra = p.devices.compactMap(\.kind.info.must).filter { _ in resistor }
        buy += p.devices.compactMap(\.kind.info.must).filter { _ in !resistor }
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Head("Wat heb je nodig")
                Spacer()
                Text("\(have.count + 1) in huis · \(Set(buy).count) kopen").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            }
            Label("ESP32 en een USB-kabel", systemImage: "checkmark").foregroundStyle(Ink.green)
            ForEach(have, id: \.self) { Label($0.info.label, systemImage: "checkmark").foregroundStyle(Ink.green) }
            ForEach(Array(Set(extra)).sorted(), id: \.self) { Label($0.prefix(1).uppercased() + $0.dropFirst(), systemImage: "checkmark").foregroundStyle(Ink.green) }
            ForEach(Array(Set(buy)).sorted(), id: \.self) { Label($0.prefix(1).uppercased() + $0.dropFirst(), systemImage: "cart").foregroundStyle(Ink.orange) }
        }
        .font(.ui(size: 13))
    }
}
