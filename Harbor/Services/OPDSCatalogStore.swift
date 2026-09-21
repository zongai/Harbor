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

    @discardableResult
    func add(title: String, url: String, username: String? = nil, password: String? = nil) -> String? {
        guard let normalized = NetworkURLPolicy.validateOPDS(url) else {
            return "OPDS 地址无效。请填写可访问的 http(s) 地址（可省略 https://）"
        }
        let trimmed = normalized.absoluteString
        if catalogs.contains(where: { $0.url == trimmed }) {
            return "该书库已添加"
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = OPDSCatalog(
            title: name.isEmpty ? (normalized.host ?? "OPDS") : name,
            url: trimmed,
            username: (user?.isEmpty == false) ? user : nil
        )
        OPDSCredentialStore.savePassword(password, catalogID: catalog.id)
        catalogs.insert(catalog, at: 0)
        save()
        return nil
    }

    func updateCredentials(id: UUID, username: String?, password: String?) {
        guard let i = catalogs.firstIndex(where: { $0.id == id }) else { return }
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogs[i].username = (user?.isEmpty == false) ? user : nil
        OPDSCredentialStore.savePassword(password, catalogID: id)
        save()
    }

    func remove(id: UUID) {
        OPDSCredentialStore.delete(catalogID: id)
        catalogs.removeAll { $0.id == id }
        save()
    }

    func credentials(for catalog: OPDSCatalog) -> (String?, String?) {
        (catalog.username, OPDSCredentialStore.password(catalogID: catalog.id))
    }

    func rename(id: UUID, title: String) {
        guard let i = catalogs.firstIndex(where: { $0.id == id }) else { return }
        catalogs[i].title = title
        save()
    }
}
