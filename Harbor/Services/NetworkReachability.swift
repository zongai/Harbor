import Foundation
import Network

/// 网络可达性：在线状态 + Wi‑Fi / 昂贵网络，供预缓存与 TTS 离线策略
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    private(set) var isOnline: Bool = true
    /// 当前路径主要走 Wi‑Fi（非蜂窝）
    private(set) var isWiFi: Bool = false
    /// Low Data Mode / 系统标记的昂贵网络
    private(set) var isExpensive: Bool = false
    private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "harbor.network.monitor")

    /// Wi‑Fi 且非昂贵/受限网络时允许后台预缓存
    var isPrefetchAllowed: Bool {
        isOnline && isWiFi && !isExpensive && !isConstrained
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                // 满足路径且使用 Wi‑Fi，且未走蜂窝
                let wifi = path.status == .satisfied
                    && path.usesInterfaceType(.wifi)
                    && !path.usesInterfaceType(.cellular)
                self.isWiFi = wifi
            }
        }
        monitor.start(queue: queue)
    }
}
