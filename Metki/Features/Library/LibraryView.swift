import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router
    @State private var path = NavigationPath()
    @State private var importing = false
    @State private var exportFile: ExportFile?
    @State private var notice: String?
    @State private var showingExport = false
    @State private var showingShelves = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.tags.isEmpty {
                    empty
                } else {
                    filled
                }
            }
            .background(Theme.paper)
            .searchable(text: $library.search, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.text("Имя, номер или текст"))
            .navigationTitle(L10n.text("Библиотека"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel(L10n.text("Импорт"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShelves = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(L10n.text("Полки"))
                }
                if !library.tags.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.text("Экспорт"))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                TagDetailView(tagID: id)
            }
            .onAppear(perform: openPending)
            .onChange(of: router.libraryTag) { _, _ in openPending() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    notice = try library.importFile(at: url).message
                } catch {
                    notice = (error as? LocalizedError)?.errorDescription ?? L10n.text("Не удалось импортировать.")
                }
            case .failure:
                notice = L10n.text("Не удалось открыть файл.")
            }
        }
        .sheet(item: $exportFile) { file in
            ActivitySheet(url: file.url)
        }
        .sheet(isPresented: $showingShelves) {
            ShelfEditor()
        }
        .confirmationDialog(L10n.text("Экспорт"), isPresented: $showingExport, titleVisibility: .visible) {
            Button("JSON") { shareExport(redactWiFi: false, zip: false) }
            Button(L10n.text("JSON без паролей Wi‑Fi")) { shareExport(redactWiFi: true, zip: false) }
            Button(L10n.text("Архив с фото")) { shareExport(redactWiFi: false, zip: true) }
            Button(L10n.text("Отмена"), role: .cancel) {}
        } message: {
            Text(library.hasPhotos ? L10n.text("Обычный JSON не включает фото.") : L10n.text("Файл библиотеки."))
        }
        .alert(L10n.text("Библиотека"), isPresented: noticePresented) {
            Button(L10n.text("Хорошо"), role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func shareExport(redactWiFi: Bool, zip: Bool) {
        if zip {
            exportFile = library.makePhotoArchiveURL().map { ExportFile(url: $0) }
        } else {
            exportFile = library.makeExportURL(redactWiFi: redactWiFi).map { ExportFile(url: $0) }
        }
    }

    private func openPending() {
        guard let id = router.libraryTag else { return }
        router.libraryTag = nil
        path.append(id)
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenTitle(
                title: L10n.text("Пока пусто"),
                subtitle: L10n.text("Считанная метка появится здесь: имя, полка и то, что на ней записано.")
            )
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filled: some View {
        VStack(spacing: 0) {
            filterBar
            if library.visibleTags.isEmpty {
                Text(L10n.text("Ничего не найдено"))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.mute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            } else {
                tagList
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: L10n.text("Все"), selected: library.scope == .all) {
                        library.scope = .all
                    }
                    FilterChip(title: L10n.text("Закреплённые"), selected: library.scope == .pinned) {
                        library.scope = .pinned
                    }
                    ForEach(ShelfCatalog.filterOrder(library.shelves)) { shelf in
                        FilterChip(title: shelf.displayName, selected: library.scope == .shelf(shelf.id)) {
                            library.scope = .shelf(shelf.id)
                        }
                    }
                }
            }
            Menu {
                ForEach(LibrarySort.allCases) { item in
                    Button(item.title) { library.sort = item }
                }
            } label: {
                Text(library.sort.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.card, in: Capsule())
                    .overlay { Capsule().stroke(Theme.line, lineWidth: 1) }
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var tagList: some View {
        List {
            ForEach(library.visibleTags) { tag in
                NavigationLink(value: tag.id) {
                    LibraryRow(tag: tag, shelfName: library.shelfName(id: tag.shelfId))
                }
                .listRowBackground(Theme.card)
                .listRowSeparatorTint(Theme.line)
                .swipeActions(edge: .leading) {
                    Button {
                        library.togglePin(id: tag.id)
                    } label: {
                        Label(tag.pinned ? L10n.text("Открепить") : L10n.text("Закрепить"), systemImage: "pin")
                    }
                    .tint(Theme.stamp)
                }
            }
            .onDelete { offsets in
                library.delete(offsets: offsets, in: library.visibleTags)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct LibraryRow: View {
    var tag: TagRecord
    var shelfName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tag.name)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                if tag.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mute)
                }
            }
            Text(meta)
                .font(.system(size: 13))
                .foregroundStyle(Theme.mute)
            Text(tag.preview)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink.opacity(0.82))
                .lineLimit(1)
        }
        .padding(.vertical, 6)
    }

    private var meta: String {
        let shelf = shelfName == Shelf.inbox.title ? tag.typeName : "\(shelfName) · \(tag.typeName)"
        return "\(shelf) · \(tag.scannedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct ShelfEditor: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L10n.text("Новая полка"), text: $name)
                        .accessibilityLabel(L10n.text("Новая полка"))
                    Button(L10n.text("Добавить")) {
                        if library.addShelf(name: name) != nil {
                            name = ""
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    ForEach(library.shelves) { shelf in
                        if shelf.isInbox {
                            Text(shelf.displayName)
                        } else {
                            TextField(L10n.text("Название"), text: binding(shelf))
                        }
                    }
            .onDelete { offsets in
                let ids = offsets.compactMap { library.shelves.indices.contains($0) ? library.shelves[$0].id : nil }
                ids.forEach { library.deleteShelf(id: $0) }
            }
                }
            }
            .navigationTitle(L10n.text("Полки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Закрыть")) { dismiss() }
                }
            }
        }
    }

    private func binding(_ shelf: ShelfDefinition) -> Binding<String> {
        Binding(
            get: { library.shelves.first { $0.id == shelf.id }?.displayName ?? shelf.displayName },
            set: { library.renameShelf(id: shelf.id, name: $0) }
        )
    }
}
