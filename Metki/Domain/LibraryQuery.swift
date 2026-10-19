import Foundation

enum Shelf: String, Codable, CaseIterable, Identifiable, Hashable {
    case inbox
    case home
    case work
    case things
    case custom

    var id: String { rawValue }

    // Stable names used by existing libraries. Translate only for presentation.
    var defaultName: String {
        switch self {
        case .inbox: return "Без полки"
        case .home: return "Дом"
        case .work: return "Работа"
        case .things: return "Вещи"
        case .custom: return "Своя"
        }
    }

    var title: String { L10n.text(defaultName) }
}

enum LibraryScope: Hashable {
    case all
    case pinned
    case shelf(UUID)
}

enum LibrarySort: String, CaseIterable, Identifiable, Hashable {
    case recent
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return L10n.text("Сначала новые")
        case .name: return L10n.text("По имени")
        }
    }
}

enum LibraryQuery {
    static func apply(
        tags: [TagRecord],
        search: String,
        scope: LibraryScope,
        sort: LibrarySort,
        shelves: [ShelfDefinition]
    ) -> [TagRecord] {
        var result = tags.filter { matches($0, search: search, shelves: shelves) }
        switch scope {
        case .all:
            break
        case .pinned:
            result = result.filter(\.pinned)
        case .shelf(let id):
            result = result.filter { $0.shelfId == id }
        }
        result.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            switch sort {
            case .recent:
                return lhs.scannedAt > rhs.scannedAt
            case .name:
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if order == .orderedSame { return lhs.scannedAt > rhs.scannedAt }
                return order == .orderedAscending
            }
        }
        return result
    }

    private static func matches(_ tag: TagRecord, search: String, shelves: [ShelfDefinition]) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if tag.name.localizedCaseInsensitiveContains(needle) { return true }
        if tag.uid.localizedCaseInsensitiveContains(needle) { return true }
        if tag.note.localizedCaseInsensitiveContains(needle) { return true }
        if tag.typeName.localizedCaseInsensitiveContains(needle) { return true }
        if ShelfCatalog.name(for: tag, in: shelves).localizedCaseInsensitiveContains(needle) { return true }
        return tag.records.contains {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.detail.localizedCaseInsensitiveContains(needle)
        }
    }
}
