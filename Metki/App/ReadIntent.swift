import AppIntents
import Foundation

extension Notification.Name {
    static let metkiReadTag = Notification.Name("metki.readTag")
}

enum LaunchAction {
    private(set) static var pendingRead = false

    static func requestRead() {
        pendingRead = true
        NotificationCenter.default.post(name: .metkiReadTag, object: nil)
    }

    static func takeRead() -> Bool {
        let value = pendingRead
        pendingRead = false
        return value
    }
}

struct ReadTagIntent: AppIntent {
    static var title: LocalizedStringResource = "Считать метку"
    static var description = IntentDescription("Открывает Метки и начинает чтение. Запись не запускается.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            LaunchAction.requestRead()
        }
        return .result()
    }
}

struct MetkiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadTagIntent(),
            phrases: ["Считать метку в \(.applicationName)"],
            shortTitle: "Считать метку",
            systemImageName: "wave.3.right"
        )
    }
}
