import Foundation

struct RecordSignature: Equatable {
    var format: UInt8
    var type: Data
    var identifier: Data
    var payload: Data
}

enum RecordIdentity {
    static func signature(_ record: StoredRecord) -> RecordSignature {
        RecordSignature(
            format: record.typeNameFormat,
            type: record.type,
            identifier: record.identifier,
            payload: record.payload
        )
    }

    static func same(_ lhs: [StoredRecord], _ rhs: [StoredRecord]) -> Bool {
        lhs.map(signature) == rhs.map(signature)
    }
}

enum ScanChange: Equatable {
    case same
    case emptied
    case locked
    case changed(added: Int, removed: Int, modified: Int)

    var title: String {
        switch self {
        case .same:
            return L10n.text("Совпадает с карточкой")
        case .emptied:
            return L10n.text("На метке больше нет записей")
        case .locked:
            return L10n.text("Метка закрыта для записи")
        case .changed(let added, let removed, let modified):
            return L10n.format("Изменилось: +%lld, −%lld, других %lld", added, removed, modified)
        }
    }
}

enum ScanDiff {
    static func compare(card: TagRecord, scan: TagScan) -> ScanChange {
        let contentSame = RecordIdentity.same(card.records, scan.records)
        if !card.records.isEmpty && scan.records.isEmpty {
            return .emptied
        }
        if scan.ndefStatus == .readOnly && card.ndefStatus != .readOnly && contentSame {
            return .locked
        }
        if contentSame {
            return .same
        }
        let delta = delta(from: card.records, to: scan.records)
        return .changed(added: delta.added, removed: delta.removed, modified: delta.modified)
    }

    static func delta(from old: [StoredRecord], to new: [StoredRecord]) -> (added: Int, removed: Int, modified: Int) {
        let oldSignatures = old.map(RecordIdentity.signature)
        let newSignatures = new.map(RecordIdentity.signature)
        var oldIndex = 0
        var newIndex = 0
        var added = 0
        var removed = 0
        var modified = 0
        while oldIndex < oldSignatures.count && newIndex < newSignatures.count {
            if oldSignatures[oldIndex] == newSignatures[newIndex] {
                oldIndex += 1
                newIndex += 1
                continue
            }
            let sameSlot = oldSignatures[oldIndex].format == newSignatures[newIndex].format
                && oldSignatures[oldIndex].type == newSignatures[newIndex].type
            if sameSlot {
                modified += 1
                oldIndex += 1
                newIndex += 1
                continue
            }
            if !newSignatures[newIndex...].contains(oldSignatures[oldIndex]) {
                removed += 1
                oldIndex += 1
            } else {
                added += 1
                newIndex += 1
            }
        }
        removed += oldSignatures.count - oldIndex
        added += newSignatures.count - newIndex
        return (added, removed, modified)
    }
}

enum DraftMatch {
    static func samePayloads(_ written: [StoredRecord], _ draft: [StoredRecord]) -> Bool {
        written.map(\.payload) == draft.map(\.payload)
    }
}
