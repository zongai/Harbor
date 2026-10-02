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
            return "OPDS 地址无效。请使用 http:// 或 https:// 地址（明文 HTTP 已允许）"
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

    /// 导出书库列表；`includePasswords` 为真时附带 Keychain 密码
    func exportItems(includePasswords: Bool) -> [OPDSCatalogExportItem] {
        catalogs.map { cat in
            OPDSCatalogExportItem(
                id: cat.id,
                title: cat.title,
                url: cat.url,
                addedAt: cat.addedAt,
                username: cat.username,
                password: includePasswords ? OPDSCredentialStore.password(catalogID: cat.id) : nil
            )
        }
    }

    /// 用导入快照整表替换（保留合法 URL；密码写入 Keychain）
    func replaceAll(from items: [OPDSCatalogExportItem]) {
        for old in catalogs {
            OPDSCredentialStore.delete(catalogID: old.id)
        }
        var next: [OPDSCatalog] = []
        next.reserveCapacity(items.count)
        for item in items {
            guard let normalized = NetworkURLPolicy.validateOPDS(item.url) else { continue }
            let id = item.id ?? UUID()
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let user = item.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cat = OPDSCatalog(
                id: id,
                title: title.isEmpty ? (normalized.host ?? "OPDS") : title,
                url: normalized.absoluteString,
                addedAt: item.addedAt ?? Date(),
                username: (user?.isEmpty == false) ? user : nil
            )
            if let pw = item.password, !pw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OPDSCredentialStore.savePassword(pw, catalogID: id)
            }
            next.append(cat)
        }
        catalogs = next.sorted { $0.addedAt > $1.addedAt }
        save()
    }
}
