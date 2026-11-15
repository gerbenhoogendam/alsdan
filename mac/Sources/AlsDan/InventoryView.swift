// Inventaris: alles wat in je doos zit, voor al je projecten. Met een foto van de webcam, en de kleuren van de draadjes die echt aan
// je onderdelen zitten: die gebruikt Aansluiten in elk schema.
import SwiftUI
import AlsDanCore

struct InventoryView: View {
    @Environment(AppState.self) var app
    @State private var selected: String?
    @State private var filter = 0
    @State private var camera = false

    // De draadjes van een soort onderdeel, met een voorbeeldpin zodat de seintjes er ook bij staan.
    nonisolated static func wires(_ part: Part) -> [Wire] {
        guard let k = part.kind else { return [] }
        var d = Device(id: "x", kind: k, name: "")
        d.pin = k.info.prefer.first { $0 != 0 } ?? k.info.pins.first
        if k.info.two { d.pin2 = k.info.prefer.dropFirst().first }
        return Project.wires(d, owned: part.colors).filter { $0.name != nil }
    }

    var body: some View {
        let parts = app.parts
        let shown = parts.filter { filter == 0 || (filter == 1 ? !$0.toBuy : $0.toBuy) }
        let allWires = parts.flatMap { p in Self.wires(p).map { (p, $0) } }
        let part = parts.first { $0.id == selected } ?? shown.first
        Page(title: "Inventaris", intro: "Alles wat in je doos zit. Claude kiest bij een wens eerst uit deze spullen, en elk schema tekent de draadjes in de kleuren die jij echt gebruikt.") {
            HStack(spacing: 10) {
                Stat(label: "Soorten onderdelen", value: "\(parts.count)", color: Ink.indigo)
                Stat(label: "Met een foto", value: "\(parts.filter { $0.photo != nil }.count) van \(parts.count)", color: Ink.cyan)
                Stat(label: "Draadjes met kleur", value: "\(allWires.filter { $0.0.colors[$0.1.i] != nil }.count) van \(allWires.count)", color: Ink.ringWired)
                Stat(label: "Nog kopen", value: "\(parts.filter(\.toBuy).count)", color: Ink.orange)
            }
            HStack(spacing: 8) {
                ForEach(Array(["Alles", "In huis", "Nog kopen"].enumerated()), id: \.offset) { i, t in Button(t) { filter = i }.buttonStyle(Chip(on: filter == i)) }
                Spacer()
                Button { let p = Part(name: "Nieuw onderdeel"); app.parts.append(p); selected = p.id } label: { Label("Nieuw onderdeel", systemImage: "plus") }.buttonStyle(Soft())
                Button { camera = true } label: { Label("Foto maken", systemImage: "camera") }.buttonStyle(Filled())
            }
            HStack(alignment: .top, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(shown) { p in card(p, on: p.id == part?.id) }
                }
                .frame(maxWidth: .infinity)
                if let part { detail(part).frame(width: 400) }
            }
        }
        .sheet(isPresented: $camera) { CameraSheet { selected = $0 } }
    }

    func card(_ p: Part, on: Bool) -> some View {
        let wires = Self.wires(p), missing = wires.filter { p.colors[$0.i] == nil }.count
        return Button { selected = p.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                PartPicture(kind: p.kind, photo: p.photo, size: 146)
                Text(p.name).font(.ui(size: 14, weight: .semibold)).lineLimit(1)
                HStack {
                    Text(p.kind?.info.label ?? "iets anders").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                    Spacer()
                    Text("×\(p.count)").font(.ui(size: 13, weight: .black, design: .rounded))
                }
                if p.toBuy { Text("nog kopen").font(.ui(size: 12, weight: .semibold)).foregroundStyle(Ink.orange) }
                else if missing > 0 { Text("kleuren vastleggen").font(.ui(size: 12, weight: .semibold)).foregroundStyle(Ink.cyan) }
                else if !wires.isEmpty { Text("kleuren klaar").font(.ui(size: 12, weight: .semibold)).foregroundStyle(Ink.green) }
                else { Text(" ").font(.ui(size: 12)) }   // zelfde hoogte als de andere kaartjes
            }
            .padding(12)
            .background(on ? Ink.accent.opacity(0.14) : Ink.card, in: ChamferedRect(cut: 16))
        }
        .buttonStyle(.plain)
    }

    func binding(_ id: String) -> Binding<Part> {
        Binding(get: { app.parts.first { $0.id == id } ?? Part(name: "") }, set: { nv in if let i = app.parts.firstIndex(where: { $0.id == id }) { app.parts[i] = nv } })
    }

    func detail(_ p: Part) -> some View {
        let b = binding(p.id), wires = Self.wires(p)
        let redMin = wires.contains { $0.pin == "GND" && $0.name == "rood" }, blackPlus = wires.contains { ($0.pin == "3V3" || $0.pin == "VIN") && $0.name == "zwart" }
        return Card {
            PartPicture(kind: p.kind, photo: p.photo, size: 360).frame(maxWidth: .infinity)
            TextField("Naam", text: b.name).textFieldStyle(.roundedBorder).font(.ui(size: 15, weight: .semibold))
            HStack {
                Picker("Soort", selection: b.kind) {
                    Text("Iets anders").tag(Kind?.none)
                    ForEach(Kind.allCases) { Text($0.info.label).tag(Kind?.some($0)) }
                }
                .fixedSize()
                Spacer()
                Stepper("× \(p.count)", value: b.count, in: 0...99).fixedSize()
            }
            Toggle("Nog kopen", isOn: b.toBuy)
            if p.kind == nil {
                Text("Voor dit onderdeel tekent de app nog geen schema. Claude weet wel dat je het hebt.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            } else {
                Text("Draadjes").font(.ui(size: 15, weight: .bold))
                Text("Kies de kleur van het draadje dat echt aan je onderdeel zit.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                ForEach(wires, id: \.i) { w in
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(WIRE_COLORS, id: \.name) { c in Button(c.name) { b.wrappedValue.colors[w.i] = c.name } }
                            Divider()
                            Button("Weet ik niet") { b.wrappedValue.colors[w.i] = nil }
                        } label: {
                            HStack(spacing: 6) { Circle().fill(Color(hex: w.color!)).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.white.opacity(0.4))); Text(p.colors[w.i] ?? "\(w.name!)?") }
                        }
                        .fixedSize()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.lab).font(.ui(size: 13, weight: .semibold))
                            Text(w.num != nil ? "seintje, naar een pin" : w.pin == "GND" ? "min, naar GND" : "plus, naar \(w.pin)").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                        }
                    }
                }
                if redMin { Label("Let op: bij dit onderdeel is rood de min. Steek het rode draadje op GND (min), niet op de plus.", systemImage: "exclamationmark.triangle.fill").font(.ui(size: 14)).foregroundStyle(Ink.orange) }
                if blackPlus { Label("Let op: hier is zwart de plus. Steek het zwarte draadje op de plus, niet op GND.", systemImage: "exclamationmark.triangle.fill").font(.ui(size: 14)).foregroundStyle(Ink.orange) }
            }
            HStack {
                Button { camera = true; selected = p.id } label: { Label(p.photo == nil ? "Maak een foto" : "Nieuwe foto", systemImage: "camera") }.buttonStyle(Soft())
                if p.kind != nil { Button("Bekijk in Aansluiten") { app.screen = .wiring }.buttonStyle(Soft()) }
                Spacer()
                Button(role: .destructive) { app.parts.removeAll { $0.id == p.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Weg uit de inventaris")
            }
        }
    }
}

