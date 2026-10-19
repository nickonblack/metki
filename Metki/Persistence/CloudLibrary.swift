import Foundation

enum CloudLibrary {
    static func folder() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: AppStorage.cloudID) else { return nil }
        let folder = base.appendingPathComponent("Documents/Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func pull(
        tags: [TagRecord],
        shelves: [ShelfDefinition],
        templates: [WriteTemplate],
        localFolder: URL
    ) -> (tags: [TagRecord], shelves: [ShelfDefinition], templates: [WriteTemplate]) {
        guard let cloud = folder() else { return (tags, shelves, templates) }
        let remoteTags = readTags(cloud.appendingPathComponent("tags.json"))
        let remoteTemplates = TemplateCodec.load(from: cloud.appendingPathComponent("templates.json"))
        let remoteShelves = remoteTags.shelves
        let mergedTags = remoteTags.tags.isEmpty && !FileManager.default.fileExists(atPath: cloud.appendingPathComponent("tags.json").path)
            ? tags
            : LibraryMerge.tags(local: tags, remote: remoteTags.tags)
        let mergedShelves = LibraryMerge.shelves(local: shelves, remote: remoteShelves)
        let mergedTemplates = LibraryMerge.templates(local: templates, remote: remoteTemplates)
        let names = mergedTags.compactMap(\.photoFile)
        copyMissingPhotos(from: cloud, to: localFolder, names: names)
        return (mergedTags, mergedShelves, mergedTemplates)
    }

    static func push(from localFolder: URL) {
        guard let cloud = folder() else { return }
        for name in ["tags.json", "templates.json", "pinned.json"] {
            copy(localFolder.appendingPathComponent(name), to: cloud.appendingPathComponent(name))
        }
        let photos = localFolder.appendingPathComponent("photos", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: photos, includingPropertiesForKeys: nil) else { return }
        let destination = cloud.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "jpg" {
            copy(file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
    }

    private static func readTags(_ url: URL) -> (tags: [TagRecord], shelves: [ShelfDefinition]) {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? TagCodec.decode(data) else {
            return ([], [])
        }
        return (decoded.tags, decoded.shelves)
    }

    private static func copyMissingPhotos(from cloud: URL, to local: URL, names: [String]) {
        for name in names {
            let source = cloud.appendingPathComponent("photos", isDirectory: true).appendingPathComponent(name)
            let destination = PhotoStore.fileURL(named: name, in: local)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func copy(_ source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}
