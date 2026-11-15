// Als-Dan voor de Mac: een wens wordt ALS-DAN-regels, de app tekent hoe je aansluit, zet de regels op de ESP32 en kijkt live mee.
import SwiftUI
import AlsDanCore

@main
struct AlsDanApp: App {
    @State private var app = AppState()
    @AppStorage("look") private var look = Look.system.rawValue

    init() { Font.registerBarlow() }

    var body: some Scene {
        WindowGroup("Als-Dan") {
            RootView().environment(app).font(.ui(size: 14))
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear { Look.apply(look) }
                .onChange(of: look) { Look.apply(look) }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Nieuw project") { app.newProject() }.keyboardShortcut("n") }
            CommandMenu("ESP32") {
                Button("Zet op ESP32") { app.board.upload(app.project) }.keyboardShortcut("u")
                Button(app.board.connected ? "Verbreek" : "Verbind") { app.board.connected ? app.board.disconnect() : app.board.connect() }
                Divider()
                Button("Zet de firmware erop…") { app.screen = .board; app.board.flash() }
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(Screen.allCases.enumerated()), id: \.1) { i, s in
                    Button(s.title) { app.screen = s }.keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                }
                Divider()
                Picker("Weergave", selection: $look) { ForEach(Look.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }
            }
        }
        Settings { SettingsView() }
    }
}

struct RootView: View {
    @Environment(AppState.self) var app
    @State private var renaming: Project?
    @State private var newName = ""

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            Group {
                switch app.screen {
                case .wish: WishView()
                case .rules: RulesView()
                case .sounds: SoundsView()
                case .wiring: WiringView()
                case .board: BoardView()
                case .live: LiveView()
                case .inventory: InventoryView()
                }
            }
            .navigationTitle(app.screen.title)
            .navigationSubtitle(app.screen == .inventory ? "Voor al je projecten" : app.project.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { status }
                ToolbarItem(placement: .primaryAction) {
                    Button { app.board.upload(app.project); app.screen = app.screen == .live ? .live : .board } label: { Text("Zet op ESP32") }
                        .buttonStyle(Filled()).disabled(!app.board.connected).help("Stuur de regels naar de ESP32 (Command-U)")
                }
            }
        }
        .task { await Snapshot.run(app) }
        .alert("Andere naam", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Naam", text: $newName)
            Button("Bewaar") { if let r = renaming, let i = app.projects.firstIndex(where: { $0.id == r.id }), !newName.isEmpty { app.projects[i].name = newName } }
            Button("Annuleer", role: .cancel) {}
        }
    }

    var status: some View {
        let on = app.board.connected
        return HStack(spacing: 7) {
            Circle().fill(on ? Ink.green : Ink.dim).frame(width: 7, height: 7)
            Text(app.board.flashing != nil ? "Firmware gaat erop" : on ? (app.board.dirty ? "Verbonden, nog niet verstuurd" : "ESP32 verbonden") : "Niet verbonden")
                .font(.ui(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12).frame(height: 28)
        .foregroundStyle(on ? Ink.green : Ink.dim)
        .background(on ? Ink.green.opacity(0.15) : Ink.well, in: ChamferedRect(cut: 7))
    }

    var sidebar: some View {
        @Bindable var app = app
        return List(selection: Binding<Screen?>(get: { app.screen }, set: { if let s = $0 { app.screen = s } })) {
            HStack(spacing: 12) {
                Rings(thought: app.thought, wired: app.wired, tested: app.tested)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.project.name).font(.ui(size: 15, weight: .bold)).lineLimit(1)
                    Text("Bedacht · Aangesloten · Getest").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: ChamferedRect(cut: 14))
            .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 10, trailing: 4))
            .selectionDisabled()

            Section("Stappen") {
                ForEach(Screen.allCases.filter { $0 != .inventory }) { s in row(s) }
            }
            Section("Mijn spullen") { row(.inventory) }
            Section("Projecten") {
                ForEach(app.projects) { p in
                    Button { app.currentID = p.id; if app.screen == .inventory { app.screen = .wish } } label: {
                        Label(p.name, systemImage: "folder").foregroundStyle(p.id == app.currentID ? Ink.ringThought : Ink.text)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Andere naam…") { newName = p.name; renaming = p }
                        Button("Verwijder", role: .destructive) {
                            app.projects.removeAll { $0.id == p.id }
                            if app.projects.isEmpty { app.newProject() } else if app.currentID == p.id { app.currentID = app.projects[0].id }
                        }
                    }
                }
                Button { app.newProject() } label: { Label("Nieuw project", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(Ink.cyan)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { connection }
    }

    func row(_ s: Screen) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.85))
                .frame(width: 24, height: 24).background(s.tint, in: ChamferedRect(cut: 7))
            Text(s.title)
            Spacer()
            switch s {
            case .wish where !app.project.rules.isEmpty, .rules where app.thought == 1:
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Ink.green)
            case .wiring:
                let all = app.wiresToDo
                Text("\(all.filter(app.project.doneWires.contains).count) van \(all.count)").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            case .inventory: Text("\(app.parts.count)").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            default: EmptyView()
            }
        }
        .tag(s)
    }

    var connection: some View {
        let b = app.board
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(b.connected ? Ink.green : Ink.dim).frame(width: 8, height: 8)
                Text(b.connected ? "ESP32 verbonden" : "ESP32 niet verbonden").font(.ui(size: 13, weight: .semibold))
            }
            Text(b.connected ? "Via USB" + (b.fw > 0 ? " · firmware \(b.fw)" : "") : "Steek de USB-kabel in de Mac").font(.ui(size: 12)).foregroundStyle(Ink.dim)
            if let f = b.flashing { ProgressView(value: f).tint(Ink.cyan) }
            if app.ears.listening {
                HStack(spacing: 6) {
                    Image(systemName: "ear").foregroundStyle(Ink.pink)
                    Text("De Mac luistert mee").font(.ui(size: 12)).foregroundStyle(Ink.dim)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: ChamferedRect(cut: 14))
        .padding(12)
    }
}

struct SettingsView: View {
    @State private var key = Keychain.read() ?? ""
    @State private var saved = false
    @AppStorage("look") private var look = Look.system.rawValue
    var body: some View {
        Form {
            Section("Weergave") {
                Picker("Licht of donker", selection: $look) { ForEach(Look.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }
                    .pickerStyle(.segmented)
                    .onChange(of: look) { Look.apply(look) }
            }
            Section {
                SecureField("Sleutel voor Claude", text: $key, prompt: Text("sk-ant-…"))
                HStack {
                    Button("Bewaar") { Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines)); saved = true }
                    if saved { Text("Bewaard in je sleutelhanger").foregroundStyle(.secondary) }
                }
            } header: { Text("Claude") } footer: {
                Text("Maak een sleutel op console.anthropic.com. Hij blijft op deze Mac, in de sleutelhanger. Claude (\(Claude.model)) maakt regels van een wens, herkent onderdelen op een foto en legt uit wat de ESP32 zegt.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
