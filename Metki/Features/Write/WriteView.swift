import Contacts
import ContactsUI
import CoreLocation
import CoreNFC
import SwiftUI
import UIKit

struct WriteView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router
    @State private var showingComposer = false
    @State private var editingRecord: StoredRecord?
    @State private var isBusy = false
    @State private var confirmClear = false
    @State private var alertText: String?
    @State private var finishedScan: TagScan?
    @State private var showingResult = false
    @State private var series = false
    @State private var seriesIDs: [String] = []
    @State private var matchesDraft: Bool?
    @State private var namingTemplate = false
    @State private var templateTitle = ""
    @State private var exportFile: ExportFile?

    private var payloadBytes: Int {
        guard !router.drafts.isEmpty else { return 0 }
        return NDEFCodec.encodedLength(of: router.drafts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(
                    title: L10n.text("Запись"),
                    subtitle: L10n.text("Соберите записи и положите их на свою перезаписываемую метку.")
                )
                .padding(.top, 8)

                if router.drafts.isEmpty {
                    PaperCard {
                        Text(L10n.text("Пока пусто. Добавьте текст, ссылку, контакт или сеть Wi‑Fi."))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.mute)
                    }
                } else {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(L10n.text("Попадёт на метку"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.mute)
                                Spacer()
                                Text(L10n.bytes(payloadBytes))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.mute)
                            }
                            ForEach(router.drafts) { record in
                                HStack(alignment: .top, spacing: 8) {
                                    RecordRow(
                                        record: record,
                                        onDelete: {
                                            router.drafts.removeAll { $0.id == record.id }
                                            if router.drafts.isEmpty { router.templateName = nil }
                                        },
                                        onSelect: record.kind == .other ? nil : {
                                            editingRecord = record
                                            showingComposer = true
                                        }
                                    )
                                    if router.drafts.count > 1 {
                                        VStack(spacing: 4) {
                                            Button(L10n.text("Выше")) { move(record, by: -1) }
                                            Button(L10n.text("Ниже")) { move(record, by: 1) }
                                        }
                                        .font(.system(size: 12, weight: .semibold))
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            Text(capacityHint)
                                .font(.system(size: 13))
                                .foregroundStyle(overCapacity ? Theme.signal : Theme.mute)
                        }
                    }
                }

                QuietButton(title: L10n.text("Добавить запись")) {
                    editingRecord = nil
                    showingComposer = true
                }

                if !router.drafts.isEmpty {
                    QuietButton(title: L10n.text("Сохранить как шаблон")) { namingTemplate = true }
                }

                if !library.templates.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.text("Шаблоны"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.mute)
                            ForEach(library.templates) { template in
                                HStack {
                                    Button(template.name) {
                                        router.drafts = template.records
                                        router.templateName = template.name
                                    }
                                    .font(.system(size: 16, weight: .medium))
                                    Spacer()
                                    Button(L10n.text("Поделиться")) {
                                        exportFile = library.exportURL(for: template).map { ExportFile(url: $0) }
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    Button(L10n.text("Удалить шаблон")) { library.deleteTemplate(id: template.id) }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.signal)
                                }
                            }
                        }
                    }
                }

                Toggle(L10n.text("Несколько меток"), isOn: $series)
                    .font(.system(size: 16, weight: .medium))
                    .tint(Theme.stamp)

                SignalButton(
                    title: isBusy ? L10n.text("Держите метку рядом") : L10n.text("Записать на метку"),
                    enabled: !router.drafts.isEmpty && !isBusy && NFCService.isAvailable
                ) {
                    write()
                }

                QuietButton(title: L10n.text("Очистить метку"), role: .destructive) { confirmClear = true }
                    .disabled(!NFCService.isAvailable || isBusy)
                    .opacity(NFCService.isAvailable ? 1 : 0.45)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.paper)
        .sheet(isPresented: $showingComposer, onDismiss: { editingRecord = nil }) {
            ComposerSheet(existing: editingRecord) { record in
                if let index = router.drafts.firstIndex(where: { $0.id == record.id }) {
                    router.drafts[index] = record
                } else {
                    router.drafts.append(record)
                }
            }
        }
        .sheet(isPresented: $showingResult) {
            if let finishedScan {
                ResultSheet(
                    scan: finishedScan,
                    matchesDraft: matchesDraft,
                    seriesCount: seriesIDs.count,
                    onNext: series ? { showingResult = false; write() } : nil
                )
            }
        }
        .confirmationDialog(L10n.text("Очистить NDEF на метке?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L10n.text("Очистить"), role: .destructive) { clear() }
            Button(L10n.text("Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.text("С метки исчезнут текст и ссылки. Сам чип останется, запись можно положить заново."))
        }
        .alert(L10n.text("Не получилось"), isPresented: alertPresented) {
            Button(L10n.text("Хорошо"), role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
        .alert(L10n.text("Имя шаблона"), isPresented: $namingTemplate) {
            TextField(L10n.text("Имя"), text: $templateTitle)
            Button(L10n.text("Сохранить")) {
                let saved = library.saveTemplate(name: templateTitle.isEmpty ? (router.templateName ?? "") : templateTitle, records: router.drafts)
                router.templateName = saved.name
                templateTitle = ""
            }
            Button(L10n.text("Отмена"), role: .cancel) {}
        }
        .sheet(item: $exportFile) { file in
            ActivitySheet(url: file.url)
        }
    }

    private var overCapacity: Bool {
        guard let capacity = router.lastScan?.capacity, capacity > 0 else { return false }
        return payloadBytes > capacity
    }

    private var capacityHint: String {
        var lines: [String] = []
        if let capacity = router.lastScan?.capacity, capacity > 0 {
            if payloadBytes > capacity {
                lines.append(L10n.format("Черновик %@, на последней метке %@.", L10n.bytes(payloadBytes), L10n.bytes(capacity)))
            } else {
                lines.append(L10n.format("Черновик %@ из %@ на последней метке.", L10n.bytes(payloadBytes), L10n.bytes(capacity)))
            }
        }
        if payloadBytes > 144 {
            lines.append(L10n.text("Больше 144 байт: на маленький NTAG213 может не поместиться."))
        } else {
            lines.append(L10n.text("NTAG213 обычно вмещает 144 байта, NTAG215 — 504."))
        }
        return lines.joined(separator: " ")
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })
    }

    private func write() {
        let message = NDEFCodec.message(from: router.drafts)
        let drafts = router.drafts
        let title = router.templateName ?? drafts.first?.title ?? L10n.text("Серия")
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let scan = try await NFCService.shared.write(message)
                matchesDraft = DraftMatch.samePayloads(scan.records, drafts)
                if series {
                    if scan.uid != "—", !seriesIDs.contains(scan.uid) {
                        seriesIDs.append(scan.uid)
                    }
                    library.save(
                        scan: scan,
                        name: title,
                        note: "",
                        preserveName: library.existing(uid: scan.uid) != nil
                    )
                }
                finishedScan = scan
                showingResult = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                alertText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func move(_ record: StoredRecord, by direction: Int) {
        guard let index = router.drafts.firstIndex(where: { $0.id == record.id }) else { return }
        let target = index + direction
        guard router.drafts.indices.contains(target) else { return }
        router.drafts.swapAt(index, target)
    }

    private func clear() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                finishedScan = try await NFCService.shared.clear()
                showingResult = true
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                alertText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct ComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var existing: StoredRecord?
    var onSave: (StoredRecord) -> Void

    @State private var kind: RecordKind = .text
    @State private var primary = ""
    @State private var secondary = ""
    @State private var tertiary = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var security: WiFiSecurity = .wpa2
    @State private var errorText: String?
    @State private var prepared = false
    @State private var showingContacts = false
    @FocusState private var focused: Bool
    @StateObject private var place = PlaceLookup()

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isEditing {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 108), spacing: 8, alignment: .leading)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(RecordKind.writable) { item in
                                FilterChip(title: item.title, selected: kind == item) {
                                    kind = item
                                }
                            }
                        }
                    }
                    fields
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.signal)
                    }
                    SignalButton(title: isEditing ? L10n.text("Сохранить") : L10n.text("Добавить"), action: save)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Закрыть")) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.text("Готово")) { focused = false }
                }
            }
        }
        .presentationDragIndicator(.visible)
            .onAppear(perform: prepare)
            .onChange(of: kind) { _, _ in errorText = nil }
            .sheet(isPresented: $showingContacts) {
                ContactFieldPicker { picked in
                    if kind == .phone {
                        primary = picked.phone
                    } else {
                        primary = picked.name
                        secondary = picked.phone
                        tertiary = picked.email
                    }
                }
            }
        }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .text:
            field(L10n.text("Текст"), text: $primary, axis: .vertical)
        case .url:
            field(L10n.text("Адрес"), text: $primary, prompt: "example.com")
        case .contact:
            field(L10n.text("Имя"), text: $primary, prompt: L10n.text("Имя"))
            field(L10n.text("Телефон"), text: $secondary, prompt: "+7 900 000-00-00", keyboard: .phonePad)
            field(L10n.text("Почта"), text: $tertiary, prompt: "name@mail.com", keyboard: .emailAddress)
            Button(L10n.text("Из Контактов")) { showingContacts = true }
                .font(.system(size: 15, weight: .semibold))
        case .phone:
            field(L10n.text("Номер"), text: $primary, prompt: "+7 900 000-00-00", keyboard: .phonePad)
            Button(L10n.text("Из Контактов")) { showingContacts = true }
                .font(.system(size: 15, weight: .semibold))
        case .email:
            field(L10n.text("Адрес почты"), text: $primary, prompt: "name@mail.com", keyboard: .emailAddress)
        case .sms:
            field(L10n.text("Номер"), text: $primary, prompt: "+7 900 000-00-00", keyboard: .phonePad)
            field(L10n.text("Текст сообщения"), text: $secondary, axis: .vertical)
        case .geo:
            field(L10n.text("Широта"), text: $latitude, prompt: "55.7558", keyboard: .decimalPad)
            field(L10n.text("Долгота"), text: $longitude, prompt: "37.6173", keyboard: .decimalPad)
            Button(place.isBusy ? L10n.text("Ищу место") : L10n.text("Здесь")) { useHere() }
                .font(.system(size: 15, weight: .semibold))
                .disabled(place.isBusy)
        case .wifi:
            field(L10n.text("Имя сети"), text: $primary)
            field(L10n.text("Пароль"), text: $secondary)
            Picker(L10n.text("Защита"), selection: $security) {
                ForEach(WiFiSecurity.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        case .other:
            EmptyView()
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        prompt: String = "",
        axis: Axis = .horizontal,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mute)
            TextField(prompt, text: text, axis: axis)
                .focused($focused)
                .textInputAutocapitalization(shouldNeverCapitalize(title) ? .never : .sentences)
                .autocorrectionDisabled(kind != .text && kind != .sms)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(12)
                .accessibilityLabel(title)
                .frame(minHeight: axis == .vertical ? 88 : 24, alignment: .topLeading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                }
        }
    }

    private func shouldNeverCapitalize(_ title: String) -> Bool {
        kind == .url || kind == .email || (kind == .contact && title == L10n.text("Почта"))
    }

    private func useHere() {
        Task {
            do {
                let location = try await place.request()
                latitude = String(format: "%.6f", location.coordinate.latitude)
                longitude = String(format: "%.6f", location.coordinate.longitude)
                errorText = nil
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? L10n.text("Геолокация выключена.")
            }
        }
    }

    private func prepare() {
        guard !prepared, let existing else { return }
        prepared = true
        kind = existing.kind
        switch existing.kind {
        case .text, .url, .phone, .email:
            primary = existing.title
        case .sms:
            primary = existing.title
            secondary = existing.detail
        case .geo:
            let parts = existing.title.split(separator: ",", maxSplits: 1).map(String.init)
            latitude = parts.first ?? ""
            longitude = parts.count > 1 ? parts[1] : ""
        case .wifi:
            let network = WiFiPayload.fields(from: existing.payload)
            primary = network.ssid ?? existing.title
            secondary = network.password ?? ""
            security = network.security
        case .contact:
            let fields = RecordComposer.vcardFields(from: String(data: existing.payload, encoding: .utf8) ?? "")
            primary = fields?.name ?? existing.title
            secondary = fields?.phone ?? ""
            tertiary = fields?.email ?? ""
        case .other:
            break
        }
    }

    private func save() {
        do {
            let command = try makeCommand()
            var record = NDEFCodec.storedRecord(from: try NDEFCodec.payload(for: command))
            if let existing {
                record.id = existing.id
            }
            onSave(record)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func makeCommand() throws -> ComposeCommand {
        switch kind {
        case .text: return try RecordComposer.text(primary)
        case .url: return try RecordComposer.url(primary)
        case .contact: return try RecordComposer.contact(name: primary, phone: secondary, email: tertiary)
        case .phone: return try RecordComposer.phone(primary)
        case .email: return try RecordComposer.email(primary)
        case .sms: return try RecordComposer.sms(number: primary, body: secondary)
        case .geo: return try RecordComposer.geo(latitude: latitude, longitude: longitude)
        case .wifi: return try RecordComposer.wifi(ssid: primary, password: secondary, security: security)
        case .other: throw ComposerError(L10n.text("Этот тип нельзя собрать вручную."))
        }
    }
}

final class PlaceLookup: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isBusy = false
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var didAskLocation = false

    func request() async throws -> CLLocation {
        manager.delegate = self
        isBusy = true
        do {
            let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                self.continuation = continuation
                self.didAskLocation = false
                let status = manager.authorizationStatus
                if status == .denied || status == .restricted {
                    self.continuation = nil
                    continuation.resume(throwing: ComposerError(L10n.text("Геолокация выключена.")))
                    return
                }
                if status == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                } else {
                    askLocation()
                }
            }
            isBusy = false
            return location
        } catch {
            isBusy = false
            throw error
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            askLocation()
        case .denied, .restricted:
            continuation?.resume(throwing: ComposerError(L10n.text("Геолокация выключена.")))
            continuation = nil
        default:
            break
        }
    }

    private func askLocation() {
        guard continuation != nil, !didAskLocation else { return }
        didAskLocation = true
        manager.requestLocation()
    }
}

struct ContactChoice {
    var name: String
    var phone: String
    var email: String
}

struct ContactFieldPicker: UIViewControllerRepresentable {
    var onPick: (ContactChoice) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: (ContactChoice) -> Void
        init(onPick: @escaping (ContactChoice) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            let email = contact.emailAddresses.first?.value as String? ?? ""
            onPick(ContactChoice(name: name, phone: phone, email: email))
        }
    }
}
