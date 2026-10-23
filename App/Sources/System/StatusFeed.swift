import DeskCore
import Foundation
import ShelfRunnerCore

/// Hears the runner: the `dev.ted2xmen.shelf-runner.status` notification,
/// `dev.ted2xmen.shelf.ping` at launch and when Desk comes to the front, and `heartbeat.json`
/// read directly (first at launch, then every `pollSeconds`, so a silent runner turns offline).
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
            forName: .init(ProtocolV1.statusName), object: nil, queue: .main) { [weak self] note in
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

    /// The runner answers with a status right away (protocol v1). Same `object` as Shelf: the runner
    /// listens only for it; a ping carries nothing and changes nothing.
    func ping() {
        DistributedNotificationCenter.default().postNotificationName(
            .init(ProtocolV1.pingName), object: ProtocolV1.shelfObject, userInfo: nil, deliverImmediately: true)
    }

    private func readHeartbeat() {
        let url = DeskFiles.heartbeat(paths)
        Task {
            let data = await Task.detached { try? Data(contentsOf: url) }.value
            deliver(data.map { StatusReader.read($0) }, data != nil)
        }
    }
}
