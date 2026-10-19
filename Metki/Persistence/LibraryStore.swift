import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tags: [TagRecord] = []
    @Published private(set) var shelves: [ShelfDefinition] = ShelfCatalog.defaults()
    @Published private(set) var templates: [WriteTemplate] = []
    @Published var search = ""
    @Published var scope: LibraryScope = .all
    @Published var sort: LibrarySort = .recent
    @Published private(set) var pendingUndo: [TagRecord] = []

    private let storage: TagStoring
    private var templatesURL: URL { storage.folder.appendingPathComponent("templates.json") }

    var folder: URL { storage.folder }

    init(storage: TagStoring = JSONTagStoring()) {
        self.storage = storage
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") {
            tags = arguments.contains("-seedLibrary") ? DebugLibrary.make() : []
            shelves = ShelfCatalog.defaults()
            templates = []
            storage.replace(LibrarySnapshot(tags: tags, shelves: shelves))
            TemplateCodec.save([], to: templatesURL)
            publishPinned()
            return
        }
        #endif
        let snapshot = storage.load()
        tags = snapshot.tags
        shelves = ShelfCatalog.normalized(snapshot.shelves)
        templates = TemplateCodec.load(from: templatesURL)
        if storage.syncsWithCloud {
            let pulled = CloudLibrary.pull(tags: tags, shelves: shelves, templates: templates, localFolder: storage.folder)
            let changed = pulled.tags != tags || pulled.shelves != shelves || pulled.templates != templates
            tags = pulled.tags
            shelves = ShelfCatalog.normalized(pulled.shelves)
            templates = pulled.templates
            if changed { commit() }
        }
        publishPinned()
    }

    var visibleTags: [TagRecord] {
        LibraryQuery.apply(tags: tags, search: search, scope: scope, sort: sort, shelves: shelves)
    }

    var recentTags: [TagRecord] {
        LibraryQuery.apply(tags: tags, search: "", scope: .all, sort: .recent, shelves: shelves).prefix(4).map { $0 }
    }

    var hasPhotos: Bool { tags.contains { $0.photoFile != nil } }

    var undoMessage: String? {
        switch pendingUndo.count {
        case 0: return nil
        case 1: return L10n.format("Удалена «%@»", pendingUndo[0].name)
        default: return L10n.format("Удалено %lld", pendingUndo.count)
        }
    }

    func shelfName(id: UUID) -> String {
        shelves.first { $0.id == id }?.displayName ?? ShelfCatalog.shelf(for: id).title
    }

    func existing(uid: String) -> TagRecord? {
        guard uid != "—" else { return nil }
        return tags.first { $0.uid == uid }
    }

    func tag(id: UUID) -> TagRecord? {
        tags.first { $0.id == id }
    }

    func save(scan: TagScan, name: String, note: String, preserveName: Bool = false, keepRecordsIfEmpty: Bool = false) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? scan.suggestedName : trimmedName
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = tags.firstIndex(where: { $0.uid == scan.uid && scan.uid != "—" }) {
            if !preserveName {
                tags[index].name = finalName
                tags[index].note = finalNote
            }
            let nextRecords = keepRecordsIfEmpty && scan.records.isEmpty ? tags[index].records : scan.records
        if !RecordIdentity.same(tags[index].records, nextRecords) {
                tags[index].scans.append(
                    ScanSnapshot(
                        id: UUID(),
                        scannedAt: tags[index].scannedAt,
                        ndefStatus: tags[index].ndefStatus,
                        capacity: tags[index].capacity,
                        records: tags[index].records
                    )
                )
                if tags[index].scans.count > 20 {
                    tags[index].scans.removeFirst(tags[index].scans.count - 20)
                }
            }
            tags[index].typeName = scan.identity.typeName
            tags[index].technology = scan.identity.technology
            tags[index].manufacturer = scan.identity.manufacturer
            tags[index].ndefStatus = scan.ndefStatus
            tags[index].capacity = scan.capacity
            tags[index].records = nextRecords
            tags[index].scannedAt = scan.scannedAt
        } else {
            tags.append(
                TagRecord(
                    id: UUID(),
                    name: finalName,
                    note: finalNote,
                    uid: scan.uid,
                    typeName: scan.identity.typeName,
                    technology: scan.identity.technology,
                    manufacturer: scan.identity.manufacturer,
                    ndefStatus: scan.ndefStatus,
                    capacity: scan.capacity,
                    records: scan.records,
                    scannedAt: scan.scannedAt
                )
            )
        }
        commit()
    }

    func update(id: UUID, name: String, note: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[index].name = trimmed.isEmpty ? tags[index].name : trimmed
        tags[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[index].nameConflict = false
        commit()
    }

    func useAlternateName(id: UUID) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let alternate = tags[index].alternateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alternate.isEmpty else { return }
        tags[index].name = alternate
        tags[index].alternateName = ""
        tags[index].nameConflict = false
        commit()
    }

    func setShelf(id: UUID, shelfId: UUID) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        guard shelves.contains(where: { $0.id == shelfId }) else { return }
        tags[index].shelfId = shelfId
        tags[index].shelf = ShelfCatalog.shelf(for: shelfId)
        commit()
    }

    func addShelf(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let shelf = ShelfDefinition(id: UUID(), name: trimmed, sortIndex: (shelves.map(\.sortIndex).max() ?? 0) + 1, systemKey: nil)
        shelves.append(shelf)
        commit()
        return shelf.id
    }

    func renameShelf(id: UUID, name: String) {
        guard let index = shelves.firstIndex(where: { $0.id == id }), !shelves[index].isInbox else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shelves[index].name = trimmed
        commit()
    }

    func deleteShelf(id: UUID) {
        guard let shelf = shelves.first(where: { $0.id == id }), !shelf.isInbox else { return }
        for index in tags.indices where tags[index].shelfId == id {
            tags[index].shelfId = ShelfCatalog.inboxID
            tags[index].shelf = .inbox
        }
        shelves.removeAll { $0.id == id }
        if case .shelf(let selected) = scope, selected == id {
            scope = .all
        }
        commit()
    }

    func togglePin(id: UUID) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].pinned.toggle()
        commit()
    }

    func setPhoto(id: UUID, data: Data) {
        guard tags.contains(where: { $0.id == id }) else { return }
        guard let name = try? PhotoStore.writeJPEG(data, tagID: id, folder: storage.folder) else { return }
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].photoFile = name
        commit()
    }

    func removePhoto(id: UUID) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        PhotoStore.remove(tags[index].photoFile, folder: storage.folder)
        tags[index].photoFile = nil
        commit()
    }

    func delete(id: UUID) {
        guard let tag = tags.first(where: { $0.id == id }) else { return }
        purgePhotos(pendingUndo)
        tags.removeAll { $0.id == id }
        pendingUndo = [tag]
        commit()
    }

    func delete(offsets: IndexSet, in visible: [TagRecord]) {
        let removed = offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
        let ids = Set(removed.map(\.id))
        guard !ids.isEmpty else { return }
        purgePhotos(pendingUndo)
        tags.removeAll { ids.contains($0.id) }
        pendingUndo = removed
        commit()
    }

    func undoDelete() {
        guard !pendingUndo.isEmpty else { return }
        let known = Set(tags.map(\.id))
        tags.append(contentsOf: pendingUndo.filter { !known.contains($0.id) })
        pendingUndo = []
        commit()
    }

    func dismissUndo() {
        purgePhotos(pendingUndo)
        pendingUndo = []
    }

    func saveTemplate(name: String, records: [StoredRecord]) -> WriteTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = WriteTemplate(
            id: UUID(),
            name: trimmed.isEmpty ? L10n.text("Шаблон") : trimmed,
            records: records,
            updatedAt: Date()
        )
        templates.append(template)
        commit()
        return template
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        commit()
    }

    func importFile(at url: URL) throws -> ImportSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try importData(data)
    }

    func importData(_ data: Data) throws -> ImportSummary {
        let incoming = try TagCodec.decode(data)
        guard !incoming.tags.isEmpty || !incoming.templates.isEmpty else { throw ArchiveError.empty }
        for shelf in incoming.shelves where !shelves.contains(where: { $0.id == shelf.id }) {
            shelves.append(shelf)
        }
        var inserted = 0
        var updated = 0
        for var tag in incoming.tags {
            if !shelves.contains(where: { $0.id == tag.shelfId }) {
                shelves.append(
                    ShelfDefinition(
                        id: tag.shelfId,
                        name: tag.shelf.defaultName,
                        sortIndex: (shelves.map(\.sortIndex).max() ?? 0) + 1,
                        systemKey: tag.shelf == .custom ? nil : tag.shelf.rawValue
                    )
                )
            }
            if tag.uid != "—", let index = tags.firstIndex(where: { $0.uid == tag.uid }) {
                tag.id = tags[index].id
                tag.pinned = tags[index].pinned || tag.pinned
                if tag.shelf == .inbox {
                    tag.shelf = tags[index].shelf
                    tag.shelfId = tags[index].shelfId
                }
                if tag.photoFile == nil { tag.photoFile = tags[index].photoFile }
                if tag.scans.isEmpty { tag.scans = tags[index].scans }
                tags[index] = tag
                updated += 1
            } else {
                tag.id = UUID()
                tags.append(tag)
                inserted += 1
            }
        }
        var templateCount = 0
        for template in incoming.templates {
            if let index = templates.firstIndex(where: { $0.id == template.id }) {
                templates[index] = template
            } else {
                templates.append(template)
            }
            templateCount += 1
        }
        shelves = ShelfCatalog.normalized(shelves)
        commit()
        return ImportSummary(inserted: inserted, updated: updated, templates: templateCount)
    }

    func makeExportURL(redactWiFi: Bool) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metki-library.json")
        guard let data = try? TagCodec.archiveData(tags: tags, shelves: shelves, redactWiFi: redactWiFi) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    func makePhotoArchiveURL() -> URL? {
        guard let json = try? TagCodec.archiveData(tags: tags, shelves: shelves, templates: templates) else { return nil }
        var files: [(path: String, data: Data)] = [("library.json", json)]
        for tag in tags {
            guard let name = tag.photoFile else { continue }
            let url = PhotoStore.fileURL(named: name, in: storage.folder)
            guard let data = try? Data(contentsOf: url) else { continue }
            files.append(("photos/\(name)", data))
        }
        let archive = ZipArchive.data(files: files)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metki-library.zip")
        try? archive.write(to: url, options: .atomic)
        return url
    }

    func exportURL(for tag: TagRecord, redactWiFi: Bool) -> URL? {
        let shelf = shelves.filter { $0.id == tag.shelfId }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metki-card.json")
        guard let data = try? TagCodec.archiveData(tags: [tag], shelves: shelf, redactWiFi: redactWiFi) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    func exportURL(for template: WriteTemplate) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metki-template.json")
        guard let data = try? TagCodec.archiveData(tags: [], templates: [template]) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    func refreshFromCloud() {
        guard storage.syncsWithCloud else { return }
        let pulled = CloudLibrary.pull(tags: tags, shelves: shelves, templates: templates, localFolder: storage.folder)
        guard pulled.tags != tags || pulled.shelves != shelves || pulled.templates != templates else { return }
        tags = pulled.tags
        shelves = ShelfCatalog.normalized(pulled.shelves)
        templates = pulled.templates
        commit()
    }

    private func commit() {
        tags = LibraryQuery.apply(tags: tags, search: "", scope: .all, sort: .recent, shelves: shelves)
        shelves = ShelfCatalog.normalized(shelves)
        storage.replace(LibrarySnapshot(tags: tags, shelves: shelves))
        TemplateCodec.save(templates, to: templatesURL)
        publishPinned()
        if storage.syncsWithCloud {
            CloudLibrary.push(from: storage.folder)
        }
    }

    private func publishPinned() {
        PinnedBoard.write(PinnedBoard.cards(from: tags, shelves: shelves), to: storage.folder)
    }

    private func purgePhotos(_ records: [TagRecord]) {
        for tag in records {
            PhotoStore.remove(tag.photoFile, folder: storage.folder)
        }
    }
}

