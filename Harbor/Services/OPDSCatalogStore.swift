import Foundation
import Observation

/// 用户添加的 OPDS 书库列表（与 BookLibrary 分离）
@Observable
@MainActor
final class OPDSCatalogStore {
    private(set) var catalogs: [OPDSCatalog] = []

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Harbor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("opds_catalogs.json")
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([OPDSCatalog].self, from: data) else {
            catalogs = []
            return
        }
        catalogs = list.sorted { $0.addedAt > $1.addedAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(catalogs) {
            try? data.write(to: Self.fileURL, options: [.atomic])
        }
    }

    func add(title: String, url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NetworkURLPolicy.validate(trimmed) != nil else { return }
        if catalogs.contains(where: { $0.url == trimmed }) { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogs.insert(OPDSCatalog(title: name.isEmpty ? (URL(string: trimmed)?.host ?? "OPDS") : name, url: trimmed), at: 0)
        save()
    }

    func remove(id: UUID) {
        catalogs.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, title: String) {
        guard let i = catalogs.firstIndex(where: { $0.id == id }) else { return }
        catalogs[i].title = title
        save()
    }
}
