import CoreNFC
import Foundation

enum NFCFailure: LocalizedError {
    case unavailable
    case busy
    case cancelled
    case surfaced
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.text("NFC есть на iPhone 7 и новее. На симуляторе считывание не работает.")
        case .busy:
            return L10n.text("Сессия уже идёт.")
        case .cancelled, .surfaced:
            return nil
        case .message(let text):
            return text
        }
    }
}

final class NFCService: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    static let shared = NFCService()

    static var isAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }

    private var session: NFCTagReaderSession?
    private var operation: Operation?
    private var continuation: CheckedContinuation<TagScan, Error>?
    private var didResume = false

    private enum Operation {
        case read
        case write(NFCNDEFMessage)
        case protect(password: Data, pack: Data)
        case unprotect(password: Data)
        case lock
    }

    func read() async throws -> TagScan {
        try await start(.read, prompt: L10n.text("Поднесите верхнюю часть iPhone к метке"))
    }

    func write(_ message: NFCNDEFMessage) async throws -> TagScan {
        try await start(.write(message), prompt: L10n.text("Поднесите метку, чтобы записать"))
    }

    func clear() async throws -> TagScan {
        try await start(.write(NDEFCodec.emptyMessage()), prompt: L10n.text("Поднесите метку, чтобы очистить"))
    }

    func protect(password: Data, pack: Data) async throws -> TagScan {
        guard password.count == 4, pack.count == 2 else {
            throw NFCFailure.message(L10n.text("Пароль — 4 символа, код PACK — 2."))
        }
        return try await start(.protect(password: password, pack: pack), prompt: L10n.text("Поднесите метку, чтобы поставить пароль"))
    }

    func unprotect(password: Data) async throws -> TagScan {
        guard password.count == 4 else {
            throw NFCFailure.message(L10n.text("Пароль — 4 символа."))
        }
        return try await start(.unprotect(password: password), prompt: L10n.text("Поднесите метку, чтобы снять пароль"))
    }

    func lockTag() async throws -> TagScan {
        try await start(.lock, prompt: L10n.text("Поднесите метку, чтобы закрыть её"))
    }

    private func start(_ operation: Operation, prompt: String) async throws -> TagScan {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard self.continuation == nil else {
                    continuation.resume(throwing: NFCFailure.busy)
                    return
                }
                guard NFCTagReaderSession.readingAvailable else {
                    continuation.resume(throwing: NFCFailure.unavailable)
                    return
                }
                self.didResume = false
                self.operation = operation
                self.continuation = continuation
                guard let session = NFCTagReaderSession(
                    pollingOption: [.iso14443, .iso15693, .iso18092],
                    delegate: self,
                    queue: .main
                ) else {
                    self.finish(.failure(NFCFailure.unavailable))
                    return
                }
                session.alertMessage = prompt
                self.session = session
                session.begin()
            }
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if !didResume {
            if Self.isCancellation(error) {
                finish(.failure(NFCFailure.cancelled))
            } else {
                finish(.failure(NFCFailure.message(Self.describe(error))))
            }
        }
        self.session = nil
        operation = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = L10n.text("В поле несколько меток. Оставьте одну.")
            session.restartPolling()
            return
        }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(session, Self.describe(error))
                return
            }
            Task { @MainActor in
                await self.consume(tag, session: session)
            }
        }
    }

    @MainActor
    private func consume(_ tag: NFCTag, session: NFCTagReaderSession) async {
        var identity = Self.identity(of: tag)
        let miFare = Self.ultralight(tag)
        if let miFare {
            if let data = try? await transceive(miFare, UltralightCommand.getVersion),
               let name = NTAGLayout.modelName(version: data) {
                identity.typeName = name
            }
        }
        guard let ndef = Self.ndefTag(from: tag) else {
            succeed(session, scan: makeScan(identity: identity, status: .unsupported, capacity: nil, records: []))
            return
        }
        session.alertMessage = L10n.text("Не убирайте метку")
        let (status, capacity, error) = await query(ndef)
        switch operation {
        case .read, .none:
            if error != nil {
                succeed(session, scan: makeScan(identity: identity, status: .unknown, capacity: nil, records: []))
                return
            }
            await readMessage(ndef, session: session, identity: identity, status: status, capacity: capacity)
        case .write(let message):
            if let error {
                fail(session, Self.describe(error))
                return
            }
            if let miFare, let secret = TagSecretStore.load(uid: identity.uid) {
                do {
                    _ = try await transceive(miFare, UltralightCommand.pwdAuth(secret.password))
                } catch {
                    fail(session, L10n.text("Сохранённый пароль не подошёл."))
                    return
                }
            }
            await writeMessage(message, to: ndef, session: session, identity: identity, status: status, capacity: capacity)
        case .protect(let password, let pack):
            await protect(miFare, session: session, identity: identity, password: password, pack: pack, status: status, capacity: capacity)
        case .unprotect(let password):
            await unprotect(miFare, session: session, identity: identity, password: password, status: status, capacity: capacity)
        case .lock:
            if let miFare, let secret = TagSecretStore.load(uid: identity.uid) {
                _ = try? await transceive(miFare, UltralightCommand.pwdAuth(secret.password))
            }
            await lock(ndef, session: session, identity: identity, status: status, capacity: capacity)
        }
    }

    @MainActor
    private func protect(
        _ tag: NFCMiFareTag?,
        session: NFCTagReaderSession,
        identity: TagIdentity,
        password: Data,
        pack: Data,
        status: NDEFState,
        capacity: Int
    ) async {
        guard let tag, tag.mifareFamily == .ultralight else {
            fail(session, L10n.text("Пароль только для NTAG и Ultralight."))
            return
        }
        do {
            let version = try await transceive(tag, UltralightCommand.getVersion)
            guard let pages = NTAGLayout.pages(version: version) else {
                fail(session, L10n.text("Пароль доступен для NTAG213, 215 и 216."))
                return
            }
            session.alertMessage = L10n.text("Ставлю пароль…")
            _ = try await transceive(tag, UltralightCommand.write(page: pages.pwd, block: password))
            let packPage = try await transceive(tag, UltralightCommand.read(page: pages.pack))
            var packBlock = Data(pack.prefix(2))
            if packPage.count >= 4 {
                packBlock.append(packPage[2])
                packBlock.append(packPage[3])
            } else {
                packBlock.append(contentsOf: [0x00, 0x00])
            }
            _ = try await transceive(tag, UltralightCommand.write(page: pages.pack, block: packBlock))
            let authPage = try await transceive(tag, UltralightCommand.read(page: pages.auth0))
            guard authPage.count >= 4 else {
                fail(session, L10n.text("Не удалось прочитать страницу защиты."))
                return
            }
            var authBlock = Data(authPage.prefix(4))
            authBlock[3] = 0x04
            _ = try await transceive(tag, UltralightCommand.write(page: pages.auth0, block: authBlock))
            TagSecretStore.save(uid: identity.uid, password: password, pack: pack)
            let records = await readRecords(tag: tag)
            succeed(session, scan: makeScan(identity: identity, status: status, capacity: capacity, records: records), alert: L10n.text("Пароль поставлен"))
        } catch {
            fail(session, L10n.text("Не удалось поставить пароль. Держите телефон ближе."))
        }
    }

    @MainActor
    private func unprotect(
        _ tag: NFCMiFareTag?,
        session: NFCTagReaderSession,
        identity: TagIdentity,
        password: Data,
        status: NDEFState,
        capacity: Int
    ) async {
        guard let tag, tag.mifareFamily == .ultralight else {
            fail(session, L10n.text("Пароль только для NTAG и Ultralight."))
            return
        }
        do {
            let version = try await transceive(tag, UltralightCommand.getVersion)
            guard let pages = NTAGLayout.pages(version: version) else {
                fail(session, L10n.text("Пароль доступен для NTAG213, 215 и 216."))
                return
            }
            session.alertMessage = L10n.text("Снимаю пароль…")
            _ = try await transceive(tag, UltralightCommand.pwdAuth(password))
            let authPage = try await transceive(tag, UltralightCommand.read(page: pages.auth0))
            guard authPage.count >= 4 else {
                fail(session, L10n.text("Не удалось прочитать страницу защиты."))
                return
            }
            var authBlock = Data(authPage.prefix(4))
            authBlock[3] = 0xFF
            _ = try await transceive(tag, UltralightCommand.write(page: pages.auth0, block: authBlock))
            TagSecretStore.delete(uid: identity.uid)
            let records = await readRecords(tag: tag)
            succeed(session, scan: makeScan(identity: identity, status: status, capacity: capacity, records: records), alert: L10n.text("Пароль снят"))
        } catch {
            fail(session, L10n.text("Пароль не подошёл."))
        }
    }

    @MainActor
    private func lock(
        _ tag: NFCNDEFTag,
        session: NFCTagReaderSession,
        identity: TagIdentity,
        status: NDEFState,
        capacity: Int
    ) async {
        switch status {
        case .unsupported:
            fail(session, L10n.text("Эта метка не хранит NDEF."))
            return
        case .readOnly:
            fail(session, L10n.text("Метка уже закрыта."))
            return
        case .unknown, .readWrite:
            break
        }
        session.alertMessage = L10n.text("Закрываю метку…")
        do {
            try await writeLock(tag)
            let records = await readRecords(tag: tag)
            succeed(
                session,
                scan: makeScan(identity: identity, status: .readOnly, capacity: capacity, records: records),
                alert: L10n.text("Метка закрыта")
            )
        } catch {
            fail(session, Self.describe(error))
        }
    }

    @MainActor
    private func readMessage(
        _ tag: NFCNDEFTag,
        session: NFCTagReaderSession,
        identity: TagIdentity,
        status: NDEFState,
        capacity: Int
    ) async {
        let records = await readRecords(tag: tag)
        succeed(session, scan: makeScan(identity: identity, status: status, capacity: capacity, records: records))
    }

    @MainActor
    private func writeMessage(
        _ message: NFCNDEFMessage,
        to tag: NFCNDEFTag,
        session: NFCTagReaderSession,
        identity: TagIdentity,
        status: NDEFState,
        capacity: Int
    ) async {
        switch status {
        case .unsupported:
            fail(session, L10n.text("Эта метка не хранит NDEF."))
            return
        case .readOnly:
            fail(session, L10n.text("Метка закрыта для записи."))
            return
        case .unknown, .readWrite:
            break
        }
        if capacity > 0, message.length > capacity {
            fail(session, L10n.format("На метке %@, а запись занимает %@.", L10n.bytes(capacity), L10n.bytes(message.length)))
            return
        }
        session.alertMessage = L10n.text("Записываю…")
        do {
            try await writeNDEF(message, to: tag)
            let records = await readRecords(tag: tag)
            succeed(
                session,
                scan: makeScan(identity: identity, status: .readWrite, capacity: capacity, records: records),
                alert: L10n.text("Записано")
            )
        } catch {
            fail(session, Self.describe(error))
        }
    }

    private func makeScan(identity: TagIdentity, status: NDEFState, capacity: Int?, records: [StoredRecord]) -> TagScan {
        TagScan(
            id: UUID(),
            identity: identity,
            ndefStatus: status,
            capacity: capacity,
            records: records,
            scannedAt: Date()
        )
    }

    private func succeed(_ session: NFCTagReaderSession, scan: TagScan, alert: String = L10n.text("Готово")) {
        session.alertMessage = alert
        finish(.success(scan))
        session.invalidate()
    }

    private func fail(_ session: NFCTagReaderSession, _ message: String) {
        finish(.failure(NFCFailure.surfaced))
        session.invalidate(errorMessage: message)
    }

    private func finish(_ result: Result<TagScan, Error>) {
        guard !didResume, let continuation else { return }
        didResume = true
        self.continuation = nil
        continuation.resume(with: result)
    }

    @MainActor
    private func transceive(_ tag: NFCMiFareTag, _ command: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            tag.sendMiFareCommand(commandPacket: command) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    @MainActor
    private func query(_ tag: NFCNDEFTag) async -> (NDEFState, Int, Error?) {
        await withCheckedContinuation { continuation in
            tag.queryNDEFStatus { status, capacity, error in
                let mapped = error == nil ? Self.map(status) : NDEFState.unknown
                continuation.resume(returning: (mapped, capacity, error))
            }
        }
    }

    @MainActor
    private func readRecords(tag: NFCNDEFTag) async -> [StoredRecord] {
        await withCheckedContinuation { continuation in
            tag.readNDEF { message, error in
                if let error, !Self.isEmpty(error) {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: message?.records.map(NDEFCodec.storedRecord(from:)) ?? [])
            }
        }
    }

    @MainActor
    private func writeNDEF(_ message: NFCNDEFMessage, to tag: NFCNDEFTag) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tag.writeNDEF(message) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func writeLock(_ tag: NFCNDEFTag) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tag.writeLock { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func ultralight(_ tag: NFCTag) -> NFCMiFareTag? {
        guard case .miFare(let miFare) = tag, miFare.mifareFamily == .ultralight else { return nil }
        return miFare
    }

    private static func ndefTag(from tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let tag): return tag
        case .iso15693(let tag): return tag
        case .feliCa(let tag): return tag
        case .iso7816(let tag): return tag
        @unknown default: return nil
        }
    }

    private static func identity(of tag: NFCTag) -> TagIdentity {
        switch tag {
        case .miFare(let tag):
            let type: String
            switch tag.mifareFamily {
            case .ultralight: type = "Ultralight / NTAG"
            case .plus: type = "MIFARE Plus"
            case .desfire: type = "MIFARE DESFire"
            default: type = "ISO 14443 Type A"
            }
            return TagIdentity(
                uid: Hex.string(tag.identifier),
                typeName: type,
                technology: "ISO 14443 · \(L10n.bytes(tag.identifier.count))",
                manufacturer: manufacturer(tag.identifier)
            )
        case .iso15693(let tag):
            return TagIdentity(
                uid: Hex.string(tag.identifier),
                typeName: "ISO 15693",
                technology: "ISO 15693 · \(L10n.bytes(tag.identifier.count))",
                manufacturer: manufacturerCode(tag.icManufacturerCode)
            )
        case .feliCa(let tag):
            return TagIdentity(
                uid: Hex.string(tag.currentIDm),
                typeName: "FeliCa",
                technology: "FeliCa",
                manufacturer: "Sony"
            )
        case .iso7816(let tag):
            return TagIdentity(
                uid: Hex.string(tag.identifier),
                typeName: "ISO 7816",
                technology: "ISO 14443-4 · \(L10n.bytes(tag.identifier.count))",
                manufacturer: manufacturer(tag.identifier)
            )
        @unknown default:
            return TagIdentity(uid: "—", typeName: L10n.text("Неизвестная метка"), technology: "—", manufacturer: "—")
        }
    }

    private static func manufacturer(_ identifier: Data) -> String {
        guard identifier.count >= 7, let code = identifier.first else {
            if identifier.first == 0x08, identifier.count == 4 {
                return L10n.text("Случайный UID")
            }
            return identifier.isEmpty ? "—" : L10n.text("Не определён")
        }
        return manufacturerCode(Int(code))
    }

    private static func manufacturerCode(_ code: Int) -> String {
        switch code {
        case 0x02: return "STMicroelectronics"
        case 0x04: return "NXP Semiconductors"
        case 0x05: return "Infineon"
        case 0x07: return "Texas Instruments"
        case 0x16: return "EM Microelectronic"
        case 0x1D: return "Fudan Micro"
        default: return L10n.text("Не определён")
        }
    }

    private static func map(_ status: NFCNDEFStatus) -> NDEFState {
        switch status {
        case .readWrite: return .readWrite
        case .readOnly: return .readOnly
        case .notSupported: return .unsupported
        @unknown default: return .unknown
        }
    }

    private static func isEmpty(_ error: Error) -> Bool {
        (error as? NFCReaderError)?.code == .ndefReaderSessionErrorZeroLengthMessage
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let code = (error as? NFCReaderError)?.code
        return code == .readerSessionInvalidationErrorUserCanceled
            || code == .readerSessionInvalidationErrorFirstNDEFTagRead
    }

    static func describe(_ error: Error) -> String {
        guard let code = (error as? NFCReaderError)?.code else {
            return error.localizedDescription
        }
        switch code {
        case .readerSessionInvalidationErrorSessionTimeout:
            return L10n.text("Время вышло. Поднесите метку ещё раз.")
        case .readerSessionInvalidationErrorSystemIsBusy:
            return L10n.text("NFC сейчас занят другой функцией iPhone.")
        case .ndefReaderSessionErrorTagNotWritable:
            return L10n.text("Метка закрыта для записи.")
        case .ndefReaderSessionErrorTagSizeTooSmall:
            return L10n.text("На метке не хватает памяти.")
        case .ndefReaderSessionErrorTagUpdateFailure:
            return L10n.text("Записать не удалось. Держите телефон ближе.")
        case .readerErrorRadioDisabled:
            return L10n.text("NFC выключен в настройках iPhone.")
        case .readerErrorSecurityViolation:
            return L10n.text("У приложения нет права на NFC. Проверьте подпись и entitlement.")
        case .readerTransceiveErrorTagConnectionLost, .readerTransceiveErrorTagNotConnected:
            return L10n.text("Метка пропала из поля. Держите телефон ближе.")
        default:
            return error.localizedDescription
        }
    }
}
