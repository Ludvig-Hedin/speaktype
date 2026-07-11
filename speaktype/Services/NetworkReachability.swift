import Foundation
import Network

/// Lightweight always-on network reachability so `auto` mode can pre-decide whether remote
/// transcription is even possible, instead of eating a request timeout when offline.
final class NetworkReachability {
    static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.speaktype.reachability")
    private let lock = NSLock()
    private var _isOnline = true

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isOnline
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isOnline = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