// De foto van een onderdeel: de webcam (of een foto van de schijf), Claude zegt wat het is en welke kleur de draadjes hebben, jij
// verbetert wat niet klopt, en dan gaat het in de inventaris.
struct CameraSheet: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss
    var onSaved: (String) -> Void
    @State private var camera = Camera()
    @State private var jpeg: Data?
    @State private var thinking = false
    @State private var problem: String?
    @State private var part = Part(name: "")
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Head("Foto van een onderdeel")
                Spacer()
                Button("Sluit") { dismiss() }.buttonStyle(Soft())
            }
            if let jpeg, let img = NSImage(data: jpeg) {
                HStack(alignment: .top, spacing: 20) {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 380).clipShape(ChamferedRect(cut: 14))
                    VStack(alignment: .leading, spacing: 12) {
                        if thinking { HStack { ProgressView().controlSize(.small); Text("Claude kijkt…") } }
                        else { result }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ZStack {
                    CameraPreview(session: camera.session).clipShape(ChamferedRect(cut: 14))
                    ChamferedRect(cut: 18).strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [10, 8])).padding(50)
                    VStack { Spacer(); Text(camera.problem ?? "Houd het onderdeel met de draadjes in het kader.").padding(8).background(.black.opacity(0.6), in: Capsule()).padding(14) }
                }
                .frame(height: 420)
                HStack {
                    Text(camera.name).font(.ui(size: 12)).foregroundStyle(Ink.dim)
                    Spacer()
                    Button("Kies een foto…") { if let d = Photo.choose() { took(d) } }.buttonStyle(Soft())
                    Button { Task { if let d = await camera.shoot() { took(d) } } } label: { Label("Maak foto", systemImage: "camera.fill") }
                        .buttonStyle(Filled(big: true)).disabled(camera.problem != nil).keyboardShortcut(.space, modifiers: [])
                }
            }
            if let problem { Text(problem).font(.ui(size: 14)).foregroundStyle(Ink.orange) }
        }
        .padding(24)
        .frame(width: 860)
        .background(Ink.card)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder var result: some View {
        Text("Herkend").font(.ui(size: 12)).foregroundStyle(Ink.dim)
        TextField("Naam", text: $part.name).textFieldStyle(.roundedBorder).font(.ui(size: 17, weight: .bold))
        Picker("Soort", selection: $part.kind) {
            Text("Iets anders").tag(Kind?.none)
            ForEach(Kind.allCases) { Text($0.info.label).tag(Kind?.some($0)) }
        }
        .fixedSize()
        if !note.isEmpty { Text(note).font(.ui(size: 14)).foregroundStyle(Ink.dim) }
        let wires = InventoryView.wires(part)
        if !wires.isEmpty {
            Text("Klopt een kleur niet? Klik erop.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            ForEach(wires, id: \.i) { w in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(WIRE_COLORS, id: \.name) { c in Button(c.name) { part.colors[w.i] = c.name } }
                        Divider()
                        Button("Weet ik niet") { part.colors[w.i] = nil }
                    } label: {
                        HStack(spacing: 6) { Circle().fill(Color(hex: w.color!)).frame(width: 16, height: 16); Text(part.colors[w.i] ?? "?") }
                    }
                    .fixedSize()
                    Text("is \(w.lab)").font(.ui(size: 13))
                }
            }
        }
        HStack {
            Button("Opnieuw") { jpeg = nil; problem = nil }.buttonStyle(Soft())
            Spacer()
            Button("Bewaar in inventaris") { save() }.buttonStyle(Filled(big: true)).disabled(part.name.isEmpty)
        }
    }

    func took(_ data: Data) {
        guard let small = Photo.jpeg(data) else { problem = "Die foto kan ik niet lezen."; return }
        jpeg = small
        camera.stop()
        thinking = true
        problem = nil
        Task {
            defer { thinking = false }
            do {
                let g = try await Claude.recognise(jpeg: small)
                part.kind = Kind(rawValue: g.kind)
                part.name = app.parts.first { $0.kind == part.kind && part.kind != nil }?.name ?? g.name
                part.colors = [:]
                let wires = InventoryView.wires(Part(name: "", kind: part.kind))
                for (n, w) in wires.enumerated() where n < g.wires.count && wireHex(g.wires[n]) != nil { part.colors[w.i] = g.wires[n] }
                note = g.note
            } catch {
                problem = error.localizedDescription + " Vul het dan zelf in."
            }
        }
    }

    func save() {
        guard let jpeg else { return }
        let file = UUID().uuidString + ".jpg"
        try? jpeg.write(to: AppState.photos.appendingPathComponent(file))
        if let k = part.kind, let i = app.parts.firstIndex(where: { $0.kind == k && !$0.toBuy }) {
            app.parts[i].photo = file   // dat onderdeel had je al: alleen de foto en de draadjes
            app.parts[i].colors.merge(part.colors) { _, new in new }
            onSaved(app.parts[i].id)
        } else {
            var p = part
            p.photo = file
            app.parts.append(p)
            onSaved(p.id)
        }
        dismiss()
    }
}
