import SwiftUI

enum Theme {
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let ink = Color("Ink")
    static let mute = Color("Mute")
    static let line = Color("Line")
    static let signal = Color("Signal")
    static let stamp = Color("Stamp")
    static let stampText = Color("StampText")
}

enum AppSection: String, CaseIterable, Identifiable {
    case read
    case write
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return L10n.text("Чтение")
        case .write: return L10n.text("Запись")
        case .library: return L10n.text("Библиотека")
        }
    }

    var symbol: String {
        switch self {
        case .read: return "wave.3.right"
        case .write: return "square.and.pencil"
        case .library: return "square.stack"
        }
    }
}
