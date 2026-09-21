import Foundation
import Network

/// 粗粒度在线状态，供书籍 TTS 离线策略使用
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    private(set) var isOnline: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "harbor.network.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
