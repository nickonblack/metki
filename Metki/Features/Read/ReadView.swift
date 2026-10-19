import SwiftUI
import UIKit

struct ReadView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router
    @State private var isBusy = false
    @State private var showingResult = false
    @State private var alertText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenTitle(
                        title: L10n.text("Метки"),
                        subtitle: L10n.text("Считайте свою метку, оставьте карточку и при желании запишите на неё текст или ссылку.")
                    )
                    .padding(.top, 8)

                    scanCard

                    if !NFCService.isAvailable {
                        PaperCard {
                            Text(L10n.text("На этом устройстве NFC недоступен. Библиотека работает, а считывание — на iPhone 7 и новее."))
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                        }
                    }

                    if let lastScan = router.lastScan {
                        Button {
                            showingResult = true
                        } label: {
                            PaperCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.text("Последнее чтение"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.mute)
                                    Text(lastScan.identity.typeName)
                                        .font(.system(size: 22, weight: .medium, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                    Text(lastScan.uid)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.mute)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if library.tags.isEmpty {
                        steps
                    } else {
                        recent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                TagDetailView(tagID: id)
            }
        }
        .sheet(isPresented: $showingResult) {
            if let lastScan = router.lastScan {
                ResultSheet(scan: lastScan)
            }
        }
        .alert(L10n.text("Не получилось"), isPresented: alertPresented) {
            Button(L10n.text("Хорошо"), role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
        .onAppear {
            if router.pendingRead {
                router.pendingRead = false
                if NFCService.isAvailable { scan() }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedScan"), !DebugLibrary.didSeedScan {
                DebugLibrary.didSeedScan = true
                router.lastScan = DebugLibrary.sampleScan()
            }
            #endif
        }
        .onChange(of: router.pendingRead) { _, pending in
            guard pending else { return }
            router.pendingRead = false
            if NFCService.isAvailable { scan() }
        }
    }

    private var scanCard: some View {
        Button(action: scan) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Считать метку"))
                        .font(.system(size: 22, weight: .semibold))
                    Text(isBusy ? L10n.text("Держите метку рядом") : L10n.text("Верх iPhone — к метке"))
                        .font(.system(size: 14))
                        .foregroundStyle(canScan ? Theme.stampText.opacity(0.72) : Theme.mute)
                }
                Spacer(minLength: 0)
                FieldMark(active: canScan)
            }
            .padding(18)
            .foregroundStyle(canScan ? Theme.stampText : Theme.ink)
            .background(canScan ? Theme.stamp : Theme.line, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canScan)
        .accessibilityLabel(L10n.text("Считать метку"))
    }

    private var steps: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Как пользоваться"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mute)
                step("1", L10n.text("Поднесите метку и посмотрите, что на ней"))
                step("2", L10n.text("Дайте карточке имя и полку"))
                step("3", L10n.text("Запишите свой текст, ссылку или Wi‑Fi"))
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Недавние"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.mute)
            ForEach(library.recentTags) { tag in
                NavigationLink(value: tag.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tag.name)
                                .font(.system(size: 18, weight: .medium, design: .serif))
                                .foregroundStyle(Theme.ink)
                            Text(tag.preview)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.mute)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if tag.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.mute)
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func step(_ index: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(index)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.mute)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
        }
    }

    private var canScan: Bool { !isBusy && NFCService.isAvailable }

    private var alertPresented: Binding<Bool> {
        Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })
    }

    private func scan() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let scan = try await NFCService.shared.read()
                router.lastScan = scan
                showingResult = true
            } catch NFCFailure.cancelled, NFCFailure.surfaced {
                return
            } catch {
                alertText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct ResultSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    let scan: TagScan
    var matchesDraft: Bool? = nil
    var seriesCount: Int = 0
    var onNext: (() -> Void)? = nil
    @State private var name = ""
    @State private var note = ""
    @State private var prepared = false
    @State private var updating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SpecBlock(
                        typeName: scan.identity.typeName,
                        manufacturer: scan.identity.manufacturer,
                        technology: scan.identity.technology,
                        uid: scan.uid,
                        status: scan.statusLine
                    )
                    if let change {
                        Text(change.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(change == .same ? Theme.mute : Theme.signal)
                    }
                    if let matchesDraft {
                        Text(matchesDraft ? L10n.text("Запись совпала с черновиком.") : L10n.text("Запись на метке отличается от черновика."))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(matchesDraft ? Theme.mute : Theme.signal)
                    }
                    if seriesCount > 0 {
                        Text(L10n.format("В серии %lld", seriesCount))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.mute)
                    }
                    records
                    fields
                    SignalButton(title: updating ? L10n.text("Обновить в библиотеке") : L10n.text("Сохранить в библиотеку")) {
                        library.save(scan: scan, name: name, note: note)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    if !scan.records.isEmpty {
                        QuietButton(title: L10n.text("В черновик")) {
                            router.drafts = scan.records
                            router.section = .write
                            dismiss()
                        }
                    }
                    if let onNext {
                        QuietButton(title: L10n.text("Следующая метка"), action: onNext)
                    }
                    QuietButton(title: L10n.text("Закрыть без сохранения")) { dismiss() }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle(L10n.text("Метка"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Скопировать UID")) { UIPasteboard.general.string = scan.uid }
                        .disabled(scan.uid == "—")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: prepare)
    }

    @ViewBuilder
    private var records: some View {
        if scan.records.isEmpty {
            PaperCard {
                Text(L10n.text("На метке нет NDEF-записей. Её всё равно можно сохранить как карточку."))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.mute)
            }
        } else {
            PaperCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("Записи"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.mute)
                    ForEach(scan.records) { record in
                        RecordRow(record: record)
                    }
                }
            }
        }
    }

    private var fields: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                labeledField(L10n.text("Имя"), text: $name, prompt: L10n.text("Офис, дом, коробка"))
                labeledField(L10n.text("Заметка"), text: $note, prompt: L10n.text("Где лежит. На метку не пишется"))
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mute)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let existing = library.existing(uid: scan.uid) {
            name = existing.name
            note = existing.note
            updating = true
        } else {
            name = scan.suggestedName
        }
    }

    private var change: ScanChange? {
        guard let card = library.existing(uid: scan.uid) else { return nil }
        return ScanDiff.compare(card: card, scan: scan)
    }
}
