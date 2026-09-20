// Cloud 同步 / 登录当前为 stub，产品内未暴露入口；保留类型以免历史引用编译失败。
// RESTORED_FROM_LOCAL_SEE_NEXT_COMMIT
import Foundation

public enum Cloud {
    nonisolated(unsafe) public static var appId = "playground"
    nonisolated(unsafe) public static var baseURL = "https://api.dactyl.dev"
    nonisolated(unsafe) public static var aiToken: String?
    public static func configure(appId: String, baseURL: String? = nil, aiToken: String? = nil) {
        Cloud.appId = appId
        if let baseURL { Cloud.baseURL = baseURL }
        if let aiToken { Cloud.aiToken = aiToken }
    }
    nonisolated(unsafe) public static let auth = CloudAuth()
    nonisolated(unsafe) public static let realtime = CloudRealtime()
    nonisolated(unsafe) public static let ai = CloudAI()
    public static func collection(_ name: String) -> CloudCollection { CloudCollection(name: name) }
    public static var authScheme: String {
        "com.dactyl.app" + appId.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct CloudError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public let status: Int
    public var description: String { message }
    public var errorDescription: String? { message }
    public init(message: String, status: Int) { self.message = message; self.status = status }
}

public struct CloudUser: Identifiable, Hashable {
    public let id: String
    public let username: String
}

public struct CloudDocument: Identifiable {
    public let id: String
    public let owner: String?
    public let ownerName: String?
    public let createdAt: String
    public let updatedAt: String
    public let fields: [String: Any]
    public subscript(key: String) -> Any? { fields[key] }
    public func string(_ key: String) -> String? { fields[key] as? String }
    public func int(_ key: String) -> Int? { (fields[key] as? Int) ?? (fields[key] as? Double).map(Int.init) }
    public func double(_ key: String) -> Double? { (fields[key] as? Double) ?? (fields[key] as? Int).map(Double.init) }
    public func bool(_ key: String) -> Bool? { fields[key] as? Bool }
    public var isMine: Bool { owner != nil && owner == Cloud.auth.currentUser?.id }
    init(_ row: [String: Any]) {
        id = row["id"] as? String ?? ""
        owner = row["user_id"] as? String
        ownerName = row["owner_name"] as? String
        createdAt = row["created_at"] as? String ?? ""
        updatedAt = row["updated_at"] as? String ?? ""
        let system: Set<String> = ["id", "user_id", "owner_name", "created_at", "updated_at"]
        fields = row.filter { !system.contains($0.key) }
    }
}

public final class CloudAuth {
    var token: String?
    public private(set) var currentUser: CloudUser?
    public var isSignedIn: Bool { token != nil }
    @discardableResult
    public func signUp(username: String, password: String) async throws -> CloudUser {
        try await session("auth/v1/signup", body: ["email": username, "password": password])
    }
    @discardableResult
    public func signIn(username: String, password: String) async throws -> CloudUser {
        try await session("auth/v1/token?grant_type=password", body: ["email": username, "password": password])
    }
    public func signOut() async {
        token = nil; currentUser = nil
    }
    @discardableResult
    public func signInWithApple() async throws -> CloudUser {
        throw CloudError(message: "Sign in with Apple temporarily unavailable — restore in progress", status: 0)
    }
    @discardableResult
    public func signInWithOAuth(provider: String) async throws -> CloudUser {
        throw CloudError(message: "OAuth temporarily unavailable — restore in progress", status: 0)
    }
    private func session(_ path: String, body: [String: Any]) async throws -> CloudUser {
        throw CloudError(message: "Cloud backend not configured in this build stub", status: 0)
    }
}

public struct CloudCollection {
    public let name: String
    public func add(_ fields: [String: Any]) async throws -> CloudDocument {
        throw CloudError(message: "Cloud backend not configured", status: 0)
    }
    public func list(limit: Int = 50, mine: Bool = false, before: String? = nil) async throws -> [CloudDocument] { [] }
    public func get(_ id: String) async throws -> CloudDocument {
        throw CloudError(message: "not found", status: 404)
    }
    public func update(_ id: String, _ fields: [String: Any]) async throws -> CloudDocument {
        throw CloudError(message: "not found", status: 404)
    }
    public func delete(_ id: String) async throws {}
}

public final class CloudRealtime {
    public func channel(_ name: String) -> CloudChannel { CloudChannel(name: name) }
}
public final class CloudChannel {
    public let name: String
    init(name: String) { self.name = name }
    @discardableResult public func onBroadcast(_ h: @escaping (String, [String: Any]) -> Void) -> CloudChannel { self }
    @discardableResult public func onPresence(_ h: @escaping ([CloudPresence]) -> Void) -> CloudChannel { self }
    public func send(event: String, _ payload: [String: Any] = [:]) {}
    public func track(_ state: [String: Any]) {}
    public func leave() {}
}
public struct CloudPresence: Identifiable {
    public let id: String
    public let name: String
    public let state: [String: Any]
}

public final class CloudAI {
    public struct Message {
        public let role: String
        public let content: String
        public init(role: String, content: String) { self.role = role; self.content = content }
    }
    public func ask(_ prompt: String, model: String? = nil) async throws -> String {
        throw CloudError(message: "Cloud AI not configured", status: 0)
    }
    public func chat(_ messages: [Message], model: String? = nil) async throws -> String {
        throw CloudError(message: "Cloud AI not configured", status: 0)
    }
}
