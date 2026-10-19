import Foundation
import UIKit

enum AppStorage {
    static let groupID = "group.app.metki.reader"
    static let cloudID = "iCloud.app.metki.reader"

    static func libraryFolder() -> URL {
        let folder: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            folder = group.appendingPathComponent("Library", isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            folder = base.appendingPathComponent("Metki", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        migrateLegacy(into: folder)
        return folder
    }

    static func widgetFolder() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Library", isDirectory: true)
    }

    private static func migrateLegacy(into folder: URL) {
        let destination = folder.appendingPathComponent("tags.json")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = support.appendingPathComponent("Metki", isDirectory: true).appendingPathComponent("tags.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        if legacy.standardizedFileURL == destination.standardizedFileURL { return }
        try? FileManager.default.copyItem(at: legacy, to: destination)
    }
}

enum PhotoStore {
    static func fileURL(named name: String, in folder: URL) -> URL {
        folder.appendingPathComponent("photos", isDirectory: true).appendingPathComponent(name)
    }

    static func writeJPEG(_ data: Data, tagID: UUID, folder: URL) throws -> String {
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw ArchiveError.unreadable
        }
        let name = "\(tagID.uuidString).jpg"
        let url = fileURL(named: name, in: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: url, options: .atomic)
        return name
    }

    static func remove(_ name: String?, folder: URL) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: fileURL(named: name, in: folder))
    }
}

struct PinnedCard: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var shelf: String
    var kind: String
    var shelfKey: String? = nil
    var kindKey: String? = nil
}

enum PinnedBoard {
    static func cards(from tags: [TagRecord], shelves: [ShelfDefinition]) -> [PinnedCard] {
        tags.filter(\.pinned).map { tag in
            PinnedCard(
                id: tag.id,
                name: tag.name,
                shelf: ShelfCatalog.name(for: tag, in: shelves),
                kind: tag.records.first?.kind.title ?? tag.typeName,
                shelfKey: shelves.first { $0.id == tag.shelfId }?.localizationKey,
                kindKey: tag.records.first?.kind.localizationKey
            )
        }
    }

    static func write(_ cards: [PinnedCard], to folder: URL) {
        let url = folder.appendingPathComponent("pinned.json")
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func read(from folder: URL) -> [PinnedCard] {
        let url = folder.appendingPathComponent("pinned.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PinnedCard].self, from: data)) ?? []
    }
}

enum ZipArchive {
    static func data(files: [(path: String, data: Data)]) -> Data {
        var locals = Data()
        var central = Data()
        var offset: UInt32 = 0
        for file in files {
            let name = Data(file.path.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)
            var local = Data()
            local.append(le32(0x04034B50))
            local.append(le16(20))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le32(crc))
            local.append(le32(size))
            local.append(le32(size))
            local.append(le16(UInt16(name.count)))
            local.append(le16(0))
            local.append(name)
            local.append(file.data)
            locals.append(local)

            var entry = Data()
            entry.append(le32(0x02014B50))
            entry.append(le16(20))
            entry.append(le16(20))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le32(crc))
            entry.append(le32(size))
            entry.append(le32(size))
            entry.append(le16(UInt16(name.count)))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le16(0))
            entry.append(le32(0))
            entry.append(le32(offset))
            entry.append(name)
            central.append(entry)
            offset += UInt32(local.count)
        }
        var end = Data()
        end.append(le32(0x06054B50))
        end.append(le16(0))
        end.append(le16(0))
        end.append(le16(UInt16(files.count)))
        end.append(le16(UInt16(files.count)))
        end.append(le32(UInt32(central.count)))
        end.append(le32(offset))
        end.append(le16(0))
        var archive = Data()
        archive.append(locals)
        archive.append(central)
        archive.append(end)
        return archive
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = (crc & 1) == 1 ? UInt32(0xEDB8_8320) : 0
                crc = (crc >> 1) ^ mask
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
