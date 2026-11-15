// De ESP32 aan de USB: verbinden, regels erop zetten, testen, meelezen wat hij zegt, en de firmware erop zetten met esptool.
import Foundation
import AlsDanCore

// Een seriële poort (115200 baud) met de POSIX-functies van macOS. Regels komen binnen op de main queue.
final class SerialPort {
    let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private let writes = DispatchQueue(label: "alsdan.serial.write")
    var onLine: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(path: String) { self.path = path }

    // De USB-chips op ESP32-bordjes: CP210x (usbserial, SLAB), CH340 (wchusbserial) en de eigen USB van de S2/S3 (usbmodem).
    static func candidates() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.") && ["usbserial", "SLAB", "wchusbserial", "usbmodem"].contains(where: $0.contains) }.sorted().map { "/dev/" + $0 }
    }

    func open() throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(B115200))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(fd, TCSANOW, &t)
        var bits: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = withUnsafeMutablePointer(to: &bits) { ioctl(fd, 0x8004_746B, $0) }   // TIOCMBIC: DTR en RTS laag, anders blijft het bordje in reset hangen
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in self?.read() }
        src.setCancelHandler { [fd] in Darwin.close(fd) }
        source = src
        src.resume()
    }

    func close() {
        source?.cancel()
        source = nil
    }

    func send(_ text: String) {
        let data = Array((text.hasSuffix("\n") ? text : text + "\n").utf8), fd = fd
        writes.async {
            var off = 0, tries = 0
            while off < data.count && tries < 500 {
                let n = data[off...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n > 0 { off += n } else { tries += 1; usleep(5000) }   // de buffer zit vol: even wachten
            }
        }
    }

    private func read() {
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = Darwin.read(fd, &buf, buf.count)
        if n <= 0 {
            if n == 0 || errno != EAGAIN { close(); onClose() }   // kabel eruit
            return
        }
        buffer.append(contentsOf: buf[0..<n])
        while let i = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[buffer.startIndex..<i], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(buffer.startIndex...i)
            if !line.isEmpty { onLine(line) }
        }
    }
}

struct LogLine: Identifiable { let id = UUID(); let time = Date(); let text: String; let out: Bool }

@Observable @MainActor final class Board {
    enum Upload: Int { case idle, packing, sending, saving, done, failed }

    var path: String?            // verbonden met deze poort
    var chip: String?
    var fw = 0                   // de firmware die de ESP32 meldt, 0 = nog niet gehoord
    var lastBoot: Date?
    var log: [LogLine] = []
    var values: [Int: Int] = [:]                 // onderdeel (volgorde van het verstuurde programma) → laatste waarde
    var history: [Int: [(Date, Int)]] = [:]      // de laatste minuut
    var upload = Upload.idle
    var uploadNote = ""
    var uploadedAt: Date?
    var programBytes = 0
    var flashing: Double?        // 0…1 zolang de firmware erop gaat
    var flashNote = ""
    var sent: (rules: [String], devices: [String])?
    var dirty = true             // het project veranderde na het versturen
    var autoConnect = true
    @ObservationIgnored var onFired: (String) -> Void = { _ in }

    @ObservationIgnored private var port: SerialPort?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var uploadTimeout: Task<Void, Never>?

