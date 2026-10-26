import BenchCore
import Foundation
import ShelfBridgeCore

/// Hears Bridge: the `dev.ted2xmen.shelf-bridge.status` notification,
/// `dev.ted2xmen.shelf.ping` at launch and when Bench comes to the front, and `heartbeat.json`
/// read directly (first at launch, then every `pollSeconds`, so a silent Bridge turns offline).
@MainActor
final class StatusFeed {
    static let pollSeconds: TimeInterval = 5

    private let paths: Paths
    private let deliver: @MainActor (StatusRead?, Bool) -> Void
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    /// `deliver(reading, heartbeatExists)`: a nil reading only reports the file's presence.
    init(paths: Paths, deliver: @escaping @MainActor (StatusRead?, Bool) -> Void) {
        self.paths = paths
        self.deliver = deliver
    }

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: .init(ProtocolV2.statusName), object: nil, queue: .main) { [weak self] note in
            let json = note.userInfo?["json"] as? String
            MainActor.assumeIsolated {
                guard let self, let json else { return }
                self.deliver(StatusReader.read(json: json), true)
            }
        }
        readHeartbeat()
        ping()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readHeartbeat() }
        }
    }

    /// Bridge answers with a status right away (protocol v2). Same `object` as Shelf: Bridge
    /// listens only for it; a ping carries nothing and changes nothing.
    func ping() {
        DistributedNotificationCenter.default().postNotificationName(
            .init(ProtocolV2.pingName), object: ProtocolV2.shelfObject, userInfo: nil, deliverImmediately: true)
    }

    private func readHeartbeat() {
        let url = BenchFiles.heartbeat(paths)
        Task {
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            deliver(data.map { StatusReader.read($0) }, data != nil)
        }
    }
}
