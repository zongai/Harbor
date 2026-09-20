import Foundation

/// 文章级标志/内容世代：行视图只依赖「自己的 id」，避免仅靠全局 epoch 时误伤无关行的语义不清晰。
/// 注意：Swift Observation 对 Dictionary 仍是整属性粒度；此索引用于明确「哪篇文章变了」，
/// 并配合列表 epoch 做过滤。查找走 `articleSnapshot`，避免 `flatMap` 全库。
@Observable
@MainActor
final class ArticleFlagsIndex {
    private(set) var generations: [UUID: UInt64] = [:]

    func generation(of id: UUID) -> UInt64 {
        generations[id, default: 0]
    }

    func bump(_ id: UUID) {
        generations[id, default: 0] &+= 1
    }

    func bumpAll(_ ids: [UUID]) {
        for id in ids {
            generations[id, default: 0] &+= 1
        }
    }
}