#if DEBUG
enum DebugLibrary {
    static var didSeedScan = false

    static func sampleScan() -> TagScan {
        TagScan(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA01")!,
            identity: TagIdentity(
                uid: "04:AA:01",
                typeName: "Ultralight / NTAG",
                technology: "ISO 14443 · 7 байт",
                manufacturer: "NXP Semiconductors"
            ),
            ndefStatus: .readWrite,
            capacity: 144,
            records: [],
            scannedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    static func make() -> [TagRecord] {
        [
            tag(
                id: "11111111-1111-1111-1111-111111111111",
                name: "Кухня",
                note: "Холодильник",
                uid: "04:AA:01",
                shelf: .home,
                pinned: false,
                daysAgo: 1,
                records: record(.uri("https://kitchen.example")).map { [$0] } ?? []
            ),
            tag(
                id: "22222222-2222-2222-2222-222222222222",
                name: "Офис",
                note: "Стойка",
                uid: "04:BB:02",
                shelf: .work,
                pinned: true,
                daysAgo: 3,
                records: record(.wifi(ssid: "Office", password: "secret", security: .wpa2)).map { [$0] } ?? []
            ),
            tag(
                id: "33333333-3333-3333-3333-333333333333",
                name: "Ключи",
                note: "Ящик",
                uid: "04:CC:03",
                shelf: .things,
                pinned: false,
                daysAgo: 5,
                records: record(.text("Кладовая")).map { [$0] } ?? []
            )
        ]
    }

    private static func record(_ command: ComposeCommand) -> StoredRecord? {
        guard let payload = try? NDEFCodec.payload(for: command) else { return nil }
        return NDEFCodec.storedRecord(from: payload)
    }

    private static func tag(
        id: String,
        name: String,
        note: String,
        uid: String,
        shelf: Shelf,
        pinned: Bool,
        daysAgo: Int,
        records: [StoredRecord]
    ) -> TagRecord {
        TagRecord(
            id: UUID(uuidString: id)!,
            name: name,
            note: note,
            uid: uid,
            typeName: "Ultralight / NTAG",
            technology: "ISO 14443 · 7 байт",
            manufacturer: "NXP Semiconductors",
            ndefStatus: .readWrite,
            capacity: 144,
            records: records,
            scannedAt: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            pinned: pinned,
            shelf: shelf
        )
    }
}
#endif