    static let firmwareVersion = 2   // web/firmware, zie manifest.json
    var connected: Bool { path != nil }
    var problems: [Problem] { Plain.problems(log.filter { !$0.out && $0.time > Date().addingTimeInterval(-600) }.map(\.text)) }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.autoConnect, !self.connected, self.flashing == nil, let p = SerialPort.candidates().first else { return }
                self.connect(p)
            }
        }
        timer?.fire()
    }

    func connect(_ p: String? = nil) {
        guard let p = p ?? SerialPort.candidates().first else { note("Ik zie geen ESP32. Zit de USB-kabel erin? Sommige kabels kunnen alleen opladen."); return }
        let s = SerialPort(path: p)
        do { try s.open() } catch {
            note("De poort gaat niet open: \(String(cString: strerror(Int32((error as NSError).code))))")   // Resource busy of Permission denied: zie Plain.problems
            autoConnect = false
            return
        }
        s.onLine = { [weak self] in self?.handle($0) }
        s.onClose = { [weak self] in self?.dropped() }
        port = s
        path = p
        autoConnect = true
        fw = 0
        dirty = true
        Task { try? await Task.sleep(for: .seconds(1.2)); self.send("HELLO") }
    }

    func disconnect() {
        port?.close()
        port = nil
        path = nil
        chip = nil
        autoConnect = false
    }

    private func dropped() {
        port = nil
        path = nil
        chip = nil
        note("De ESP32 is losgekoppeld.")
    }

    func send(_ text: String) {
        guard let port else { return }
        for l in text.split(separator: "\n") { log.append(LogLine(text: String(l), out: true)) }
        trim()
        port.send(text)
    }

    func upload(_ p: Project) {
        guard connected else { upload = .failed; uploadNote = "De ESP32 zit niet aan de Mac. Steek de USB-kabel erin."; return }
        if fw > 0, let old = p.devices.first(where: { $0.kind.info.fw > fw }) {
            upload = .failed; uploadNote = "Voor \(old.name) moet er nieuwe firmware op de ESP32. Klik op Zet de firmware erop."; return
        }
        upload = .packing
        let e = p.encode()
        sent = (e.rules, p.devices.map(\.id))
        programBytes = e.text.utf8.count
        values = [:]
        history = [:]
        upload = .sending
        send(e.text)
        upload = .saving
        uploadNote = e.skipped.isEmpty ? "" : "\(e.skipped.count) regel(s) zijn nog niet af, die gaan niet mee."
        uploadTimeout?.cancel()
        uploadTimeout = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled && self.upload == .saving { self.upload = .failed; self.uploadNote = "De ESP32 zei niets terug. Staat de Als-Dan-firmware erop?" }
        }
    }

    // Eén of meer stappen nu laten doen (testknop). Is het project veranderd, dan eerst het programma erop, anders kloppen de nummers niet.
    func test(_ steps: [String], project: Project) async {
        guard connected, !steps.isEmpty else { return }
        if dirty || sent == nil {
            upload(project)
            try? await Task.sleep(for: .milliseconds(500))
        }
        send("X " + steps.joined(separator: " ; "))
    }

    private func handle(_ line: String) {
        let msg = Msg.parse(line)
        if case .sensor(let d, let v) = msg {
            values[d] = v
            let now = Date()
            history[d, default: []].append((now, v))
            history[d]!.removeAll { $0.0 < now.addingTimeInterval(-60) }
            return   // vier keer per seconde: niet in het logboek
        }
        log.append(LogLine(text: line, out: false))
        trim()
        switch msg {
        case .hi(let f, let c): fw = f; chip = c
        case .ok(let s) where !s.isEmpty:
            upload = .done; dirty = false; uploadedAt = Date(); uploadTimeout?.cancel()
        case .err:
            if upload == .saving || upload == .sending { upload = .failed; uploadNote = Plain.say(line); uploadTimeout?.cancel() }
        case .fired(let r):
            if let rules = sent?.rules, r < rules.count { onFired(rules[r]) }
        case .other(let s) where s.hasPrefix("rst:"): lastBoot = Date()
        default: break
        }
    }

    private func note(_ text: String) { log.append(LogLine(text: "L " + text, out: false)); trim() }
    private func trim() { if log.count > 600 { log.removeFirst(log.count - 500) } }

    // ---- firmware ----------------------------------------------------------

    static var esptool: URL? {
        if let u = Bundle.main.url(forResource: "esptool", withExtension: nil) { return u }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Arduino15/packages/esp32/tools/esptool_py")
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
        return versions.last.map { dir.appendingPathComponent($0).appendingPathComponent("esptool") }
    }

    // Zelfde delen en plekken als web/firmware/manifest.json.
    static let parts: [(offset: String, file: String)] = [("0x1000", "bootloader.bin"), ("0x8000", "partitions.bin"), ("0xe000", "boot_app0.bin"), ("0x10000", "alsdan.bin")]
    @ObservationIgnored private var flashSizes: [Int] = []
    @ObservationIgnored private var flashDone = 0
    @ObservationIgnored private var flashBuffer = ""

    func flash() {
        guard let p = path ?? SerialPort.candidates().first else { flashNote = "Steek eerst de USB-kabel van de ESP32 in de Mac."; return }
        guard let tool = Board.esptool, FileManager.default.isExecutableFile(atPath: tool.path),
              let dir = Bundle.main.url(forResource: "firmware", withExtension: nil) else { flashNote = "esptool of de firmware ontbreekt in de app. Bouw de app opnieuw met build.sh."; return }
        disconnect()
        flashing = 0
        flashNote = "Verbinden met de ESP32…"
        flashSizes = Board.parts.map { (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($0.file).path)[.size] as? Int) ?? 0 }
        flashDone = 0
        let proc = Process()
        proc.executableURL = tool
        proc.arguments = ["--chip", "esp32", "--port", p, "--baud", "460800", "write-flash"] + Board.parts.flatMap { [$0.offset, dir.appendingPathComponent($0.file).path] }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            Task { @MainActor in self.flashOutput(s) }
        }
        proc.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self.flashFinished(proc.terminationStatus) }
        }
        do { try proc.run() } catch { flashing = nil; flashNote = "esptool start niet: \(error.localizedDescription)"; autoConnect = true }
    }

    private func flashOutput(_ s: String) {
        flashBuffer += s
        var pieces = flashBuffer.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
        flashBuffer = pieces.removeLast()
        let total = Double(max(flashSizes.reduce(0, +), 1))
        for l in pieces.map({ $0.trimmingCharacters(in: .whitespaces) }) where !l.isEmpty {
            if l.hasPrefix("Writing at"), let r = l.range(of: #"[0-9.]+(?=\s?%)"#, options: .regularExpression), let pct = Double(l[r]), flashDone < flashSizes.count {
                flashing = (Double(flashSizes.prefix(flashDone).reduce(0, +)) + pct / 100 * Double(flashSizes[flashDone])) / total
                flashNote = "Bezig met schrijven…"
                continue
            }
            if l.hasPrefix("Wrote ") { flashDone += 1 }
            if l.hasPrefix("Connected to") || l.hasPrefix("Chip type") { flashNote = "Verbonden, nu schrijven." }
            log.append(LogLine(text: l, out: false))
        }
        trim()
    }

    private func flashFinished(_ status: Int32) {
        flashing = nil
        flashNote = status == 0 ? "De firmware staat erop. De ESP32 start opnieuw." : "Het lukte niet. Kijk hieronder wat er misging."
        autoConnect = true
        dirty = true
    }
}
