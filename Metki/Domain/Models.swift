import Foundation

enum RecordKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case text
    case url
    case contact
    case phone
    case email
    case sms
    case geo
    case wifi
    case other

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .text: return "Текст"
        case .url: return "Ссылка"
        case .contact: return "Визитка"
        case .phone: return "Телефон"
        case .email: return "Почта"
        case .sms: return "Сообщение"
        case .geo: return "Геоточка"
        case .wifi: return "Wi‑Fi"
        case .other: return "record.generic"
        }
    }

    var title: String { L10n.text(localizationKey) }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .contact: return "person.crop.rectangle"
        case .phone: return "phone"
        case .email: return "envelope"
        case .sms: return "message"
        case .geo: return "mappin"
        case .wifi: return "wifi"
        case .other: return "tag"
        }
    }

    static var writable: [RecordKind] {
        [.text, .url, .contact, .phone, .email, .sms, .geo, .wifi]
    }
}

enum NDEFState: String, Codable, Hashable {
    case readWrite
    case readOnly
    case unsupported
    case unknown

    var title: String {
        switch self {
        case .readWrite: return L10n.text("Можно записать")
        case .readOnly: return L10n.text("Только чтение")
        case .unsupported: return L10n.text("Без NDEF")
        case .unknown: return L10n.text("Формат не определён")
        }
    }
}

enum WiFiSecurity: String, CaseIterable, Identifiable, Hashable {
    case open
    case wpa2
    case wpaMixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return L10n.text("Открытая")
        case .wpa2: return "WPA2"
        case .wpaMixed: return "WPA/WPA2"
        }
    }

    var auth: UInt16 {
        switch self {
        case .open: return 0x0001
        case .wpa2: return 0x0020
        case .wpaMixed: return 0x0022
        }
    }

    var encryption: UInt16 {
        switch self {
        case .open: return 0x0001
        case .wpa2: return 0x0008
        case .wpaMixed: return 0x000C
        }
    }
}

struct ScanSnapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var scannedAt: Date
    var ndefStatus: NDEFState
    var capacity: Int?
    var records: [StoredRecord]
}

struct WriteTemplate: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var records: [StoredRecord]
    var updatedAt: Date
}

struct StoredRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: RecordKind
    var title: String
    var detail: String
    var typeNameFormat: UInt8
    var type: Data
    var identifier: Data
    var payload: Data

    /// Rebuild generated labels in the current language; keep actual tag content verbatim.
    var displayDetail: String {
        switch kind {
        case .wifi: return WiFiPayload.fields(from: payload).detail
        case .phone: return L10n.text("Телефон")
        case .email: return L10n.text("Почта")
        case .geo: return L10n.text("Координаты")
        default: return detail
        }
    }

    var actionURL: URL? {
        switch kind {
        case .url:
            return URL(string: title)
        case .phone:
            let number = title.filter { $0.isNumber || $0 == "+" }
            return URL(string: "tel:\(number)")
        case .email:
            return URL(string: "mailto:\(title)")
        case .sms:
            let number = title.filter { $0.isNumber || $0 == "+" }
            guard !number.isEmpty else { return nil }
            return URL(string: RecordComposer.smsURI(number: number, body: detail))
        case .geo:
            let point = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !point.isEmpty else { return nil }
            let encoded = point.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? point
            return URL(string: "http://maps.apple.com/?ll=\(encoded)")
        default:
            return nil
        }
    }

    var actionTitle: String? {
        switch kind {
        case .url: return L10n.text("Открыть")
        case .contact: return L10n.text("В Контакты")
        case .phone: return L10n.text("Позвонить")
        case .email: return L10n.text("Написать")
        case .sms: return L10n.text("Открыть SMS")
        case .geo: return L10n.text("На карте")
        default: return nil
        }
    }

    var opensContact: Bool { kind == .contact }
}

struct TagIdentity: Hashable {
    var uid: String
    var typeName: String
    var technology: String
    var manufacturer: String
}

enum TagPresentation {
    static func label(_ value: String) -> String {
        switch value {
        case "Неизвестная метка", "Unknown tag": return L10n.text("Неизвестная метка")
        case "Случайный UID", "Random UID": return L10n.text("Случайный UID")
        case "Не определён", "Not identified": return L10n.text("Не определён")
        default: return value
        }
    }

    /// Older cards store the byte unit as part of their generated technology label.
    static func technology(_ value: String) -> String {
        let parts = value.components(separatedBy: " · ")
        guard parts.count == 2, ["ISO 14443", "ISO 14443-4", "ISO 15693"].contains(parts[0]) else { return value }
        let countAndUnit = parts[1].split(separator: " ")
        guard countAndUnit.count == 2, let count = Int(countAndUnit[0]),
              ["байт", "байта", "байтов", "byte", "bytes"].contains(String(countAndUnit[1])) else { return value }
        return "\(parts[0]) · \(L10n.bytes(count))"
    }
}

struct TagScan: Identifiable, Hashable {
    var id: UUID
    var identity: TagIdentity
    var ndefStatus: NDEFState
    var capacity: Int?
    var records: [StoredRecord]
    var scannedAt: Date

    var uid: String { identity.uid }

    var suggestedName: String {
        if let record = records.first(where: { $0.kind != .other && !$0.title.isEmpty }) {
            let raw = record.kind == .url ? (URL(string: record.title)?.host ?? record.title) : record.title
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(42))
            }
        }
        let tail = uid.split(separator: ":").suffix(2).joined(separator: ":")
        return tail.isEmpty ? L10n.text("Метка") : L10n.format("Метка %@", tail)
    }

    var statusLine: String {
        if ndefStatus == .readWrite, let capacity {
            return "\(ndefStatus.title) · \(L10n.bytes(capacity))"
        }
        return ndefStatus.title
    }
}

