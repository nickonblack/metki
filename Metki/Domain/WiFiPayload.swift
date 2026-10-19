import Foundation

struct WiFiFields: Equatable {
    var ssid: String?
    var password: String?
    var security: WiFiSecurity
    var detail: String
    var publicDetail: String
}

enum WiFiPayload {
    static func bytes(ssid: String, password: String, security: WiFiSecurity) -> Data {
        var inner = Data()
        inner.append(attribute(0x1026, Data([0x01])))
        inner.append(attribute(0x1045, Data(ssid.utf8)))
        inner.append(attribute(0x1003, u16(security.auth)))
        inner.append(attribute(0x100F, u16(security.encryption)))
        if security != .open, !password.isEmpty {
            inner.append(attribute(0x1027, Data(password.utf8)))
        }
        inner.append(attribute(0x1020, Data(repeating: 0xFF, count: 6)))
        return attribute(0x100E, inner)
    }

    static func withoutPassword(_ data: Data) -> Data {
        let parsed = fields(from: data)
        guard let ssid = parsed.ssid, !ssid.isEmpty else { return data }
        return bytes(ssid: ssid, password: "", security: parsed.security)
    }

    static func fields(from data: Data) -> WiFiFields {
        let map = flatten(data)
        let ssid = map[0x1045].flatMap { String(data: $0, encoding: .utf8) }
        let password = map[0x1027].flatMap { String(data: $0, encoding: .utf8) }
        let auth = map[0x1003].flatMap(readUInt16)
        let security = security(from: auth)
        let publicDetail = auth.map(authTitle) ?? ""
        var parts: [String] = []
        if !publicDetail.isEmpty { parts.append(publicDetail) }
        if let password, !password.isEmpty { parts.append(L10n.format("пароль %@", password)) }
        return WiFiFields(
            ssid: ssid,
            password: password,
            security: security,
            detail: parts.joined(separator: " · "),
            publicDetail: publicDetail
        )
    }

    private static func security(from auth: UInt16?) -> WiFiSecurity {
        switch auth {
        case 0x0001: return .open
        case 0x0022: return .wpaMixed
        default: return .wpa2
        }
    }

    private static func flatten(_ data: Data) -> [UInt16: Data] {
        var result: [UInt16: Data] = [:]
        var offset = 0
        while offset + 4 <= data.count {
            let id = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            let length = Int((UInt16(data[offset + 2]) << 8) | UInt16(data[offset + 3]))
            let start = offset + 4
            let end = start + length
            guard end <= data.count else { break }
            let value = data.subdata(in: start..<end)
            if id == 0x100E {
                result.merge(flatten(value)) { _, new in new }
            } else {
                result[id] = value
            }
            offset = end
        }
        return result
    }

    private static func attribute(_ id: UInt16, _ value: Data) -> Data {
        var data = Data()
        data.append(UInt8(id >> 8))
        data.append(UInt8(id & 0xFF))
        let length = UInt16(value.count)
        data.append(UInt8(length >> 8))
        data.append(UInt8(length & 0xFF))
        data.append(value)
        return data
    }

    private static func u16(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func readUInt16(_ data: Data) -> UInt16? {
        guard data.count >= 2 else { return nil }
        return (UInt16(data[0]) << 8) | UInt16(data[1])
    }

    private static func authTitle(_ value: UInt16) -> String {
        switch value {
        case 0x0001: return L10n.text("Открытая")
        case 0x0002: return "WPA"
        case 0x0020: return "WPA2"
        case 0x0022: return "WPA/WPA2"
        default: return String(format: L10n.text("Защита %04X"), value)
        }
    }
}
