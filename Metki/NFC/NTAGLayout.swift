import Foundation

struct NTAGPages: Equatable {
    var auth0: UInt8
    var access: UInt8
    var pwd: UInt8
    var pack: UInt8
}

enum NTAGLayout {
    static func modelName(version data: Data) -> String? {
        guard let storage = storageSize(version: data) else { return nil }
        switch storage {
        case 0x0F: return "NTAG213"
        case 0x11: return "NTAG215"
        case 0x13: return "NTAG216"
        default: return nil
        }
    }

    static func pages(version data: Data) -> NTAGPages? {
        guard let storage = storageSize(version: data) else { return nil }
        return pages(storageSize: storage)
    }

    static func pages(storageSize: UInt8) -> NTAGPages? {
        switch storageSize {
        case 0x0F:
            return NTAGPages(auth0: 0x29, access: 0x2A, pwd: 0x2B, pack: 0x2C)
        case 0x11:
            return NTAGPages(auth0: 0x83, access: 0x84, pwd: 0x85, pack: 0x86)
        case 0x13:
            return NTAGPages(auth0: 0xE3, access: 0xE4, pwd: 0xE5, pack: 0xE6)
        default:
            return nil
        }
    }

    private static func storageSize(version data: Data) -> UInt8? {
        if data.count >= 8, data[0] == 0x00, data[1] == 0x04, data[2] == 0x04 {
            return data[6]
        }
        if data.count >= 7, data[0] == 0x04, data[1] == 0x04 {
            return data[5]
        }
        return nil
    }
}

enum UltralightCommand {
    static let getVersion = Data([0x60])

    static func read(page: UInt8) -> Data {
        Data([0x30, page])
    }

    static func write(page: UInt8, block: Data) -> Data {
        Data([0xA2, page]) + block.prefix(4)
    }

    static func pwdAuth(_ password: Data) -> Data {
        Data([0x1B]) + password.prefix(4)
    }
}
