// Stap 5, Op de ESP32: de regels erop zetten, de firmware erop zetten, lezen wat de ESP32 zegt, en hulp als er iets misgaat.
import SwiftUI
import AlsDanCore

struct BoardView: View {
    @Environment(AppState.self) var app
    @State private var technical = false
    @State private var advice: String?
    @State private var asking = false

    var body: some View {
        let b = app.board
        Page(title: "Op de ESP32", intro: "Zet je regels op het bordje. Daarna leest de app wat de ESP32 terugzegt, en helpt als er iets misgaat.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    upload
                    ForEach(b.problems) { problem($0) }
                    if let advice { Card(border: Ink.purple) { Label("Claude zegt", systemImage: "sparkles").font(.ui(size: 15, weight: .bold)).foregroundStyle(Ink.purple); Text(advice).font(.ui(size: 14)) } }
                    HStack(spacing: 20) { esp; firmware }
                }
                .frame(maxWidth: .infinity)
                log.frame(width: 420)
            }
        }
    }

    var upload: some View {
        let b = app.board
        let stages = ["Regels klaarmaken", "Versturen over de USB-kabel", "De ESP32 bewaart ze", "Klaar: hij doet het nu ook zonder Mac"]
        let at = b.upload == .done ? 4 : b.upload == .failed ? 0 : max(0, b.upload.rawValue - 1)
        return Card {
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Ink.green.opacity(0.25), lineWidth: 14)
                    Circle().trim(from: 0, to: max(0.001, Double(at) / 4)).stroke(b.upload == .failed ? Ink.orange : Ink.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.spring(duration: 0.5), value: at)
                    VStack(spacing: 0) {
                        Text("\(at * 25)%").font(.ui(size: 30, weight: .black, design: .rounded))
                        Text(b.upload == .done ? "erop" : b.upload == .failed ? "mislukt" : b.dirty ? "nog niet" : "erop").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                    }
                }
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(stages.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            Image(systemName: i < at ? "checkmark.circle.fill" : "circle").foregroundStyle(i < at ? Ink.green : Ink.dim)
                            Text(stages[i]).font(.ui(size: 14)).foregroundStyle(i < at ? Ink.text : Ink.dim)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { app.board.upload(app.project) } label: { Label(b.dirty ? "Zet op ESP32" : "Nog een keer", systemImage: "arrow.down.to.line") }
                            .buttonStyle(Filled(big: true)).disabled(!b.connected || b.flashing != nil)
                        Button { app.screen = .live } label: { Text("Bekijk live") }.buttonStyle(Soft())
                    }
                    if !b.uploadNote.isEmpty { Text(b.uploadNote).font(.ui(size: 14)).foregroundStyle(b.upload == .failed ? Ink.orange : Ink.dim) }
                }
            }
        }
    }

    func problem(_ p: Problem) -> some View {
        Card(border: Ink.orange) {
            Label(p.title, systemImage: "exclamationmark.triangle.fill").font(.ui(size: 17, weight: .bold)).foregroundStyle(Ink.orange)
            Text(p.text).font(.ui(size: 14))
            HStack(spacing: 10) {
                switch p.fix {
                case .flash: Button("Zet de firmware erop") { app.board.flash() }.buttonStyle(Filled())
                case .reconnect: Button("Verbind opnieuw") { app.board.connect() }.buttonStyle(Filled())
                case .unplugRing: Button("Laat zien waar de ring zit") { app.screen = .wiring }.buttonStyle(Soft())
                case .none: EmptyView()
                }
                Button { ask() } label: { Label(asking ? "Claude denkt na…" : "Vraag Claude", systemImage: "sparkles") }.buttonStyle(Soft()).disabled(asking)
            }
        }
    }

    func ask() {
        asking = true
        Task {
            defer { asking = false }
            do { advice = try await Claude.explain(log: app.board.log.suffix(60).map { ($0.out ? "> " : "") + $0.text }, project: app.project) }
            catch { advice = error.localizedDescription }
        }
    }

    var esp: some View {
        let b = app.board
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        return Card {
            HStack {
                Head("Je ESP32")
                Spacer()
                Button(b.connected ? "Verbreek" : "Verbind") { b.connected ? b.disconnect() : b.connect() }.buttonStyle(Soft())
            }
            fact("Verbonden", b.path.map { "met de USB-kabel (\(($0 as NSString).lastPathComponent))" } ?? "nee")
            fact("Soort", b.chip ?? "–")
            fact("Firmware", b.fw > 0 ? "Als-Dan \(b.fw)" : "–")
            fact("Erop gezet", b.uploadedAt.map { $0.formatted(time) } ?? "–")
            fact("Laatst opgestart", b.lastBoot.map { $0.formatted(time) } ?? "–")
            fact("Programma", b.programBytes > 0 ? "\(b.programBytes) van 3900 tekens" : "–")
            Button { ask() } label: { Label("Vraag Claude wat er gebeurt", systemImage: "sparkles") }.buttonStyle(.borderless).foregroundStyle(Ink.purple).disabled(asking || b.log.isEmpty)
        }
    }

    func fact(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(k).foregroundStyle(Ink.dim).frame(width: 120, alignment: .leading); Text(v).textSelection(.enabled) }.font(.ui(size: 13))
    }

    var firmware: some View {
        let b = app.board
        return Card {
            Head("Firmware")
            Text("Het programmaatje dat je regels leest. Eén keer nodig, of als de app erom vraagt.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            if let f = b.flashing { ProgressView(value: f).tint(Ink.cyan); Text("\(Int(f * 100))%").font(.ui(size: 12)).foregroundStyle(Ink.dim) }
            if !b.flashNote.isEmpty { Text(b.flashNote).font(.ui(size: 14)) }
            Button { b.flash() } label: { Label("Zet de firmware erop", systemImage: "cpu") }
                .buttonStyle(Filled()).disabled(b.flashing != nil)
            Text("Versie \(Board.firmwareVersion) zit in de app" + (b.fw > 0 && b.fw < Board.firmwareVersion ? ", de ESP32 heeft nog \(b.fw)" : "")).font(.ui(size: 12)).foregroundStyle(Ink.dim)
        }
    }

    var log: some View {
        let b = app.board, p = app.project
        let name = { (i: Int) -> String? in b.sent.flatMap { i < $0.devices.count ? p.device($0.devices[i])?.name : nil } }
        return Card {
            HStack {
                Head("ESP32 zegt")
                if b.connected { Text("live").font(.ui(size: 12, weight: .bold)).foregroundStyle(Ink.green) }
                Spacer()
                Picker("", selection: $technical) { Text("Gewone woorden").tag(false); Text("Technisch").tag(true) }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(b.log) { l in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(l.time, format: .dateTime.hour().minute().second()).font(.ui(size: 11, design: .monospaced)).foregroundStyle(Ink.dim)
                                Text(technical ? (l.out ? "→ " : "") + l.text : Plain.say(l.text, out: l.out, deviceName: name))
                                    .font(technical ? .system(size: 12, design: .monospaced) : .system(size: 13))
                                    .foregroundStyle(l.out ? Ink.cyan : l.text.hasPrefix("ERR") || l.text.hasPrefix("L ") ? Ink.orange : Ink.text)
                                    .textSelection(.enabled)
                            }
                            .id(l.id)
                        }
                    }
                }
                .onChange(of: b.log.count) { if let last = b.log.last { scroll.scrollTo(last.id, anchor: .bottom) } }
            }
            .frame(minHeight: 420, maxHeight: 640)
            if b.log.isEmpty { Text("Nog niets gehoord. Steek de USB-kabel in de Mac.").font(.ui(size: 14)).foregroundStyle(Ink.dim) }
        }
    }
}
