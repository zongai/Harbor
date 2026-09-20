import Foundation

/// 同一 key 的并发请求共享同一个 Task，避免重复网络/解析
actor RequestDeduper<Success: Sendable> {
    private var inflight: [String: Task<Success, Error>] = [:]

    func run(key: String, operation: @Sendable @escaping () async throws -> Success) async throws -> Success {
        if let existing = inflight[key] {
            return try await existing.value
        }
        let task = Task {
            try await operation()
        }
        inflight[key] = task
        do {
            let value = try await task.value
            inflight[key] = nil
            return value
        } catch {
            inflight[key] = nil
            throw error
        }
    }
}
