import XCTest
@testable import Metki

final class DomainTests: XCTestCase {
    func testLocalizedByteCountsUseRussianAndEnglishPluralRules() throws {
        let cases: [(String, [(Int, String)])] = [
            ("ru", [(0, "0 байт"), (1, "1 байт"), (2, "2 байта"), (5, "5 байт"), (11, "11 байт"), (21, "21 байт"), (22, "22 байта"), (25, "25 байт"), (144, "144 байта")]),
            ("en", [(0, "0 bytes"), (1, "1 byte"), (2, "2 bytes"), (11, "11 bytes"), (21, "21 bytes")])
        ]
        for (language, counts) in cases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let format = bundle.localizedString(forKey: "%lld байт", value: nil, table: nil)
            for (count, expected) in counts {
                XCTAssertEqual(String(format: format, locale: Locale(identifier: language), arguments: [count]), expected)
            }
        }
    }

    func testShelfLocalizationPreservesStoredNamesAndUserRenames() throws {
        let defaults = ShelfCatalog.defaults()
        let home = try XCTUnwrap(defaults.first { $0.id == ShelfCatalog.homeID })
        XCTAssertEqual(home.name, "Дом")
        XCTAssertEqual(home.displayName, Shelf.home.title)
        XCTAssertEqual(home.localizationKey, "Дом")

        var renamed = home
        renamed.name = "My workshop"
        XCTAssertEqual(renamed.displayName, "My workshop")
        XCTAssertNil(renamed.localizationKey)
        let custom = ShelfDefinition(id: UUID(), name: "Дом", sortIndex: 4, systemKey: nil)
        XCTAssertEqual(custom.displayName, "Дом")
        XCTAssertNil(custom.localizationKey)

        let archive = try TagCodec.archiveData(tags: [], shelves: [home, custom])
        XCTAssertEqual(try TagCodec.decode(archive).shelves.map(\.name), ["Дом", "Дом"])
    }

    func testComposerNormalizesURLAndRejectsEmptyText() throws {
        let url = try RecordComposer.url("example.com")
        XCTAssertEqual(url, .uri("https://example.com"))
        XCTAssertThrowsError(try RecordComposer.text("   "))
    }

    func testComposerGeoAcceptsCommaDecimals() throws {
        let command = try RecordComposer.geo(latitude: "55,75", longitude: "37,61")
        XCTAssertEqual(command, .uri("geo:55.750000,37.610000"))
        XCTAssertThrowsError(try RecordComposer.geo(latitude: "120", longitude: "0"))
    }

    func testWiFiPayloadRoundTrip() {
        let open = WiFiPayload.bytes(ssid: "Дом", password: "", security: .open)
        XCTAssertEqual(WiFiPayload.fields(from: open).ssid, "Дом")
        XCTAssertEqual(WiFiPayload.fields(from: open).detail, "Открытая")

        let locked = WiFiPayload.bytes(ssid: "office", password: "secret", security: .wpa2)
        let fields = WiFiPayload.fields(from: locked)
        XCTAssertEqual(fields.ssid, "office")
        XCTAssertTrue(fields.detail.contains("WPA2"))
        XCTAssertTrue(fields.detail.contains("secret"))
    }

    func testOldLibraryJSONWithoutShelfStillDecodes() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Офис","note":"","uid":"04:11","typeName":"NTAG","technology":"ISO","manufacturer":"NXP","ndefStatus":"readWrite","capacity":144,"records":[],"scannedAt":"2026-10-15T12:00:00Z"}]
        """
        let tags = try TagCodec.tags(from: Data(json.utf8))
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name, "Офис")
        XCTAssertFalse(tags[0].pinned)
        XCTAssertEqual(tags[0].shelf, .inbox)
    }

    func testComposerRejectsBlankAddressAndShortPhone() {
        XCTAssertThrowsError(try RecordComposer.url("https://"))
        XCTAssertThrowsError(try RecordComposer.url("http://"))
        XCTAssertThrowsError(try RecordComposer.phone("12-34"))
        XCTAssertThrowsError(try RecordComposer.email("почта"))
        XCTAssertThrowsError(try RecordComposer.wifi(ssid: "  ", password: "x", security: .wpa2))
        XCTAssertThrowsError(try RecordComposer.wifi(ssid: "home", password: "", security: .wpa2))
        XCTAssertEqual(
            try RecordComposer.phone("+7 (900) 111-22-33"),
            .uri("tel:+79001112233")
        )
        XCTAssertEqual(try RecordComposer.email(" a@b.c "), .uri("mailto:a@b.c"))
        XCTAssertEqual(
            try RecordComposer.wifi(ssid: " Cafe ", password: "", security: .open),
            .wifi(ssid: "Cafe", password: "", security: .open)
        )
        XCTAssertThrowsError(try RecordComposer.geo(latitude: "90.1", longitude: "0"))
        XCTAssertEqual(
            try RecordComposer.geo(latitude: "-90", longitude: "180"),
            .uri("geo:-90.000000,180.000000")
        )
    }

    func testSMSEncodingKeepsReservedCharacters() throws {
        let command = try RecordComposer.sms(number: "+7 (900) 111-22-33", body: "привет & мир")
        guard case .uri(let value) = command else {
            return XCTFail("Ожидалась SMS-ссылка")
        }
        XCTAssertEqual(
            value,
            "sms:+79001112233?body=%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%26%20%D0%BC%D0%B8%D1%80"
        )
    }

    func testPayloadsRoundTrip() throws {
        let sms = try RecordComposer.sms(number: "89001112233", body: "привет & мир")
        let cases: [(String, ComposeCommand)] = [
            ("text", try RecordComposer.text("Привет\nмир")),
            ("url", try RecordComposer.url("http://example.com/a")),
            ("phone", try RecordComposer.phone("+7 (900) 111-22-33")),
            ("email", try RecordComposer.email("a@b.c")),
            ("sms", sms),
            ("geo", try RecordComposer.geo(latitude: "55,75", longitude: "37,61")),
            ("wifi", try RecordComposer.wifi(ssid: "Office", password: "secret", security: .wpa2)),
            ("open", try RecordComposer.wifi(ssid: "Cafe", password: "nope", security: .open))
        ]
        var storedByName: [String: StoredRecord] = [:]
        for (name, command) in cases {
            let payload = try NDEFCodec.payload(for: command)
            let stored = NDEFCodec.storedRecord(from: payload)
            let rewritten = NDEFCodec.message(from: [stored]).records.first?.payload
            storedByName[name] = stored
            XCTAssertEqual(rewritten, payload.payload, name)
        }

        XCTAssertEqual(storedByName["text"]?.kind, .text)
        XCTAssertEqual(storedByName["text"]?.title, "Привет\nмир")
        XCTAssertEqual(storedByName["url"]?.kind, .url)
        XCTAssertEqual(storedByName["url"]?.title, "http://example.com/a")
        XCTAssertEqual(storedByName["url"]?.actionURL?.absoluteString, "http://example.com/a")
        XCTAssertEqual(storedByName["phone"]?.kind, .phone)
        XCTAssertEqual(storedByName["phone"]?.title, "+79001112233")
        XCTAssertEqual(storedByName["phone"]?.actionURL?.absoluteString, "tel:+79001112233")
        XCTAssertEqual(storedByName["email"]?.kind, .email)
        XCTAssertEqual(storedByName["email"]?.title, "a@b.c")
        XCTAssertEqual(storedByName["email"]?.actionURL?.absoluteString, "mailto:a@b.c")
        XCTAssertEqual(storedByName["sms"]?.kind, .sms)
        XCTAssertEqual(storedByName["sms"]?.title, "89001112233")
        XCTAssertEqual(storedByName["sms"]?.detail, "привет & мир")
        XCTAssertEqual(
            storedByName["sms"]?.actionURL?.absoluteString,
            "sms:89001112233?body=%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%26%20%D0%BC%D0%B8%D1%80"
        )
        XCTAssertEqual(storedByName["geo"]?.kind, .geo)
        XCTAssertEqual(storedByName["geo"]?.title, "55.750000,37.610000")
        XCTAssertEqual(storedByName["geo"]?.actionTitle, "На карте")
        XCTAssertEqual(
            storedByName["geo"]?.actionURL?.absoluteString,
            "http://maps.apple.com/?ll=55.750000,37.610000"
        )
        XCTAssertEqual(storedByName["wifi"]?.kind, .wifi)
        XCTAssertEqual(storedByName["wifi"]?.title, "Office")
        XCTAssertTrue(storedByName["wifi"]?.detail.contains("secret") == true)
        XCTAssertEqual(storedByName["open"]?.title, "Cafe")
        XCTAssertFalse(storedByName["open"]?.detail.contains("nope") == true)
        XCTAssertTrue(storedByName["open"]?.detail.contains("Открытая") == true)

        let one = NDEFCodec.encodedLength(of: [storedByName["text"]!])
        let two = NDEFCodec.encodedLength(of: [storedByName["text"]!, storedByName["url"]!])
        XCTAssertGreaterThan(one, 0)
        XCTAssertLessThan(one, 144)
        XCTAssertGreaterThan(two, one)
        XCTAssertEqual(NDEFCodec.emptyMessage().records.count, 1)
    }

    func testContactRoundTrip() throws {
        let command = try RecordComposer.contact(
            name: " Анна ",
            phone: "+7 (900) 111-22-33",
            email: " anna@mail.com "
        )
        guard case .contact(let name, let phone, let email) = command else {
            return XCTFail("Ожидалась визитка")
        }
        XCTAssertEqual(name, "Анна")
        XCTAssertEqual(phone, "+79001112233")
        XCTAssertEqual(email, "anna@mail.com")
        XCTAssertThrowsError(try RecordComposer.contact(name: " ", phone: "123", email: "нет"))

        let text = RecordComposer.vcard(name: name, phone: phone, email: email)
        XCTAssertTrue(text.contains("\r\n"))
        XCTAssertTrue(text.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n"))

        let payload = try NDEFCodec.payload(for: command)
        XCTAssertEqual(payload.typeNameFormat, .media)
        XCTAssertEqual(String(data: payload.type, encoding: .utf8), "text/vcard")
        XCTAssertEqual(String(data: payload.payload, encoding: .utf8), text)

        let stored = NDEFCodec.storedRecord(from: payload)
        XCTAssertEqual(stored.kind, .contact)
        XCTAssertEqual(stored.title, "Анна")
        XCTAssertEqual(stored.detail, "+79001112233 · anna@mail.com")
        XCTAssertTrue(stored.opensContact)
        XCTAssertEqual(stored.actionTitle, "В Контакты")
        XCTAssertEqual(NDEFCodec.message(from: [stored]).records.first?.payload, payload.payload)

        let parsed = RecordComposer.vcardFields(from: text)
        XCTAssertEqual(parsed, VCardFields(name: "Анна", phone: "+79001112233", email: "anna@mail.com"))
    }

    func testCopiedCardOmitsWiFiPassword() throws {
        let payload = try NDEFCodec.payload(
            for: RecordComposer.wifi(ssid: "Office", password: "secret", security: .wpa2)
        )
        let record = NDEFCodec.storedRecord(from: payload)
        XCTAssertTrue(record.detail.contains("secret"))
        let card = TagRecord(
            id: UUID(),
            name: "Офис",
            note: "",
            uid: "04:AA",
            typeName: "NTAG",
            technology: "ISO",
            manufacturer: "NXP",
            ndefStatus: .readWrite,
            capacity: 144,
            records: [record],
            scannedAt: Date()
        )
        XCTAssertTrue(card.summary().contains("Office"))
        XCTAssertTrue(card.summary().contains("WPA2"))
        XCTAssertFalse(card.summary().contains("secret"))
        XCTAssertFalse(card.summary().localizedCaseInsensitiveContains("пароль"))
    }

    func testMalformedWiFiDoesNotCrash() {
        let fields = WiFiPayload.fields(from: Data([0x00, 0x01]))
        XCTAssertNil(fields.ssid)
        XCTAssertEqual(fields.detail, "")
    }

    func testNamesHexAndStatus() {
        XCTAssertEqual(Hex.string(Data()), "—")
        XCTAssertEqual(Hex.string(Data([0x04, 0x0A])), "04:0A")
        XCTAssertTrue(Hex.spaced(Data(repeating: 1, count: 60), limit: 48).hasSuffix("…"))

        let long = String(repeating: "я", count: 50)
        var scan = TagScan(
            id: UUID(),
            identity: TagIdentity(uid: "04:01:02", typeName: "NTAG", technology: "ISO", manufacturer: "NXP"),
            ndefStatus: .readWrite,
            capacity: 144,
            records: [
                StoredRecord(
                    id: UUID(),
                    kind: .text,
                    title: long,
                    detail: "",
                    typeNameFormat: 1,
                    type: Data(),
                    identifier: Data(),
                    payload: Data()
                )
            ],
            scannedAt: Date()
        )
        XCTAssertEqual(scan.suggestedName.count, 42)
        XCTAssertEqual(scan.statusLine, "Можно записать · 144 байта")
        scan.records[0].kind = .url
        scan.records[0].title = "https://kitchen.example/path"
        XCTAssertEqual(scan.suggestedName, "kitchen.example")
        scan.ndefStatus = .unsupported
        scan.capacity = nil
        XCTAssertEqual(scan.statusLine, "Без NDEF")
    }

    func testQueryPinsFirstAndFiltersShelf() {
        let home = sample(name: "Кухня", shelf: .home, pinned: false, daysAgo: 1)
        let work = sample(name: "Стол", shelf: .work, pinned: true, daysAgo: 3)
        let tags = [home, work]
        let visible = LibraryQuery.apply(tags: tags, search: "", scope: .all, sort: .recent, shelves: ShelfCatalog.defaults())
        XCTAssertEqual(visible.map(\.name), ["Стол", "Кухня"])
        let onlyHome = LibraryQuery.apply(
            tags: tags,
            search: "кух",
            scope: .shelf(ShelfCatalog.homeID),
            sort: .name,
            shelves: ShelfCatalog.defaults()
        )
        XCTAssertEqual(onlyHome.map(\.name), ["Кухня"])
    }

    @MainActor
    func testImportMergesByUIDAndUndoRestoresDelete() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("tags.json")
        let store = LibraryStore(storage: JSONTagStoring(fileURL: url))
        let original = sample(name: "Дом", uid: "04:AA", shelf: .home, pinned: true, daysAgo: 0)
        try store.importData(TagCodec.archiveData(tags: [original]))
        var replacement = original
        replacement.name = "Квартира"
        replacement.pinned = false
        replacement.shelf = .inbox
        let summary = try store.importData(TagCodec.archiveData(tags: [replacement]))
        XCTAssertEqual(summary.inserted, 0)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(store.tags.count, 1)
        XCTAssertEqual(store.tags[0].name, "Квартира")
        XCTAssertTrue(store.tags[0].pinned)
        XCTAssertEqual(store.tags[0].shelf, .home)

        let id = store.tags[0].id
        store.delete(id: id)
        XCTAssertTrue(store.tags.isEmpty)
        store.undoDelete()
        XCTAssertEqual(store.tags.map(\.id), [id])

        let reloaded = LibraryStore(storage: JSONTagStoring(fileURL: url))
        XCTAssertEqual(reloaded.tags.map(\.name), ["Квартира"])
    }

    @MainActor
    func testLibrarySearchDeleteExportAndRescan() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("tags.json")
        let store = LibraryStore(storage: JSONTagStoring(fileURL: url))
        let home = sample(name: "Кухня", uid: "04:AA", shelf: .home, pinned: false, daysAgo: 1)
        var work = sample(name: "Стол", uid: "04:BB", shelf: .work, pinned: true, daysAgo: 3)
        work.records = [
            StoredRecord(
                id: UUID(),
                kind: .text,
                title: "пароль",
                detail: "секрет",
                typeNameFormat: 1,
                type: Data(),
                identifier: Data(),
                payload: Data()
            )
        ]
        let summary = try store.importData(try TagCodec.archiveData(tags: [home, work]))
        XCTAssertEqual(summary.inserted, 2)
        XCTAssertEqual(summary.message, "Новых: 2, обновлено: 0")

        store.search = "секрет"
        XCTAssertEqual(store.visibleTags.map(\.name), ["Стол"])
        store.search = ""
        store.scope = .shelf(ShelfCatalog.homeID)
        store.delete(offsets: IndexSet(integer: 0), in: store.visibleTags)
        XCTAssertEqual(store.tags.map(\.name), ["Стол"])
        store.undoDelete()
        XCTAssertEqual(Set(store.tags.map(\.name)), ["Кухня", "Стол"])

        let id = store.tags.first { $0.name == "Кухня" }!.id
        store.update(id: id, name: "   ", note: "  ящик ")
        XCTAssertEqual(store.tag(id: id)?.name, "Кухня")
        XCTAssertEqual(store.tag(id: id)?.note, "ящик")
        store.togglePin(id: id)
        XCTAssertEqual(store.tag(id: id)?.pinned, true)

        let export = try XCTUnwrap(store.makeExportURL(redactWiFi: false))
        let exported = try TagCodec.tags(from: Data(contentsOf: export))
        XCTAssertEqual(Set(exported.map(\.uid)), ["04:AA", "04:BB"])

        let scan = TagScan(
            id: UUID(),
            identity: TagIdentity(uid: "04:AA", typeName: "Ultralight / NTAG", technology: "ISO", manufacturer: "NXP"),
            ndefStatus: .readOnly,
            capacity: 64,
            records: [
                StoredRecord(
                    id: UUID(),
                    kind: .url,
                    title: "https://kitchen.example/path",
                    detail: "",
                    typeNameFormat: 1,
                    type: Data(),
                    identifier: Data(),
                    payload: Data()
                )
            ],
            scannedAt: Date()
        )
        store.save(scan: scan, name: "  ", note: " новая ")
        let updated = store.tags.first { $0.uid == "04:AA" }
        XCTAssertEqual(updated?.name, "kitchen.example")
        XCTAssertEqual(updated?.note, "новая")
        XCTAssertEqual(updated?.pinned, true)
        XCTAssertEqual(updated?.shelf, .home)
        XCTAssertEqual(updated?.ndefStatus, .readOnly)

        store.save(scan: TagScan(
            id: UUID(),
            identity: TagIdentity(uid: "—", typeName: "Неизвестная метка", technology: "—", manufacturer: "—"),
            ndefStatus: .unknown,
            capacity: nil,
            records: [],
            scannedAt: Date()
        ), name: "Одна", note: "")
        store.save(scan: TagScan(
            id: UUID(),
            identity: TagIdentity(uid: "—", typeName: "Неизвестная метка", technology: "—", manufacturer: "—"),
            ndefStatus: .unknown,
            capacity: nil,
            records: [],
            scannedAt: Date()
        ), name: "Другая", note: "")
        XCTAssertEqual(store.tags.filter { $0.uid == "—" }.count, 2)
        XCTAssertNil(store.existing(uid: "—"))

        let unknownID = store.tags.first { $0.name == "Одна" }!.id
        store.delete(id: unknownID)
        store.dismissUndo()
        store.undoDelete()
        let afterDismiss = store.tags.count
        XCTAssertFalse(store.tags.contains { $0.name == "Одна" })

        XCTAssertThrowsError(try store.importData(Data("nope".utf8))) { error in
            XCTAssertEqual(error as? ArchiveError, .unreadable)
        }
        XCTAssertThrowsError(try store.importData(try TagCodec.archiveData(tags: []))) { error in
            XCTAssertEqual(error as? ArchiveError, .empty)
        }

        let reloaded = LibraryStore(storage: JSONTagStoring(fileURL: url))
        XCTAssertEqual(reloaded.tags.count, afterDismiss)
        XCTAssertTrue(reloaded.tags.contains { $0.uid == "04:AA" && $0.name == "kitchen.example" && $0.shelf == .home })
    }

    @MainActor
    func testRescanKeepsNameAndStoresPreviousPayload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("tags.json")
        let store = LibraryStore(storage: JSONTagStoring(fileURL: url))
        let first = scan(uid: "04:AA", title: "Было", payload: Data("one".utf8))
        store.save(scan: first, name: "Кухня", note: "ящик")
        store.setShelf(id: store.tags[0].id, shelfId: ShelfCatalog.homeID)
        store.save(scan: scan(uid: "04:AA", title: "Было", payload: Data("one".utf8)), name: "Другое", note: "")
        XCTAssertEqual(store.tags[0].scans.count, 0)
        XCTAssertEqual(store.tags[0].name, "Другое")
        store.save(scan: scan(uid: "04:AA", title: "Стало", payload: Data("two".utf8)), name: "", note: "", preserveName: true)
        XCTAssertEqual(store.tags[0].scans.count, 1)
        XCTAssertEqual(store.tags[0].scans[0].records.first?.payload, Data("one".utf8))
        XCTAssertEqual(store.tags[0].name, "Другое")
        XCTAssertEqual(store.tags[0].shelfId, ShelfCatalog.homeID)
        XCTAssertEqual(store.tags[0].records.first?.title, "Стало")
    }

    func testScanDiffReportsAddRemoveAndChange() throws {
        let original = try record(.text("Было"))
        let added = try record(.uri("https://example.com"))
        let changed = try record(.text("Стало"))
        XCTAssertEqual(ScanDiff.delta(from: [original], to: [original, added]).added, 1)
        XCTAssertEqual(ScanDiff.delta(from: [original, added], to: [original]).removed, 1)
        XCTAssertEqual(ScanDiff.delta(from: [original], to: [changed]).modified, 1)

        let card = sample(name: "Кухня", shelf: .home, pinned: false, daysAgo: 0)
        var withRecord = card
        withRecord.records = [original]
        let emptied = TagScan(
            id: UUID(),
            identity: TagIdentity(uid: card.uid, typeName: card.typeName, technology: card.technology, manufacturer: card.manufacturer),
            ndefStatus: .readWrite,
            capacity: 144,
            records: [],
            scannedAt: Date()
        )
        XCTAssertEqual(ScanDiff.compare(card: withRecord, scan: emptied), .emptied)
    }

    func testOldLibraryJSONWithoutNewFieldsStillDecodes() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Офис","note":"","uid":"04:11","typeName":"NTAG","technology":"ISO","manufacturer":"NXP","ndefStatus":"readWrite","capacity":144,"records":[],"scannedAt":"2026-10-15T12:00:00Z","shelf":"work"}]
        """
        let tags = try TagCodec.tags(from: Data(json.utf8))
        XCTAssertEqual(tags[0].shelf, .work)
        XCTAssertEqual(tags[0].shelfId, ShelfCatalog.workID)
        XCTAssertTrue(tags[0].scans.isEmpty)
        XCTAssertNil(tags[0].photoFile)
    }

    @MainActor
    func testDeletingShelfMovesCardsToInbox() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("tags.json")
        let store = LibraryStore(storage: JSONTagStoring(fileURL: url))
        let tag = sample(name: "Гараж", shelf: .home, pinned: false, daysAgo: 0)
        try store.importData(TagCodec.archiveData(tags: [tag], shelves: ShelfCatalog.defaults()))
        let created = try XCTUnwrap(store.addShelf(name: "Гаражная"))
        store.setShelf(id: store.tags[0].id, shelfId: created)
        XCTAssertEqual(store.tags[0].shelf, .custom)
        store.deleteShelf(id: created)
        XCTAssertEqual(store.tags[0].shelfId, ShelfCatalog.inboxID)
        XCTAssertFalse(store.shelves.contains { $0.id == created })
        store.deleteShelf(id: ShelfCatalog.inboxID)
        XCTAssertTrue(store.shelves.contains { $0.id == ShelfCatalog.inboxID })
    }

    @MainActor
    func testTemplateSurvivesReloadAndIsNotATag() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("tags.json")
        let store = LibraryStore(storage: JSONTagStoring(fileURL: url))
        let stored = try record(.text("Шаблонный текст"))
        _ = store.saveTemplate(name: "Домофон", records: [stored])
        let reloaded = LibraryStore(storage: JSONTagStoring(fileURL: url))
        XCTAssertEqual(reloaded.templates.map(\.name), ["Домофон"])
        XCTAssertFalse(reloaded.tags.contains { $0.name == "Домофон" })
        let file = try XCTUnwrap(reloaded.exportURL(for: reloaded.templates[0]))
        let summary = try store.importData(Data(contentsOf: file))
        XCTAssertEqual(summary.templates, 1)
        XCTAssertEqual(store.tags.filter { $0.name == "Домофон" }.count, 0)
    }

    func testRedactedExportDropsWiFiPassword() throws {
        let payload = try NDEFCodec.payload(for: RecordComposer.wifi(ssid: "Office", password: "secret", security: .wpa2))
        let record = NDEFCodec.storedRecord(from: payload)
        let card = TagRecord(
            id: UUID(),
            name: "Офис",
            note: "",
            uid: "04:AA",
            typeName: "NTAG",
            technology: "ISO",
            manufacturer: "NXP",
            ndefStatus: .readWrite,
            capacity: 144,
            records: [record],
            scannedAt: Date()
        )
        let data = try TagCodec.archiveData(tags: [card], redactWiFi: true)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertTrue(text.contains("Office"))
        let decoded = try TagCodec.tags(from: data)
        let fields = WiFiPayload.fields(from: decoded[0].records[0].payload)
        XCTAssertEqual(fields.ssid, "Office")
        XCTAssertNil(fields.password)
    }

    func testReorderingDraftsChangesRecordOrder() throws {
        let text = try record(.text("Сначала"))
        let link = try record(.uri("https://example.com/path"))
        var records = [text, link]
        records.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        let message = NDEFCodec.message(from: records)
        XCTAssertEqual(message.records.first?.payload, link.payload)
        XCTAssertNotEqual(
            NDEFCodec.message(from: [text, link]).records.map { $0.payload },
            message.records.map { $0.payload }
        )
        XCTAssertEqual(NDEFCodec.encodedLength(of: records), message.length)
    }

    func testSeriesCheckCatchesPayloadMismatch() throws {
        let draft = try record(.text("Черновик"))
        var written = draft
        written.payload = Data("другое".utf8)
        XCTAssertFalse(DraftMatch.samePayloads([written], [draft]))
        XCTAssertTrue(DraftMatch.samePayloads([draft], [draft]))
    }

    func testNTAGLayoutReadsVersionBytes() {
        var version = Data([0x00, 0x04, 0x04, 0x01, 0x01, 0x00, 0x0F, 0x03])
        XCTAssertEqual(NTAGLayout.modelName(version: version), "NTAG213")
        XCTAssertEqual(NTAGLayout.pages(version: version)?.pwd, 0x2B)
        version[6] = 0x11
        XCTAssertEqual(NTAGLayout.modelName(version: version), "NTAG215")
        version[6] = 0x13
        XCTAssertEqual(NTAGLayout.pages(storageSize: 0x13)?.pack, 0xE6)
        XCTAssertNil(NTAGLayout.modelName(version: Data([0x00, 0x02])))
    }

    func testMergeKeepsNewerRecordsAndMarksNameConflict() {
        var local = sample(name: "Кухня", uid: "04:AA", shelf: .home, pinned: true, daysAgo: 2)
        local.records = [StoredRecord(id: UUID(), kind: .text, title: "Старое", detail: "", typeNameFormat: 1, type: Data(), identifier: Data(), payload: Data("old".utf8))]
        var remote = local
        remote.name = "Плита"
        remote.pinned = false
        remote.scannedAt = Date()
        remote.records = [StoredRecord(id: UUID(), kind: .text, title: "Новое", detail: "", typeNameFormat: 1, type: Data(), identifier: Data(), payload: Data("new".utf8))]
        let merged = LibraryMerge.tags(local: [local], remote: [remote])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Плита")
        XCTAssertTrue(merged[0].nameConflict)
        XCTAssertEqual(merged[0].alternateName, "Кухня")
        XCTAssertEqual(merged[0].records[0].payload, Data("new".utf8))
        XCTAssertTrue(merged[0].pinned)
    }

    func testZipListsLibraryFile() {
        let archive = ZipArchive.data(files: [("library.json", Data("{}".utf8))])
        XCTAssertTrue(archive.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
        XCTAssertTrue(String(decoding: archive, as: UTF8.self).contains("library.json"))
    }

    func testTagSecretStaysOutOfArchive() throws {
        let uid = "04:SECRET:\(UUID().uuidString)"
        let password = Data([0xA5, 0x5A, 0x3C, 0xC3])
        let pack = Data([0x11, 0x22])
        TagSecretStore.save(uid: uid, password: password, pack: pack)
        defer { TagSecretStore.delete(uid: uid) }
        let loaded = TagSecretStore.load(uid: uid)
        XCTAssertEqual(loaded?.password, password)
        XCTAssertEqual(loaded?.pack, pack)
        let card = sample(name: "Секрет", uid: uid, shelf: .home, pinned: false, daysAgo: 0)
        let data = try TagCodec.archiveData(tags: [card], shelves: ShelfCatalog.defaults())
        XCTAssertNil(data.range(of: password))
        XCTAssertNil(TagSecretStore.load(uid: "missing-\(uid)"))
    }

    private func record(_ command: ComposeCommand) throws -> StoredRecord {
        NDEFCodec.storedRecord(from: try NDEFCodec.payload(for: command))
    }

    private func scan(uid: String, title: String, payload: Data) -> TagScan {
        TagScan(
            id: UUID(),
            identity: TagIdentity(uid: uid, typeName: "NTAG213", technology: "ISO", manufacturer: "NXP"),
            ndefStatus: .readWrite,
            capacity: 144,
            records: [
                StoredRecord(
                    id: UUID(),
                    kind: .text,
                    title: title,
                    detail: "",
                    typeNameFormat: 1,
                    type: Data([0x54]),
                    identifier: Data(),
                    payload: payload
                )
            ],
            scannedAt: Date()
        )
    }

    func testDebugSeedBuildsThreeShelves() {
        let tags = DebugLibrary.make()
        XCTAssertEqual(Set(tags.map(\.name)), ["Кухня", "Офис", "Ключи"])
        XCTAssertEqual(tags.first { $0.name == "Кухня" }?.records.first?.title, "https://kitchen.example")
        XCTAssertEqual(tags.first { $0.name == "Офис" }?.records.first?.title, "Office")
        XCTAssertEqual(tags.first { $0.name == "Ключи" }?.records.first?.title, "Кладовая")
    }

    private func sample(
        name: String,
        uid: String = "04:01",
        shelf: Shelf,
        pinned: Bool,
        daysAgo: Int
    ) -> TagRecord {
        TagRecord(
            id: UUID(),
            name: name,
            note: "",
            uid: uid,
            typeName: "Ultralight / NTAG",
            technology: "ISO 14443",
            manufacturer: "NXP Semiconductors",
            ndefStatus: .readWrite,
            capacity: 144,
            records: [],
            scannedAt: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            pinned: pinned,
            shelf: shelf
        )
    }
}
