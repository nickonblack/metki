import SwiftUI

@main
struct MetkiApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(router)
                .tint(Theme.ink)
                .onOpenURL { url in
                    router.open(url)
                }
                .onAppear {
                    router.consumeLaunch()
                    library.refreshFromCloud()
                }
                .onReceive(NotificationCenter.default.publisher(for: .metkiReadTag)) { _ in
                    router.consumeLaunch()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            Group {
                switch router.section {
                case .read:
                    ReadView()
                case .write:
                    WriteView()
                case .library:
                    LibraryView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let message = library.undoMessage {
                    UndoBanner(message: message, undo: library.undoDelete, dismiss: library.dismissUndo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TabStrip(section: $router.section)
            }
            .animation(.snappy(duration: 0.2), value: library.undoMessage)
        }
    }
}
