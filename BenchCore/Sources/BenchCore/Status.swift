import Foundation
import ShelfBridgeCore

/// One reading of Bridge's status (protocol v2): from `heartbeat.json` or the
/// `dev.ted2xmen.shelf-bridge.status` notification. Both carry the same JSON text.
public enum StatusRead: Equatable, Sendable {
    case status(StatusV2)
    /// Another protocol version: Bench hides Bridge parts and says "Update shelf-bridge".
    case unsupported(bridge: String?)
    /// Not JSON, or not a v2 status.
    case unreadable
}

public enum StatusReader {
    /// The version is read first, so a newer Bridge's status is `unsupported`, not `unreadable`.
    public static func read(_ data: Data) -> StatusRead {
        struct Head: Decodable {
            let v: Int?
            let bridge: String?
        }
        guard let head = try? JSONDecoder().decode(Head.self, from: data) else { return .unreadable }
        guard head.v == ProtocolV2.version else { return .unsupported(bridge: head.bridge) }
        guard let status = try? JSONDecoder().decode(StatusV2.self, from: data) else { return .unreadable }
        return .status(status)
    }

    public static func read(json: String) -> StatusRead { read(Data(json.utf8)) }

    /// The notification's `userInfo` (protocol v2): `["v": 2, "json": "<text>"]`; nil when it has no text.
    public static func read(userInfo: [AnyHashable: Any]?) -> StatusRead? {
        guard let json = userInfo?["json"] as? String else { return nil }
        return read(json: json)
    }

    /// Keeps the newer of two readings: the file and the notification may arrive in any order.
    /// A status replaces another only when its `seen` is not older; anything readable beats
    /// `unreadable`.
    public static func newer(_ current: StatusRead?, _ incoming: StatusRead) -> StatusRead {
        guard let current else { return incoming }
        switch (current, incoming) {
        case (.status(let a), .status(let b)):
            guard let sa = BenchTime.parse(a.seen), let sb = BenchTime.parse(b.seen) else { return incoming }
            return sb >= sa ? incoming : current
        case (_, .unreadable):
            return current
        default:
            return incoming
        }
    }
}

/// ISO 8601 with the local offset (protocol v2).
public enum BenchTime {
    public static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: text) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
