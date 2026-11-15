// Om na te kijken zonder schermopname: ALSDAN_SNAPSHOT=/een/map build/Als-Dan.app/Contents/MacOS/Als-Dan maakt van elk scherm een
// plaatje van wat het venster zelf tekent, en stopt dan. De Mac luistert dan niet mee (geen vraag om de microfoon).
import AppKit

enum Snapshot {
    static let folder = ProcessInfo.processInfo.environment["ALSDAN_SNAPSHOT"]

    @MainActor static func run(_ app: AppState) async {
        guard let folder else { return }
        try? await Task.sleep(for: .seconds(1.5))
        for look in [Look.light, .dark] {
            Look.apply(look.rawValue)
            for s in Screen.allCases {
                app.screen = s
                try? await Task.sleep(for: .seconds(1))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(s.rawValue)-\(look == .light ? "licht" : "donker").png"))
            }
        }
        NSApp.terminate(nil)
    }
}
