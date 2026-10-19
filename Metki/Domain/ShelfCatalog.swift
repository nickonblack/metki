import Foundation

struct ShelfDefinition: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var sortIndex: Int
    var systemKey: String?

    var isInbox: Bool { systemKey == Shelf.inbox.rawValue }

    var localizationKey: String? {
        guard let systemKey, let shelf = Shelf(rawValue: systemKey), name == shelf.defaultName else { return nil }
        return shelf.defaultName
    }

    var displayName: String {
        localizationKey.map(L10n.text) ?? name
    }
}

enum ShelfCatalog {
    static let inboxID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let homeID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let workID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let thingsID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!

    static func id(for shelf: Shelf) -> UUID {
        switch shelf {
        case .inbox: return inboxID
        case .home: return homeID
        case .work: return workID
        case .things: return thingsID
        case .custom: return inboxID
        }
    }

    static func shelf(for id: UUID) -> Shelf {
        switch id {
        case homeID: return .home
        case workID: return .work
        case thingsID: return .things
        case inboxID: return .inbox
        default: return .custom
        }
    }

    static func defaults() -> [ShelfDefinition] {
        [
            ShelfDefinition(id: inboxID, name: Shelf.inbox.defaultName, sortIndex: 0, systemKey: Shelf.inbox.rawValue),
            ShelfDefinition(id: homeID, name: Shelf.home.defaultName, sortIndex: 1, systemKey: Shelf.home.rawValue),
            ShelfDefinition(id: workID, name: Shelf.work.defaultName, sortIndex: 2, systemKey: Shelf.work.rawValue),
            ShelfDefinition(id: thingsID, name: Shelf.things.defaultName, sortIndex: 3, systemKey: Shelf.things.rawValue)
        ]
    }

    static func normalized(_ shelves: [ShelfDefinition]) -> [ShelfDefinition] {
        var items = shelves
        if !items.contains(where: { $0.id == inboxID }) {
            items.append(defaults()[0])
        }
        return items.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex { return lhs.name < rhs.name }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    static func name(for tag: TagRecord, in shelves: [ShelfDefinition]) -> String {
        shelves.first { $0.id == tag.shelfId }?.displayName ?? tag.shelf.title
    }

    /// Дом, Работа и Вещи остаются первыми, чтобы прежние полки были на виду.
    static func filterOrder(_ shelves: [ShelfDefinition]) -> [ShelfDefinition] {
        let rank: [UUID: Int] = [homeID: 0, workID: 1, thingsID: 2, inboxID: 3]
        return shelves.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? 10 + lhs.sortIndex
            let right = rank[rhs.id] ?? 10 + rhs.sortIndex
            if left == right { return lhs.name < rhs.name }
            return left < right
        }
    }
}
