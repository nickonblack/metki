import SwiftUI

@MainActor
final class Router: ObservableObject {
    @Published var section: AppSection = .read
    @Published var drafts: [StoredRecord] = []
    @Published var templateName: String?
    @Published var lastScan: TagScan?
    @Published var pendingRead = false
    @Published var libraryTag: UUID?

    func open(_ url: URL) {
        guard url.scheme == "metki" else { return }
        if url.host == "read" {
            section = .read
            pendingRead = true
        } else if url.host == "tag" {
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let id = UUID(uuidString: raw) {
                section = .library
                libraryTag = id
            }
        }
    }

    func consumeLaunch() {
        if LaunchAction.takeRead() {
            section = .read
            pendingRead = true
        }
    }
}
