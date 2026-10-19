import SwiftUI
import WidgetKit

struct WidgetCard: Decodable, Identifiable {
    var id: UUID
    var name: String
    var shelf: String
    var kind: String
    var shelfKey: String?
    var kindKey: String?
}

struct PinnedEntry: TimelineEntry {
    var date: Date
    var cards: [WidgetCard]
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: Date(), cards: [WidgetCard(id: UUID(), name: L10n.text("Кухня"), shelf: L10n.text("Дом"), kind: L10n.text("Ссылка"), shelfKey: "Дом", kindKey: "Ссылка")])
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        completion(PinnedEntry(date: Date(), cards: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        let entry = PinnedEntry(date: Date(), cards: load())
        let next = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> [WidgetCard] {
        guard let folder = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.metki.reader")?
            .appendingPathComponent("Library", isDirectory: true) else { return [] }
        let url = folder.appendingPathComponent("pinned.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetCard].self, from: data)) ?? []
    }
}

struct MetkiWidgetView: View {
    var entry: PinnedEntry

    var body: some View {
        if entry.cards.isEmpty {
            Text("Нет закреплённых")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.cards.prefix(3)) { card in
                    Link(destination: URL(string: "metki://tag/\(card.id.uuidString)")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(.headline)
                            Text("\(card.shelfKey.map(L10n.text) ?? card.shelf) · \(card.kindKey.map(L10n.text) ?? card.kind)")
                                .font(.caption)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }
}

struct MetkiPinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetkiPinned", provider: PinnedProvider()) { entry in
            MetkiWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Закреплённые")
        .description("Имя, полка и тип записи. Нажатие открывает карточку.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MetkiWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetkiPinnedWidget()
    }
}
