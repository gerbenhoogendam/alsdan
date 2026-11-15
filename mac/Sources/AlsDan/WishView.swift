// Stap 1, Wens: vertel in je eigen woorden wat je project moet doen, en Claude maakt er ALS-DAN-regels van.
import SwiftUI
import AlsDanCore

struct WishView: View {
    @Environment(AppState.self) var app
    static let ideas: [(String, String, Color)] = [
        ("Klap en de ring wordt een regenboog", "Als ik klap, wordt de lichtring een regenboog. Na tien tellen gaat hij weer uit.", Ink.orange),
        ("Zeg hallo als iemand dichtbij komt", "Als iemand dichtbij komt, zegt de computer hallo en wordt de ring groen.", Ink.cyan),
        ("Een alarm voor de koekjestrommel", "Als iemand bij de koekjestrommel komt, gaat er een sirene af en knippert het rode lampje.", Ink.pink),
    ]

    var body: some View {
        @Bindable var app = app
        Page(title: "Wat moet je project doen?", intro: "Vertel het in je eigen woorden. Claude maakt er ALS-DAN-regels van.") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    Card(border: Ink.purple) {
                        Text("Jouw wens").font(.ui(size: 13, weight: .bold)).foregroundStyle(Ink.purple)
                        TextEditor(text: $app.project.wish)
                            .font(.ui(size: 21, weight: .medium)).scrollContentBackground(.hidden).frame(minHeight: 130)
                            .overlay(alignment: .topLeading) {
                                if app.project.wish.isEmpty { Text("Als … dan …").font(.ui(size: 21, weight: .medium)).foregroundStyle(Ink.dim).padding(.leading, 5).allowsHitTesting(false) }
                            }
                        HStack(spacing: 12) {
                            Label("Praten in plaats van typen: druk twee keer op de Fn-toets", systemImage: "mic").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                            Spacer()
                            if app.thinking { ProgressView().controlSize(.small); Text("Claude denkt na…").font(.ui(size: 12)).foregroundStyle(Ink.dim) }
                            Button { Task { await app.makeRules() } } label: {
                                Label(app.project.rules.isEmpty ? "Maak er regels van" : "Maak opnieuw", systemImage: "sparkles")
                            }
                            .buttonStyle(Filled(big: true))
                            .disabled(app.thinking || app.project.wish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let p = app.claudeProblem {
                            Text(p).font(.ui(size: 14)).foregroundStyle(Ink.orange)
                        }
                    }

                    if !app.project.questions.isEmpty {
                        Card {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").foregroundStyle(Ink.purple).frame(width: 32, height: 32).background(Ink.purple.opacity(0.15), in: Circle())
                                VStack(alignment: .leading) {
                                    Text("Claude vraagt nog \(app.project.questions.count == 1 ? "iets" : "\(app.project.questions.count) dingen")").font(.ui(size: 15, weight: .bold))
                                    Text("Kies een antwoord, of typ het hierboven in je wens.").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                                }
                            }
                            ForEach(app.project.questions, id: \.self) { q in
                                Text(q.question).font(.ui(size: 14))
                                HStack { ForEach(q.answers, id: \.self) { a in Button(a) { Task { await app.answer(q, a) } }.buttonStyle(Chip()).disabled(app.thinking) } }
                            }
                        }
                    }

                    Caps("Ideeën om te proberen")
                    HStack(spacing: 12) {
                        ForEach(Self.ideas, id: \.0) { title, wish, tint in
                            Button { app.project.wish = wish } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: "lightbulb").foregroundStyle(.black.opacity(0.8)).frame(width: 32, height: 32).background(tint, in: ChamferedRect(cut: 10))
                                    Text(title).font(.ui(size: 14)).multilineTextAlignment(.leading)
                                }
                                .padding(16).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .background(Ink.card, in: ChamferedRect(cut: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                made.frame(width: 400)
            }
        }
    }

    var made: some View {
        let p = app.project, e = p.encode()
        let soundSteps = p.rules.flatMap(\.steps).filter { $0.kind == .sound }.count
        return Card {
            HStack(alignment: .firstTextBaseline) {
                Head("Wat Claude ervan maakt")
                Spacer()
                Text(p.summary.isEmpty ? "nog niets" : "net bijgewerkt").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            }
            HStack(spacing: 10) {
                Stat(label: "Regels", value: "\(e.rules.count + e.macRules.count)", color: Ink.orange)
                Stat(label: "Onderdelen", value: "\(p.devices.count)", color: Ink.green)
                Stat(label: "Geluiden", value: "\(soundSteps)", color: Ink.pink)
            }
            if !p.summary.isEmpty { Text(p.summary).font(.ui(size: 14)).foregroundStyle(Ink.text) }
            ForEach(p.rules) { r in
                Well {
                    HStack(spacing: 10) { Tag("ALS"); Text(sentence(r.trigger, p)).font(.ui(size: 14)) }
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 10) { Tag("DAN"); Text(sentence(s, p, sound: app.sound)).font(.ui(size: 14)) }
                    }
                }
            }
            if !p.devices.isEmpty || !p.shopping.isEmpty {
                Caps("Onderdelen")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(p.devices) { d in
                        VStack(spacing: 6) {
                            PartPicture(kind: d.kind, photo: app.part(for: d.kind)?.photo)
                            Text(d.name).font(.ui(size: 11)).foregroundStyle(Ink.dim).lineLimit(1)
                        }
                    }
                    ForEach(p.shopping, id: \.self) { s in
                        VStack(spacing: 6) {
                            Image(systemName: "cart").foregroundStyle(Ink.orange).frame(width: 64, height: 64)
                                .background(Ink.orange.opacity(0.14), in: ChamferedRect(cut: 14))
                                .overlay(ChamferedRect(cut: 14).strokeBorder(Ink.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            Text(s).font(.ui(size: 11)).foregroundStyle(Ink.orange).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .help("Nog kopen: \(s)")
                    }
                }
            }
            Label("Welke pinnetjes en weerstandjes je nodig hebt, rekent de app zelf uit.", systemImage: "checkmark")
                .font(.ui(size: 13)).foregroundStyle(Ink.green)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Ink.green.opacity(0.14), in: ChamferedRect(cut: 12))
            Button { app.screen = .rules } label: { Text("Bekijk de regels  →").frame(maxWidth: .infinity) }.buttonStyle(Filled(big: true))
        }
    }
}
