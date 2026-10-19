import Contacts
import ContactsUI
import SwiftUI
import UIKit

struct SignalButton: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundStyle(enabled ? Theme.stampText : Theme.mute)
                .background(enabled ? Theme.stamp : Theme.line, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct QuietButton: View {
    var title: String
    var role: QuietRole = .normal
    var action: () -> Void

    enum QuietRole { case normal, destructive }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(role == .destructive ? Theme.signal : Theme.ink)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            }
    }
}

struct FilterChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Theme.stampText : Theme.ink)
                .background(selected ? Theme.stamp : Theme.card, in: Capsule())
                .overlay {
                    Capsule().stroke(selected ? Color.clear : Theme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FieldMark: View {
    var active: Bool = true

    var body: some View {
        let ring = active ? Theme.stampText.opacity(0.9) : Theme.mute
        ZStack {
            Circle().stroke(ring, lineWidth: 2)
            Circle().stroke(ring, lineWidth: 1.5).padding(8)
            Circle().fill(active ? Theme.signal : Theme.mute).frame(width: 8, height: 8)
        }
        .frame(width: 48, height: 48)
    }
}

struct SpecBlock: View {
    var typeName: String
    var manufacturer: String
    var technology: String
    var uid: String
    var status: String

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TagPresentation.label(manufacturer))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.mute)
                    Text(TagPresentation.label(typeName))
                        .font(.system(size: 28, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                specRow(L10n.text("Идентификатор"), uid, mono: true)
                specRow(L10n.text("Интерфейс"), TagPresentation.technology(technology), mono: false)
                specRow("NDEF", status, mono: false)
            }
        }
    }

    private func specRow(_ label: String, _ value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.mute)
            Text(value)
                .font(mono ? .system(size: 15, weight: .medium, design: .monospaced) : .system(size: 16))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
        }
    }
}

struct RecordRow: View {
    var record: StoredRecord
    var onDelete: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    var showsOpen: Bool = false

    @Environment(\.openURL) private var openURL
    @State private var showingContact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.kind.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mute)
                Text(record.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !record.displayDetail.isEmpty {
                    Text(record.displayDetail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsOpen, record.opensContact, record.actionTitle != nil {
                    Button(L10n.text("В Контакты")) { showingContact = true }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 4)
                } else if showsOpen, let actionURL = record.actionURL, let actionTitle = record.actionTitle {
                    Button(actionTitle) { openURL(actionURL) }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mute)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Убрать запись"))
            }
        }
        .modifier(RecordTap(action: onSelect))
        .contextMenu {
            Button(L10n.text("Скопировать")) {
                UIPasteboard.general.string = record.detail.isEmpty ? record.title : "\(record.title)\n\(record.detail)"
            }
        }
        .sheet(isPresented: $showingContact) {
            if let contact = ContactCard.contact(from: record) {
                ContactPreview(contact: contact)
            }
        }
    }
}

private struct RecordTap: ViewModifier {
    var action: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

enum ContactCard {
    static func contact(from record: StoredRecord) -> CNContact? {
        guard record.kind == .contact else { return nil }
        if let parsed = try? CNContactVCardSerialization.contacts(with: record.payload).first {
            return parsed
        }
        let mutable = CNMutableContact()
        let fields = RecordComposer.vcardFields(from: String(data: record.payload, encoding: .utf8) ?? "")
            ?? VCardFields(name: record.title, phone: "", email: "")
        mutable.givenName = fields.name
        if !fields.phone.isEmpty {
            mutable.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: fields.phone))]
        }
        if !fields.email.isEmpty {
            mutable.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: fields.email as NSString)]
        }
        return mutable
    }
}

struct ContactPreview: UIViewControllerRepresentable {
    let contact: CNContact

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forUnknownContact: contact)
        controller.contactStore = CNContactStore()
        controller.allowsEditing = false
        controller.allowsActions = true
        controller.delegate = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak controller] _ in
                controller?.dismiss(animated: true)
            }
        )
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            viewController.dismiss(animated: true)
        }
    }
}

struct TabStrip: View {
    @Binding var section: AppSection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(section == item ? Theme.ink : Theme.mute)
                    .background {
                        if section == item {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.card)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Theme.line, lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .animation(.snappy(duration: 0.2), value: section)
    }
}

struct ScreenTitle: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UndoBanner: View {
    var message: String
    var undo: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.stampText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(L10n.text("Вернуть"), action: undo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.stampText)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.stampText.opacity(0.7))
            }
            .accessibilityLabel(L10n.text("Скрыть"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.stamp, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