struct TagRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var note: String
    var uid: String
    var typeName: String
    var technology: String
    var manufacturer: String
    var ndefStatus: NDEFState
    var capacity: Int?
    var records: [StoredRecord]
    var scannedAt: Date
    var pinned: Bool
    var shelf: Shelf
    var shelfId: UUID
    var scans: [ScanSnapshot]
    var photoFile: String?
    var nameConflict: Bool
    var alternateName: String

    init(
        id: UUID,
        name: String,
        note: String,
        uid: String,
        typeName: String,
        technology: String,
        manufacturer: String,
        ndefStatus: NDEFState,
        capacity: Int?,
        records: [StoredRecord],
        scannedAt: Date,
        pinned: Bool = false,
        shelf: Shelf = .inbox,
        shelfId: UUID? = nil,
        scans: [ScanSnapshot] = [],
        photoFile: String? = nil,
        nameConflict: Bool = false,
        alternateName: String = ""
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.uid = uid
        self.typeName = typeName
        self.technology = technology
        self.manufacturer = manufacturer
        self.ndefStatus = ndefStatus
        self.capacity = capacity
        self.records = records
        self.scannedAt = scannedAt
        self.pinned = pinned
        self.shelf = shelf
        self.shelfId = shelfId ?? ShelfCatalog.id(for: shelf)
        self.scans = scans
        self.photoFile = photoFile
        self.nameConflict = nameConflict
        self.alternateName = alternateName
    }

    var statusLine: String {
        if ndefStatus == .readWrite, let capacity {
            return "\(ndefStatus.title) · \(L10n.bytes(capacity))"
        }
        return ndefStatus.title
    }

    var preview: String {
        if let record = records.first, !record.title.isEmpty { return record.title }
        if !note.isEmpty { return note }
        return typeName
    }

    func summary(shelfName: String? = nil) -> String {
        var lines = [name, shelfName ?? shelf.title, typeName, uid]
        if !note.isEmpty { lines.append(note) }
        lines.append(contentsOf: records.map(Self.summaryLine(for:)))
        return lines.joined(separator: "\n")
    }

    private static func summaryLine(for record: StoredRecord) -> String {
        let detail: String
        if record.kind == .wifi {
            detail = WiFiPayload.fields(from: record.payload).publicDetail
        } else {
            detail = record.detail
        }
        if detail.isEmpty {
            return "\(record.kind.title): \(record.title)"
        }
        return "\(record.kind.title): \(record.title) — \(detail)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, uid, typeName, technology, manufacturer
        case ndefStatus, capacity, records, scannedAt, pinned, shelf
        case shelfId, scans, photoFile, nameConflict, alternateName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        uid = try container.decode(String.self, forKey: .uid)
        typeName = try container.decode(String.self, forKey: .typeName)
        technology = try container.decode(String.self, forKey: .technology)
        manufacturer = try container.decode(String.self, forKey: .manufacturer)
        ndefStatus = try container.decode(NDEFState.self, forKey: .ndefStatus)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
        records = try container.decodeIfPresent([StoredRecord].self, forKey: .records) ?? []
        scannedAt = try container.decode(Date.self, forKey: .scannedAt)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        shelf = try container.decodeIfPresent(Shelf.self, forKey: .shelf) ?? .inbox
        shelfId = try container.decodeIfPresent(UUID.self, forKey: .shelfId) ?? ShelfCatalog.id(for: shelf)
        scans = try container.decodeIfPresent([ScanSnapshot].self, forKey: .scans) ?? []
        photoFile = try container.decodeIfPresent(String.self, forKey: .photoFile)
        nameConflict = try container.decodeIfPresent(Bool.self, forKey: .nameConflict) ?? false
        alternateName = try container.decodeIfPresent(String.self, forKey: .alternateName) ?? ""
    }

    func redactingWiFi() -> TagRecord {
        var copy = self
        copy.records = records.map { $0.redactingWiFi() }
        copy.scans = scans.map { snapshot in
            var snapshot = snapshot
            snapshot.records = snapshot.records.map { $0.redactingWiFi() }
            return snapshot
        }
        return copy
    }
}

extension StoredRecord {
    func redactingWiFi() -> StoredRecord {
        guard kind == .wifi else { return self }
        var copy = self
        copy.payload = WiFiPayload.withoutPassword(payload)
        copy.detail = WiFiPayload.fields(from: copy.payload).publicDetail
        return copy
    }
}

enum Hex {
    static func string(_ data: Data, separator: String = ":") -> String {
        guard !data.isEmpty else { return "—" }
        return data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }

    static func spaced(_ data: Data, limit: Int = 48) -> String {
        let shown = data.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return data.count > limit ? shown + " …" : shown
    }

    static func full(_ data: Data) -> String {
        guard !data.isEmpty else { return "—" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func typeNameFormatTitle(_ raw: UInt8) -> String {
        switch raw {
        case 0: return L10n.text("Пустая")
        case 1: return "Well-known"
        case 2: return "MIME"
        case 3: return L10n.text("Абсолютный URI")
        case 4: return L10n.text("Внешний тип")
        case 5: return L10n.text("Неизвестный")
        case 6: return L10n.text("Без изменений")
        default: return L10n.format("Формат %lld", Int(raw))
        }
    }
}
