// Stap 3, Geluiden: de geluiden van de Mac, je eigen opnames en de computerstem. De Mac speelt ze als de regel afgaat. En wat de
// oren van de Mac kunnen horen, om te proberen.
import SwiftUI
import AVFoundation
import AlsDanCore

struct SoundsView: View {
    @Environment(AppState.self) var app
    @State private var filter = 0
    @State private var recName = ""
    @State private var recFile: String?
    @State private var recSeconds = 0.0
    @State private var recProblem: String?
    @State private var started = Date()
    @State private var say = "Wie ben jij?"
    @State private var voice = AVSpeechSynthesisVoice(language: "nl-NL")?.identifier ?? ""

    var body: some View {
        let used = Set(app.project.rules.flatMap(\.steps).compactMap(\.sound))
        let groups: [(String, [Sound])] = [("Alles", app.allSounds), ("Van de Mac", Sound.library), ("Jouw opnames", app.sounds.filter { $0.file != nil }),
                                           ("Computerstem", app.sounds.filter { $0.text != nil })]
        Page(title: "Geluiden", intro: "Kies een geluid, neem er zelf een op, of laat de computer iets zeggen. De Mac speelt ze af als een regel afgaat.") {
            HStack(alignment: .top, spacing: 20) {
                Card {
                    HStack { ForEach(groups.indices, id: \.self) { i in Button("\(groups[i].0)  \(groups[i].1.count)") { filter = i }.buttonStyle(Chip(on: filter == i)) } }
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(groups[filter].1) { s in row(s, used: used.contains(s.id)) }
                        }
                    }
                    .frame(minHeight: 300, maxHeight: 520)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    record
                    speak
                    ears
                }
                .frame(width: 380)
            }
        }
        .onAppear { app.listenScreens = true }
        .onDisappear { app.listenScreens = false }
    }

    func row(_ s: Sound, used: Bool) -> some View {
        HStack(spacing: 12) {
            Button { app.player.play(s, folder: AppState.recordings) } label: { Image(systemName: "play.fill").frame(width: 34, height: 34).background(Ink.pink.opacity(0.18), in: Circle()) }
                .buttonStyle(.plain).foregroundStyle(Ink.pink).help("Speel af")
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(.ui(size: 14, weight: .semibold))
                Text(s.kindLabel + (s.seconds.map { " · " + num(($0 * 10).rounded() / 10) + " s" } ?? "")).font(.ui(size: 12)).foregroundStyle(Ink.dim)
            }
            Spacer()
            if used { Text("In je project").font(.ui(size: 12, weight: .semibold)).foregroundStyle(Ink.green) }
            if s.system == nil {
                Button(role: .destructive) {
                    if let f = s.file { try? FileManager.default.removeItem(at: AppState.recordings.appendingPathComponent(f)) }
                    app.sounds.removeAll { $0.id == s.id }
                } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Weg")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Ink.well, in: ChamferedRect(cut: 12))
    }

    var record: some View {
        let r = app.recorder
        return Card {
            Head("Zelf opnemen")
            HStack(spacing: 14) {
                Button {
                    if r.recording { recSeconds = r.stop() } else {
                        let f = UUID().uuidString + ".m4a"
                        Task {
                            recProblem = await r.start(to: AppState.recordings.appendingPathComponent(f))
                            if recProblem == nil { recFile = f; started = Date() }
                        }
                    }
                } label: {
                    Image(systemName: r.recording ? "stop.fill" : "mic.fill").font(.system(size: 22)).foregroundStyle(.white)
                        .frame(width: 60, height: 60).background(Ink.pink, in: Circle())
                }
                .buttonStyle(.plain).help(r.recording ? "Stop" : "Neem op")
                VStack(alignment: .leading, spacing: 4) {
                    if r.recording {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                            Text(num((Date().timeIntervalSince(started) * 10).rounded() / 10) + " s").font(.ui(size: 22, weight: .black, design: .rounded))
                        }
                        Capsule().fill(Ink.pink).frame(width: 12 + 200 * CGFloat(r.level), height: 6).animation(.linear(duration: 0.05), value: r.level)
                    } else {
                        Text(recFile == nil ? "Klik en zeg iets" : "Opgenomen: \(num((recSeconds * 10).rounded() / 10)) s").font(.ui(size: 15, weight: .semibold))
                        Text("Klik nog een keer om te stoppen.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                    }
                }
            }
            if let recProblem { Text(recProblem).font(.ui(size: 14)).foregroundStyle(Ink.orange) }
            if let f = recFile, !r.recording {
                TextField("Naam", text: $recName, prompt: Text("Hoe heet dit geluid?")).textFieldStyle(.roundedBorder)
                HStack {
                    Button { app.player.play(Sound(name: "", file: f), folder: AppState.recordings) } label: { Label("Luister", systemImage: "play.fill") }.buttonStyle(Soft())
                    Button("Opnieuw") { try? FileManager.default.removeItem(at: AppState.recordings.appendingPathComponent(f)); recFile = nil }.buttonStyle(Soft())
                    Spacer()
                    Button("Bewaar") {
                        app.sounds.append(Sound(name: recName.isEmpty ? "Mijn opname" : recName, file: f, seconds: recSeconds))
                        recFile = nil; recName = ""; filter = 2
                    }.buttonStyle(Filled())
                }
            }
        }
    }

    var speak: some View {
        Card {
            Head("Laat de computer praten")
            TextField("Wat moet hij zeggen?", text: $say).textFieldStyle(.roundedBorder)
            Picker("Stem", selection: $voice) { ForEach(Player.voices, id: \.identifier) { Text($0.name).tag($0.identifier) } }
            HStack {
                Button { app.player.play(Sound(name: "", text: say, voice: voice), folder: AppState.recordings) } label: { Label("Luister", systemImage: "play.fill") }.buttonStyle(Soft())
                Spacer()
                Button("Maak er een geluid van") { app.sounds.append(Sound(name: say, text: say, voice: voice)); filter = 3 }
                    .buttonStyle(Filled()).disabled(say.isEmpty)
            }
        }
    }

    var ears: some View {
        let e = app.ears
        return Card {
            Head("Wat de Mac kan horen")
            Text("Voor een regel met \u{201C}De Mac hoort\u{201D}. Klap eens, of fluit.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            if let p = e.problem { Text(p).font(.ui(size: 14)).foregroundStyle(Ink.orange) }
            HStack {
                Text("Nu hoor ik:").foregroundStyle(Ink.dim)
                Text(e.heard.map { h in MacEars.classes.contains { $0.id == h.id } ? MacEars.label(h.id) : "iets anders" } ?? "niets")
                    .font(.ui(size: 15, weight: .bold)).foregroundStyle(Ink.pink)
                Spacer()
                Text(e.heard.map { "\(Int($0.confidence * 100))% zeker" } ?? "").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            }
        }
    }
}
