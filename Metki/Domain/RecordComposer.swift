import Foundation

struct ComposerError: LocalizedError, Equatable {
    var errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

enum ComposeCommand: Equatable {
    case text(String)
    case uri(String)
    case wifi(ssid: String, password: String, security: WiFiSecurity)
    case contact(name: String, phone: String, email: String)
}

struct VCardFields: Equatable {
    var name: String
    var phone: String
    var email: String

    var detail: String {
        [phone, email].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum RecordComposer {
    static func text(_ raw: String) throws -> ComposeCommand {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ComposerError(L10n.text("Введите текст.")) }
        return .text(value)
    }

    static func url(_ raw: String) throws -> ComposeCommand {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ComposerError(L10n.text("Не похоже на адрес.")) }
        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let parsed = URL(string: value), let host = parsed.host, !host.isEmpty else {
            throw ComposerError(L10n.text("Не похоже на адрес."))
        }
        return .uri(parsed.absoluteString)
    }

    static func phone(_ raw: String) throws -> ComposeCommand {
        let number = raw.filter { $0.isNumber || $0 == "+" }
        guard number.filter(\.isNumber).count >= 5 else { throw ComposerError(L10n.text("Введите номер.")) }
        return .uri("tel:\(number)")
    }

    static func email(_ raw: String) throws -> ComposeCommand {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !address.hasPrefix("@"), !address.hasSuffix("@") else {
            throw ComposerError(L10n.text("Введите почту."))
        }
        return .uri("mailto:\(address)")
    }

    static func sms(number rawNumber: String, body rawBody: String) throws -> ComposeCommand {
        let number = rawNumber.filter { $0.isNumber || $0 == "+" }
        guard number.filter(\.isNumber).count >= 5 else { throw ComposerError(L10n.text("Введите номер.")) }
        return .uri(smsURI(number: number, body: rawBody))
    }

    static func smsURI(number: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "sms:\(number)" }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        return "sms:\(number)?body=\(encoded)"
    }

    static func geo(latitude rawLat: String, longitude rawLon: String) throws -> ComposeCommand {
        guard let lat = number(rawLat), let lon = number(rawLon),
              (-90...90).contains(lat), (-180...180).contains(lon) else {
            throw ComposerError(L10n.text("Широта от −90 до 90, долгота от −180 до 180."))
        }
        return .uri(String(format: "geo:%.6f,%.6f", lat, lon))
    }

    static func wifi(ssid rawSSID: String, password: String, security: WiFiSecurity) throws -> ComposeCommand {
        let ssid = rawSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else { throw ComposerError(L10n.text("Введите имя сети.")) }
        if security != .open && password.isEmpty {
            throw ComposerError(L10n.text("Для защищённой сети нужен пароль."))
        }
        return .wifi(ssid: ssid, password: password, security: security)
    }

    static func contact(name rawName: String, phone rawPhone: String, email rawEmail: String) throws -> ComposeCommand {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ComposerError(L10n.text("Введите имя.")) }
        let phone = rawPhone.filter { $0.isNumber || $0 == "+" }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPhone = phone.filter(\.isNumber).count >= 5
        let hasEmail = email.contains("@") && !email.hasPrefix("@") && !email.hasSuffix("@")
        guard hasPhone || hasEmail else { throw ComposerError(L10n.text("Введите телефон или почту.")) }
        return .contact(name: name, phone: hasPhone ? phone : "", email: hasEmail ? email : "")
    }

    static func vcard(name: String, phone: String, email: String) -> String {
        var lines = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "FN:\(escapeVCard(name))",
            "N:\(escapeVCard(name));;;;"
        ]
        if !phone.isEmpty {
            lines.append("TEL;TYPE=CELL:\(phone)")
        }
        if !email.isEmpty {
            lines.append("EMAIL:\(escapeVCard(email))")
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func vcardFields(from text: String) -> VCardFields? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var name = ""
        var phone = ""
        var email = ""
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let upper = line.uppercased()
            if upper.hasPrefix("FN:") {
                name = unescapeVCard(String(line.dropFirst(3)))
            } else if upper.hasPrefix("TEL") {
                if let value = line.split(separator: ":", maxSplits: 1).last {
                    phone = String(value).filter { $0.isNumber || $0 == "+" }
                }
            } else if upper.hasPrefix("EMAIL") {
                if let value = line.split(separator: ":", maxSplits: 1).last {
                    email = unescapeVCard(String(value)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        guard !name.isEmpty || !phone.isEmpty || !email.isEmpty else { return nil }
        if name.isEmpty {
            name = [phone, email].first { !$0.isEmpty } ?? L10n.text("Контакт")
        }
        return VCardFields(name: name, phone: phone, email: email)
    }

    private static func number(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func escapeVCard(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescapeVCard(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
