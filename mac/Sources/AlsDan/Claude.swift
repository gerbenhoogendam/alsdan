// Claude via de Messages API (Swift heeft geen SDK, dus gewoon HTTP): een wens wordt regels, een foto wordt een onderdeel
// met de kleuren van zijn draadjes, en een logboek wordt uitleg in gewone woorden. De sleutel staat in de sleutelhanger.
import Foundation
import Security
import AlsDanCore

enum Keychain {
    static let service = "Als-Dan Claude API key"
    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
    static func write(_ v: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(q as CFDictionary)
        guard !v.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct ClaudeError: LocalizedError { let errorDescription: String? }

enum Claude {
    static let model = "claude-opus-5-5"
    static var key: String? { Keychain.read() ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }

    // Eén vraag, één antwoord. Met `schema` komt het antwoord als JSON in die vorm terug. Opus 5.5 denkt altijd na; `effort` zegt hoe diep.
    static func ask(system: String, _ content: [[String: Any]], schema: [String: Any]? = nil, effort: String = "medium") async throws -> String {
        guard let key, !key.isEmpty else { throw ClaudeError(errorDescription: "Er is nog geen sleutel voor Claude. Zet hem in Instellingen (Command-komma).") }
        var output: [String: Any] = ["effort": effort]
        if let schema { output["format"] = ["type": "json_schema", "schema": schema] }
        let body: [String: Any] = ["model": model, "max_tokens": 16000, "system": system, "output_config": output,
                                   "messages": [["role": "user", "content": content]]]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 300)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
            throw ClaudeError(errorDescription: "Claude is niet te bereiken. Is er internet? (\(error.localizedDescription))")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "fout \(status)"
            throw ClaudeError(errorDescription: status == 401 ? "De sleutel voor Claude klopt niet. Kijk hem na in Instellingen." : "Claude zegt: \(msg)")
        }
        switch json["stop_reason"] as? String {
        case "refusal": throw ClaudeError(errorDescription: "Claude wil hier niet aan meewerken. Probeer het anders te zeggen.")
        case "max_tokens": throw ClaudeError(errorDescription: "Het antwoord werd te lang. Probeer een kortere wens.")
        default: break
        }
        guard let text = (json["content"] as? [[String: Any]])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw ClaudeError(errorDescription: "Claude gaf geen antwoord.")
        }
        return text
    }

    // ---- schema-hulpjes: elk veld verplicht, niets extra ----
    static let str: [String: Any] = ["type": "string"], num: [String: Any] = ["type": "number"]
    static func obj(_ p: [String: Any]) -> [String: Any] { ["type": "object", "additionalProperties": false, "required": Array(p.keys), "properties": p] }
    static func arr(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    static func one(of v: [String]) -> [String: Any] { ["type": "string", "enum": v] }

    // ---- wens → regels ----

    struct Plan: Decodable {
        struct Dev: Decodable { let ref, kind, name: String }
        struct Trig: Decodable { let kind, device: String; let value: Double; let sound: String }
        struct St: Decodable { let kind, device: String; let value: Double; let color, sound: String }
        struct R: Decodable { let trigger: Trig; let steps: [St] }
        let summary: String
        let questions: [Question]
        let devices: [Dev]
        let rules: [R]
        let shopping: [String]
    }

    static func plan(wish: String, inventory: [Part], sounds: [Sound]) async throws -> Plan {
        let kinds = Kind.allCases.map { k -> String in
            let i = k.info
            let steps = StepKind.allCases.filter { $0.kinds?.contains(k) == true }.map(\.rawValue)
            return "- \(k.rawValue) (\(i.label)): ALS \(i.triggers.map(\.rawValue).joined(separator: ", ").ifEmpty("-")); DAN \(steps.joined(separator: ", ").ifEmpty("-"))"
                + (i.needs.map { ". Mag pas aan de ESP32 met \($0)" } ?? "") + (i.single ? ". Hooguit één." : "")
        }.joined(separator: "\n")
        let have = inventory.map { "- \($0.name)" + ($0.kind.map { " [\($0.rawValue)]" } ?? "") + " ×\($0.count)" + ($0.toBuy ? " (nog kopen)" : "") }.joined(separator: "\n")
        let system = """
        Je maakt van de wens van een kind (ongeveer 10 jaar) ALS-DAN-regels voor een ESP32-project, Als-Dan. Schrijf elke tekst in \
        eenvoudig Nederlands, kort, zonder vaktaal en zonder emoji.

        Onderdelen die de ESP32 kent (soort (naam): de ALS-triggers; de DAN-stappen):
        \(kinds)
        Altijd: ALS START (de ESP32 gaat aan), EVERY (elke zoveel seconden); DAN wait (wachten).

        Wat de Mac zelf doet, alleen zolang de ESP32 met de USB-kabel aan de Mac zit:
        - ALS HEARS: de microfoon van de Mac herkent een soort geluid. Zet `sound` op een van: \(MacEars.classes.map(\.id).joined(separator: ", ")).
        - DAN sound: de Mac speelt een geluid uit de bibliotheek. Zet `sound` op precies een van deze namen: \(sounds.map(\.name).joined(separator: ", ")).
        - DAN say: de computerstem van de Mac zegt de tekst in `sound`.
        Kies voor "als het hard is" LOUD met de microfoon van de ESP32 (mic). Voor een soort geluid (klappen, de deurbel, een blaffende \
        hond) HEARS. De ESP32 kan klappen niet tellen: maak van "twee keer klappen" één klap en zeg dat in summary.

        Velden: devices krijgen een eigen `ref` ("a", "b", …). trigger.device en step.device zijn zo'n ref; leeg ("") bij START, EVERY, \
        HEARS, wait, sound en say. value: EVERY seconden, NEAR/FAR cm, LOUD 0-100, dim/fwd/back procent, wait seconden (hooguit 10); \
        anders 0. color: "#rrggbb" bij color en spin, anders "". sound: alleen bij HEARS, sound en say, anders "".
        Gebruik bij voorkeur wat in de doos zit. Is iets nodig dat er niet in zit of nog gekocht moet worden, gebruik het toch en zet het \
        in shopping. summary: één zin over wat het project doet. questions: alleen als de wens onduidelijk is op een manier die de \
        regels verandert, hooguit twee, elk met twee of drie korte antwoorden; maak dan toch al je beste regels.

        In de doos:
        \(have)
        """
        let trig = obj(["kind": one(of: TriggerKind.allCases.map(\.rawValue)), "device": str, "value": num, "sound": str])
        let step = obj(["kind": one(of: StepKind.allCases.map(\.rawValue) + ["say"]), "device": str, "value": num, "color": str, "sound": str])
        let schema = obj(["summary": str,
                          "questions": arr(obj(["question": str, "answers": arr(str)])),
                          "devices": arr(obj(["ref": str, "kind": one(of: Kind.allCases.map(\.rawValue)), "name": str])),
                          "rules": arr(obj(["trigger": trig, "steps": arr(step)])),
                          "shopping": arr(str)])
        let text = try await ask(system: system, [["type": "text", "text": wish]], schema: schema)
        do { return try JSONDecoder().decode(Plan.self, from: Data(text.utf8)) } catch {
            throw ClaudeError(errorDescription: "Het antwoord van Claude was niet te lezen. Probeer het nog een keer.")
        }
    }

    // ---- foto → onderdeel ----

    struct Guess: Decodable { let kind, name: String; let wires: [String]; let note: String }

    static func recognise(jpeg: Data) async throws -> Guess {
        let kinds = Kind.allCases.map { k in
            "- \(k.rawValue) (\(k.info.label)): draadjes " + InventoryView.wires(Part(name: "", kind: k)).map(\.lab).joined(separator: ", ").ifEmpty("geen")
        }.joined(separator: "\n")
        let system = """
        Je herkent een elektronica-onderdeel op een foto voor een kind van 10. Soorten die de app kent, met hun draadjes in volgorde:
        \(kinds)
        kind: een van die soorten, of "anders". name: een korte Nederlandse naam. wires: de kleur van elk draadje dat aan het onderdeel \
        vastzit, in de volgorde van de draadjes van die soort; "onbekend" als je het niet ziet; een lege lijst bij "anders" of als er \
        geen draadjes aan zitten. note: één korte zin voor het kind, bijvoorbeeld over welk draadje je twijfelt. Geen emoji.
        """
        let schema = obj(["kind": one(of: Kind.allCases.map(\.rawValue) + ["anders"]), "name": str,
                          "wires": arr(one(of: WIRE_COLORS.map(\.name) + ["onbekend"])), "note": str])
        let text = try await ask(system: system, [["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                                                  ["type": "text", "text": "Wat is dit, en welke kleur hebben de draadjes?"]], schema: schema, effort: "low")
        do { return try JSONDecoder().decode(Guess.self, from: Data(text.utf8)) } catch {
            throw ClaudeError(errorDescription: "Het antwoord van Claude was niet te lezen. Probeer het nog een keer.")
        }
    }

    // ---- logboek → uitleg ----

    static func explain(log: [String], project: Project) async throws -> String {
        let devices = project.devices.map { d in "- \(d.name): " + Project.wires(d).map { "\($0.lab) → \($0.esp)" }.joined(separator: ", ") }.joined(separator: "\n")
        let system = """
        Je helpt een kind van 10 en zijn vader met hun ESP32 (een DevKit V1 met de Als-Dan-firmware). Leg in eenvoudig Nederlands uit \
        wat er mis is en wat ze moeten doen, in hooguit vijf korte zinnen. Zeg eerst het gewone woord en zet een vakterm tussen haakjes. \
        Geen emoji. Is er niets mis, zeg dat dan.

        Hun onderdelen en draadjes:
        \(devices)

        Het programma:
        \(project.encode().text)
        """
        return try await ask(system: system, [["type": "text", "text": "Dit zei de ESP32 net:\n" + log.joined(separator: "\n")]], effort: "low")
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }
