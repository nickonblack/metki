import Foundation

struct TagArchive: Codable, Equatable {
    var version: Int
    var tags: [TagRecord]
    var shelves: [ShelfDefinition]?
    var templates: [WriteTemplate]?
}

struct DecodedLibrary: Equatable {
    var tags: [TagRecord]
    var shelves: [ShelfDefinition]
    var templates: [WriteTemplate]
}

struct LibrarySnapshot: Equatable {
    var tags: [TagRecord]
    var shelves: [ShelfDefinition]
}

struct ImportSummary: Equatable {
    var inserted: Int
    var updated: Int
    var templates: Int = 0

    var message: String {
        var text = L10n.format("Новых: %lld, обновлено: %lld", inserted, updated)
        if templates > 0 {
            text += L10n.format(", шаблонов: %lld", templates)
        }
        return text
    }
}

enum ArchiveError: LocalizedError, Equatable {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return L10n.text("Файл не похож на библиотеку меток.")
        case .empty: return L10n.text("В файле нет меток.")
        }
    }
}

enum TagCodec {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func tags(from data: Data) throws -> [TagRecord] {
        try decode(data).tags
    }

    static func decode(_ data: Data) throws -> DecodedLibrary {
        let decoder = decoder()
        if let archive = try? decoder.decode(TagArchive.self, from: data) {
            return DecodedLibrary(
                tags: archive.tags,
                shelves: archive.shelves ?? [],
                templates: archive.templates ?? []
            )
        }
        if let tags = try? decoder.decode([TagRecord].self, from: data), !tags.isEmpty {
            return DecodedLibrary(tags: tags, shelves: [], templates: [])
        }
        throw ArchiveError.unreadable
    }

    static func archiveData(
        tags: [TagRecord],
        shelves: [ShelfDefinition] = [],
        templates: [WriteTemplate] = [],
        redactWiFi: Bool = false
    ) throws -> Data {
        let stored = redactWiFi ? tags.map { $0.redactingWiFi() } : tags
        let archive = TagArchive(
            version: shelves.isEmpty && templates.isEmpty ? 1 : 2,
            tags: stored,
            shelves: shelves.isEmpty ? nil : shelves,
            templates: templates.isEmpty ? nil : templates
        )
        return try encoder().encode(archive)
    }

    static func snapshot(from data: Data) -> LibrarySnapshot? {
        guard let decoded = try? decode(data) else { return nil }
        let shelves = decoded.shelves.isEmpty ? ShelfCatalog.defaults() : ShelfCatalog.normalized(decoded.shelves)
        return LibrarySnapshot(tags: decoded.tags, shelves: shelves)
    }
}

enum TemplateCodec {
    static func load(from url: URL) -> [WriteTemplate] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let templates = try? TagCodec.decoder().decode([WriteTemplate].self, from: data) {
            return templates
        }
        if let decoded = try? TagCodec.decode(data) {
            return decoded.templates
        }
        return []
    }

    static func save(_ templates: [WriteTemplate], to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? TagCodec.encoder().encode(templates) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

protocol TagStoring: AnyObject {
    var folder: URL { get }
    var syncsWithCloud: Bool { get }
    func load() -> LibrarySnapshot
    func replace(_ snapshot: LibrarySnapshot)
}

final class JSONTagStoring: TagStoring {
    let folder: URL
    let syncsWithCloud: Bool
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.folder = fileURL.deletingLastPathComponent()
            self.syncsWithCloud = false
        } else {
            let folder = AppStorage.libraryFolder()
            self.folder = folder
            self.fileURL = folder.appendingPathComponent("tags.json")
            let testing = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            self.syncsWithCloud = !testing
        }
    }

    func load() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = TagCodec.snapshot(from: data) else {
            return LibrarySnapshot(tags: [], shelves: ShelfCatalog.defaults())
        }
        return snapshot
    }

    func replace(_ snapshot: LibrarySnapshot) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? TagCodec.archiveData(tags: snapshot.tags, shelves: snapshot.shelves) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
