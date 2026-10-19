import PhotosUI
import SwiftUI
import UIKit

struct TagDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    let tagID: UUID
    @State private var name = ""
    @State private var note = ""
    @State private var prepared = false
    @State private var acceptEdits = false
    @State private var confirmDelete = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var inspecting: StoredRecord?
    @State private var exportFile: ExportFile?
    @State private var password = ""
    @State private var pack = ""
    @State private var protectError: String?
    @State private var confirmLock = false
    @State private var confirmLockFinal = false
    @State private var isBusy = false

    private var tag: TagRecord? { library.tag(id: tagID) }

    var body: some View {
        Group {
            if let tag {
                content(tag)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(Theme.paper)
        .navigationTitle(name.isEmpty ? L10n.text("Метка") : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.paper, for: .navigationBar)
        .toolbar {
            if let tag {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        library.togglePin(id: tag.id)
                    } label: {
                        Image(systemName: tag.pinned ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(tag.pinned ? L10n.text("Открепить") : L10n.text("Закрепить"))
                }
            }
        }
        .confirmationDialog(L10n.text("Удалить карточку из библиотеки?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.text("Удалить"), role: .destructive) {
                library.delete(id: tagID)
                dismiss()
            }
            Button(L10n.text("Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.text("Сама метка не изменится. Карточку можно вернуть."))
        }
        .confirmationDialog(L10n.text("Закрыть метку навсегда?"), isPresented: $confirmLock, titleVisibility: .visible) {
            Button(L10n.text("Продолжить")) { confirmLockFinal = true }
            Button(L10n.text("Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.text("После этого записать на неё уже нельзя. Сам чип останется."))
        }
        .confirmationDialog(L10n.text("Это нельзя отменить"), isPresented: $confirmLockFinal, titleVisibility: .visible) {
            Button(L10n.text("Закрыть навсегда"), role: .destructive) { lock() }
            Button(L10n.text("Отмена"), role: .cancel) {}
        } message: {
            Text(L10n.text("Метка останется только для чтения."))
        }
        .sheet(item: $inspecting) { record in
            RecordInspector(record: record)
        }
        .sheet(item: $exportFile) { file in
            ActivitySheet(url: file.url)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { data in
                library.setPhoto(id: tagID, data: data)
            }
        }
        .alert(L10n.text("Не получилось"), isPresented: protectPresented) {
            Button(L10n.text("Хорошо"), role: .cancel) {}
        } message: {
            Text(protectError ?? "")
        }
    }

    private func content(_ tag: TagRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SpecBlock(
                    typeName: tag.typeName,
                    manufacturer: tag.manufacturer,
                    technology: tag.technology,
                    uid: tag.uid,
                    status: tag.statusLine
                )
                photo(tag)
                if tag.nameConflict, !tag.alternateName.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("На другом устройстве имя «%@».", tag.alternateName))
                                .font(.system(size: 15))
                            Button(L10n.text("Взять это имя")) { library.useAlternateName(id: tag.id) }
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        editor(L10n.text("Имя"), text: $name)
                        editor(L10n.text("Заметка"), text: $note)
                        Text(L10n.text("Заметка и полка хранятся в телефоне и на метку не пишутся."))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.mute)
                        Text(L10n.text("Полка"))
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.mute)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ShelfCatalog.filterOrder(library.shelves)) { shelf in
                                    FilterChip(title: shelf.displayName, selected: tag.shelfId == shelf.id) {
                                        library.setShelf(id: tag.id, shelfId: shelf.id)
                                    }
                                }
                            }
                        }
                    }
                }
                if !tag.records.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(L10n.text("Записи"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.mute)
                            ForEach(tag.records) { record in
                                RecordRow(record: record, showsOpen: true)
                                if record.kind == .other {
                                    Button(L10n.text("Разобрать запись")) { inspecting = record }
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                    }
                    SignalButton(title: L10n.text("Записать на другую метку")) {
                        router.drafts = tag.records
                        router.templateName = tag.name
                        router.section = .write
                    }
                }
                if !tag.scans.isEmpty {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.text("Прошлые чтения"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.mute)
                            ForEach(tag.scans.reversed()) { snapshot in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snapshot.scannedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(snapshot.records.first?.title ?? snapshot.ndefStatus.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.mute)
                                }
                            }
                        }
                    }
                }
                if canProtect(tag) {
                    passwordCard
                }
                QuietButton(title: L10n.text("Сделать шаблон")) {
                    library.saveTemplate(name: name.isEmpty ? tag.name : name, records: tag.records)
                }
                .disabled(tag.records.isEmpty)
                QuietButton(title: L10n.text("Поделиться карточкой")) {
                    exportFile = library.exportURL(for: tag, redactWiFi: false).map { ExportFile(url: $0) }
                }
                QuietButton(title: L10n.text("Скопировать карточку")) {
                    UIPasteboard.general.string = tag.summary(shelfName: library.shelfName(id: tag.shelfId))
                }
                QuietButton(title: L10n.text("Закрыть метку навсегда"), role: .destructive) {
                    confirmLock = true
                }
                .disabled(!NFCService.isAvailable || isBusy || tag.ndefStatus == .readOnly)
                QuietButton(title: L10n.text("Удалить из библиотеки"), role: .destructive) {
                    confirmDelete = true
                }
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            name = tag.name
            note = tag.note
            acceptEdits = true
        }
        .onDisappear {
            guard acceptEdits else { return }
            library.update(id: tagID, name: name, note: note)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    library.setPhoto(id: tagID, data: data)
                }
                photoItem = nil
            }
        }
    }

    private var protectPresented: Binding<Bool> {
        Binding(get: { protectError != nil }, set: { if !$0 { protectError = nil } })
    }

    private func photo(_ tag: TagRecord) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Предмет"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mute)
                if let name = tag.photoFile,
                   let image = UIImage(contentsOfFile: PhotoStore.fileURL(named: name, in: library.folder).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(L10n.text("Фото предмета"))
                }
                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(L10n.text("Выбрать фото"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel(L10n.text("Фото предмета"))
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(L10n.text("Снять")) { showingCamera = true }
                            .font(.system(size: 15, weight: .semibold))
                    }
                    if tag.photoFile != nil {
                        Button(L10n.text("Убрать фото")) { library.removePhoto(id: tag.id) }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.signal)
                    }
                }
            }
        }
    }

    private var passwordCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Пароль метки"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mute)
                Text(L10n.text("4 символа и код PACK из 2 символов. Он хранится в связке ключей, не в библиотеке."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mute)
                TextField(L10n.text("Пароль"), text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(L10n.text("Пароль метки"))
                TextField("PACK", text: $pack)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(L10n.text("Код PACK"))
                Button(L10n.text("Поставить пароль")) { protect() }
                    .disabled(!NFCService.isAvailable || isBusy)
                Button(L10n.text("Снять пароль")) { unprotect() }
                    .disabled(!NFCService.isAvailable || isBusy)
            }
            .font(.system(size: 15, weight: .semibold))
        }
    }

    private func canProtect(_ tag: TagRecord) -> Bool {
        let name = tag.typeName.lowercased()
        return name.contains("ntag") || name.contains("ultralight")
    }

    private func protect() {
        let passwordData = Data(password.utf8)
        let packData = Data(pack.utf8)
        guard passwordData.count == 4, packData.count == 2 else {
            protectError = L10n.text("Пароль — 4 символа, код PACK — 2.")
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let scan = try await NFCService.shared.protect(password: passwordData, pack: packData)
                library.save(scan: scan, name: name, note: note, preserveName: true, keepRecordsIfEmpty: true)
                password = ""
                pack = ""
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                protectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func unprotect() {
        let secret = Data(password.utf8)
        guard secret.count == 4 else {
            protectError = L10n.text("Пароль — 4 символа.")
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let scan = try await NFCService.shared.unprotect(password: secret)
                library.save(scan: scan, name: name, note: note, preserveName: true, keepRecordsIfEmpty: true)
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                protectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func lock() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let scan = try await NFCService.shared.lockTag()
                library.save(scan: scan, name: name, note: note, preserveName: true, keepRecordsIfEmpty: true)
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                protectError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func editor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mute)
            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .accessibilityLabel(title)
        }
    }
}

struct RecordInspector: View {
    var record: StoredRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    line(L10n.text("Формат"), Hex.typeNameFormatTitle(record.typeNameFormat))
                    line(L10n.text("Тип"), record.type.isEmpty ? "—" : (String(data: record.type, encoding: .utf8) ?? Hex.full(record.type)))
                    line(L10n.text("Идентификатор"), Hex.full(record.identifier))
                    line(L10n.text("Данные"), Hex.full(record.payload))
                    QuietButton(title: L10n.text("Скопировать hex")) {
                        UIPasteboard.general.string = Hex.full(record.payload)
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle(L10n.text("record.generic"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mute)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (Data) -> Void
        var dismiss: DismissAction

        init(onImage: @escaping (Data) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.82) {
                onImage(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
