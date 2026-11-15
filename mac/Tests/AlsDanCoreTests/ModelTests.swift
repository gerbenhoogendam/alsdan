// Dezelfde controles als web/test/logic.test.mjs, plus het protocol en de Mac-regels. swift test
import XCTest
@testable import AlsDanCore

final class ModelTests: XCTestCase {
    let ino = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../firmware/alsdan/alsdan.ino"), encoding: .utf8)

    func testKnopEnLampje() {
        let e = EXAMPLES[0].project().encode()
        XCTAssertEqual(e.text, "PROG\nD 0 BTN 0\nD 1 LED 2\nR PRESS 0 ; SET 1 100 ; WAIT 1000 ; SET 1 0\nRUN\n")
        XCTAssertEqual(e.rules.count, 1)
        XCTAssertEqual(e.skipped, [])
    }

    func testAlleVoorbeelden() throws {
        let re = try NSRegularExpression(pattern: #"^PROG\n(D \d+ [A-Z]+( -?\d+)*\n)+(R [A-Z]+( \d+)* ; .+\n)+RUN\n$"#)
        for ex in EXAMPLES {
            let e = ex.project().encode()
            XCTAssertEqual(e.skipped, [], ex.name)
            XCTAssertNotNil(re.firstMatch(in: e.text, range: NSRange(e.text.startIndex..., in: e.text)), ex.name)
        }
    }

    func testIederWoordStaatInDeFirmware() {
        for t in TriggerKind.allCases where t != .HEARS { XCTAssertTrue(ino.contains("\"\(t.rawValue)\""), t.rawValue) }
        for ex in EXAMPLES {
            for line in ex.project().encode().text.split(separator: "\n") where line.hasPrefix("R ") {
                for part in line.dropFirst(2).components(separatedBy: " ; ") {
                    let w = String(part.split(separator: " ")[0])
                    XCTAssertTrue(ino.contains("\"\(w)\""), w)
                }
            }
        }
        for k in Kind.allCases { XCTAssertTrue(ino.contains("\"\(k.info.type)\""), k.info.type) }
    }

    func testOnafRegelsGaanNietMee() {
        var m = Project(name: "t")
        let led = m.addDevice(.led)
        let r1 = m.addRule()
        let r2 = m.addRule(Trigger(.START), [Step(.on, dev: "d99")])
        let r3 = m.addRule(Trigger(.EVERY, value: 0.5), [Step(.on, dev: led.id), Step(.wait)])
        let e = m.encode()
        XCTAssertEqual(e.skipped, [r1.id, r2.id])
        XCTAssertEqual(e.rules, [r3.id])
        XCTAssertTrue(e.text.contains("R EVERY 500 ; SET 0 100 ; WAIT 1000\n"))
    }

    func testVrijePinnen() {
        var m = Project(name: "t")
        let a = m.addDevice(.led), b = m.addDevice(.led), mot = m.addDevice(.motor), btn = m.addDevice(.button)
        XCTAssertEqual(a.pin, 2)
        XCTAssertEqual(b.pin, 25)
        XCTAssertNotEqual(mot.pin, mot.pin2)
        XCTAssertEqual(btn.pin, 0)
        XCTAssertEqual(b.name, "Lampje 2")
    }

    func testDraadjesEnKleuren() {
        var m = Project(name: "t")
        let pir = m.addDevice(.pir), ring = m.addDevice(.ring), tof = m.addDevice(.tof), btn = m.addDevice(.button)
        XCTAssertEqual(Project.wires(pir).map { [$0.esp, $0.name] }, [["VIN", "rood"], ["D27", "geel"], ["GND", "zwart"]])
        XCTAssertEqual(Project.wires(ring).map { [$0.esp, $0.name] }, [["3V3", "oranje"], ["GND", "rood"], ["RX2", "wit"]])   // zoals gesoldeerd
        var r = ring
        r.colors = [2: "blauw", 0: "bestaat-niet"]
        XCTAssertEqual(Project.wires(r).map { $0.name }, ["oranje", "rood", "blauw"])
        XCTAssertEqual(Project.wires(r)[2].color, wireHex("blauw"))
        XCTAssertEqual(Project.wires(ring, owned: [2: "paars"])[2].name, "paars")   // uit de inventaris
        XCTAssertEqual(Project.wires(r, owned: [2: "paars"])[2].name, "blauw")      // wat hier gekozen is wint
        XCTAssertEqual(Project.wires(tof).map(\.esp), ["3V3", "GND", "D21", "D22"])
        XCTAssertNotEqual(Project.wires(tof)[2].color, Project.wires(tof)[3].color)
        XCTAssertNil(Project.wires(btn)[0].color)   // BOOT: niets aansluiten
        XCTAssertEqual(Project.wires(m.addDevice(.speaker))[0].inline, "een weerstand van 220 Ω")
        for k in Kind.allCases {
            var p = Project(name: "t")
            for w in Project.wires(p.addDevice(k)) { XCTAssertFalse(w.lab.isEmpty || w.esp.isEmpty, k.rawValue) }
        }
    }

    func testGndVerdeeldDanGedeeld() {
        var m = Project(name: "t")
        let pir = m.addDevice(.pir), ring = m.addDevice(.ring), led = m.addDevice(.led), tof = m.addDevice(.tof)
        let (rows, users) = m.plan()
        func gnd(_ d: Device) -> String? { rows[d.id]!.first { $0.pin == "GND" }?.key }
        XCTAssertEqual(gnd(pir), "GND:R")   // D27 zit van achteren gezien rechts
        XCTAssertEqual(gnd(ring), "GND:L")  // RX2 links
        XCTAssertEqual(gnd(led), "GND:L")   // D2 links, beide bezet: delen aan de eigen kant
        XCTAssertEqual(users["GND:L"]!.map(\.id), [ring.id, led.id, tof.id])
        XCTAssertEqual(users["3V3"]!.map(\.id), [ring.id, tof.id])
        XCTAssertEqual(users["VIN"]!.map(\.id), [pir.id])
        XCTAssertEqual(rows[pir.id]![1].key, "27")
    }

    func testMicrofoonVastePinnenEnVerhuizen() {
        var m = Project(name: "t")
        m.addDevice(.button); m.addDevice(.led)
        m.devices[0].pin = 32; m.devices[1].pin = 33
        let mic = m.addDevice(.mic)
        let (btn, led) = (m.devices[0], m.devices[1])
        XCTAssertTrue(![32, 33, 35].contains(btn.pin!) && ![32, 33, 35].contains(led.pin!) && btn.pin != led.pin)
        m.addRule(Trigger(.LOUD, dev: mic.id, value: 55), [Step(.on, dev: led.id)])
        let text = m.encode().text
        XCTAssertTrue(text.contains("\nD 2 MIC 32 33 35\n"))
        XCTAssertTrue(text.contains("\nR LOUD 2 55 ; SET 1 100\n"))
        XCTAssertEqual(Project.wires(mic).map { [$0.esp, $0.name] }, [["3V3", "rood"], ["GND", "zwart"], ["D35", "geel"], ["D32", "groen"], ["D33", "blauw"]])
        XCTAssertNotEqual(m.addDevice(.led).pin, 32)   // een nieuw lampje krijgt geen pin van de microfoon
    }

    func testMacRegelsEnGeluiden() {
        var m = Project(name: "t")
        let ring = m.addDevice(.ring)
        let hears = m.addRule(Trigger(.HEARS, sound: "clapping"), [Step(.rainbow, dev: ring.id)])
        let deaf = m.addRule(Trigger(.HEARS), [Step(.rainbow, dev: ring.id)])
        let play = m.addRule(Trigger(.START), [Step(.sound, sound: "s1"), Step(.wait, value: 2), Step(.sound, sound: "s2")])
        let e = m.encode()
        XCTAssertEqual(e.macRules, [hears.id])
        XCTAssertEqual(e.skipped, [deaf.id])
        XCTAssertEqual(e.rules, [play.id])
        XCTAssertTrue(e.text.contains("R START ; WAIT 0 ; WAIT 2000 ; WAIT 0\n"))
        XCTAssertEqual(Project.delay(before: 2, in: m.rules[2].steps), 2)
        XCTAssertNil(m.encode(Step(.sound)))   // een geluid kiezen hoort erbij
    }

    func testProtocol() {
        XCTAssertEqual(Msg.parse("HI alsdan 2 ESP32-D0WD-V3"), .hi(fw: 2, chip: "ESP32-D0WD-V3"))
        XCTAssertEqual(Msg.parse("S 3 -1"), .sensor(dev: 3, value: -1))
        XCTAssertEqual(Msg.parse("E 0"), .fired(rule: 0))
        XCTAssertEqual(Msg.parse("OK 3 onderdelen, 2 regels"), .ok("3 onderdelen, 2 regels"))
        XCTAssertEqual(Plain.say("OK 3 onderdelen, 2 regels"), "Gelukt: 3 onderdelen en 2 regels staan op de ESP32.")
        XCTAssertEqual(Plain.problems(["Brownout detector was triggered", "x", "Brownout detector was triggered"]).map(\.fix), [.unplugRing])
        XCTAssertEqual(Plain.problems(["ERR onbekend: R LOUD 0 60 ; SET 1 100"]).first?.fix, .flash)
    }
}
