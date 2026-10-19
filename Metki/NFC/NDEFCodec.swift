import CoreNFC
import Foundation

enum NDEFCodec {
    static func payload(for command: ComposeCommand) throws -> NFCNDEFPayload {
        switch command {
        case .text(let value):
            guard let payload = text(value) else { throw ComposerError(L10n.text("Не получилось собрать текст.")) }
            return payload
        case .uri(let value):
            guard let payload = uri(value) else { throw ComposerError(L10n.text("Не получилось собрать запись.")) }
            return payload
        case .wifi(let ssid, let password, let security):
            return wifi(ssid: ssid, password: password, security: security)
        case .contact(let name, let phone, let email):
            return vcard(name: name, phone: phone, email: email)
        }
    }

    static func text(_ string: String) -> NFCNDEFPayload? {
        NFCNDEFPayload.wellKnownTypeTextPayload(string: string, locale: Locale(identifier: "ru"))
    }

    static func uri(_ string: String) -> NFCNDEFPayload? {
        if let url = URL(string: string), let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) {
            return payload
        }
        return NFCNDEFPayload.wellKnownTypeURIPayload(string: string)
    }

    static func wifi(ssid: String, password: String, security: WiFiSecurity) -> NFCNDEFPayload {
        NFCNDEFPayload(
            format: .media,
            type: Data("application/vnd.wfa.wsc".utf8),
            identifier: Data(),
            payload: WiFiPayload.bytes(ssid: ssid, password: password, security: security)
        )
    }

    static func vcard(name: String, phone: String, email: String) -> NFCNDEFPayload {
        let body = RecordComposer.vcard(name: name, phone: phone, email: email)
        return NFCNDEFPayload(
            format: .media,
            type: Data("text/vcard".utf8),
            identifier: Data(),
            payload: Data(body.utf8)
        )
    }

    static func emptyMessage() -> NFCNDEFMessage {
        NFCNDEFMessage(records: [
            NFCNDEFPayload(format: .empty, type: Data(), identifier: Data(), payload: Data())
        ])
    }

    static func message(from records: [StoredRecord]) -> NFCNDEFMessage {
        let payloads = records.map { record in
            NFCNDEFPayload(
                format: NFCTypeNameFormat(rawValue: record.typeNameFormat) ?? .unknown,
                type: record.type,
                identifier: record.identifier,
                payload: record.payload
            )
        }
        return NFCNDEFMessage(records: payloads)
    }

    static func encodedLength(of records: [StoredRecord]) -> Int {
        message(from: records).length
    }

    static func storedRecord(from payload: NFCNDEFPayload) -> StoredRecord {
        let parsed = describe(payload)
        return StoredRecord(
            id: UUID(),
            kind: parsed.kind,
            title: parsed.title,
            detail: parsed.detail,
            typeNameFormat: payload.typeNameFormat.rawValue,
            type: payload.type,
            identifier: payload.identifier,
            payload: payload.payload
        )
    }

    private static func describe(_ payload: NFCNDEFPayload) -> (kind: RecordKind, title: String, detail: String) {
        let typeText = String(data: payload.type, encoding: .utf8) ?? ""
        if payload.typeNameFormat == .empty {
            return (.other, L10n.text("Пустая запись"), "")
        }
        if payload.typeNameFormat == .nfcWellKnown, typeText == "T" || payload.wellKnownTypeTextPayload().0 != nil {
            return (.text, payload.wellKnownTypeTextPayload().0 ?? readable(payload.payload) ?? L10n.text("Текст"), "")
        }
        if typeText == "application/vnd.wfa.wsc" {
            let network = WiFiPayload.fields(from: payload.payload)
            let title = network.ssid?.isEmpty == false ? network.ssid! : L10n.text("Сеть Wi‑Fi")
            return (.wifi, title, network.detail)
        }
        if typeText == "text/vcard" || typeText == "text/x-vcard" {
            let text = String(data: payload.payload, encoding: .utf8) ?? ""
            if let fields = RecordComposer.vcardFields(from: text) {
                return (.contact, fields.name, fields.detail)
            }
            return (.contact, L10n.text("Визитка"), typeText)
        }
        if let url = payload.wellKnownTypeURIPayload() ?? absoluteURI(payload) {
            return classify(url)
        }
        if let text = readable(payload.payload) {
            return (.other, text, typeText)
        }
        return (.other, typeText.isEmpty ? L10n.text("Данные") : typeText, Hex.spaced(payload.payload))
    }

    private static func absoluteURI(_ payload: NFCNDEFPayload) -> URL? {
        guard payload.typeNameFormat == .absoluteURI,
              let string = String(data: payload.payload, encoding: .utf8) else { return nil }
        return URL(string: string)
    }

    private static func classify(_ url: URL) -> (kind: RecordKind, title: String, detail: String) {
        switch url.scheme?.lowercased() {
        case "tel":
            return (.phone, url.absoluteString.replacingOccurrences(of: "tel:", with: ""), L10n.text("Телефон"))
        case "mailto":
            let address = url.absoluteString
                .replacingOccurrences(of: "mailto:", with: "")
                .components(separatedBy: "?").first ?? url.absoluteString
            return (.email, address.removingPercentEncoding ?? address, L10n.text("Почта"))
        case "sms":
            let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "body" }?
                .value
            let number = (url.absoluteString.components(separatedBy: "?").first ?? url.absoluteString)
                .replacingOccurrences(of: "sms:", with: "")
            return (.sms, number.removingPercentEncoding ?? number, body ?? "")
        case "geo":
            return (.geo, url.absoluteString.replacingOccurrences(of: "geo:", with: ""), L10n.text("Координаты"))
        default:
            return (.url, url.absoluteString, url.host ?? "")
        }
    }

    private static func readable(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        let printable = text.allSatisfy { character in
            character == "\n" || character == "\t" || character == "\r" || !character.isASCII || (character.asciiValue ?? 0) >= 32
        }
        return printable ? text : nil
    }
}
