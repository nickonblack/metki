import Foundation

enum LibraryMerge {
    static func tags(local: [TagRecord], remote: [TagRecord]) -> [TagRecord] {
        var byKey: [String: TagRecord] = [:]
        for tag in remote {
            byKey[key(tag)] = tag
        }
        for tag in local {
            let itemKey = key(tag)
            if let other = byKey[itemKey] {
                byKey[itemKey] = combine(local: tag, remote: other)
            } else {
                byKey[itemKey] = tag
            }
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.scannedAt > rhs.scannedAt
        }
    }

    static func shelves(local: [ShelfDefinition], remote: [ShelfDefinition]) -> [ShelfDefinition] {
        var map: [UUID: ShelfDefinition] = [:]
        for shelf in remote { map[shelf.id] = shelf }
        for shelf in local { map[shelf.id] = shelf }
        return ShelfCatalog.normalized(Array(map.values))
    }

    static func templates(local: [WriteTemplate], remote: [WriteTemplate]) -> [WriteTemplate] {
        var map: [UUID: WriteTemplate] = [:]
        for item in remote { map[item.id] = item }
        for item in local {
            if let existing = map[item.id], existing.updatedAt > item.updatedAt {
                continue
            }
            map[item.id] = item
        }
        return map.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func combine(local: TagRecord, remote: TagRecord) -> TagRecord {
        let newer = local.scannedAt >= remote.scannedAt ? local : remote
        let older = local.scannedAt >= remote.scannedAt ? remote : local
        var result = newer
        result.pinned = local.pinned || remote.pinned
        if local.name != remote.name {
            result.nameConflict = true
            result.alternateName = older.name
            result.name = newer.name
        }
        if newer.shelfId == ShelfCatalog.inboxID && older.shelfId != ShelfCatalog.inboxID {
            result.shelfId = older.shelfId
            result.shelf = older.shelf
        }
        if result.photoFile == nil {
            result.photoFile = older.photoFile
        }
        var scans = newer.scans + older.scans
        scans.sort { $0.scannedAt > $1.scannedAt }
        var seen = Set<UUID>()
        result.scans = scans.filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
        return result
    }

    private static func key(_ tag: TagRecord) -> String {
        tag.uid == "—" ? "id:\(tag.id.uuidString)" : "uid:\(tag.uid)"
    }
}
