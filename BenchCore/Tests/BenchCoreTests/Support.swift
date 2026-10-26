import Foundation
import ShelfBridgeCore
@testable import BenchCore

/// The protocol v2 fixtures, copied unchanged from Bridge repo's `fixtures/protocol/v2/`
/// at the pinned revision.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func status(_ name: String) throws -> StatusV2 {
        guard case .status(let s) = StatusReader.read(try data(name)) else { throw CocoaError(.fileReadCorruptFile) }
        return s
    }

    /// The fixtures' offset (+03:00), so clock times are stable on any machine.
    static let tz = TimeZone(secondsFromGMT: 3 * 3600)!

    static func date(_ iso: String) -> Date { BenchTime.parse(iso)! }

    /// The busy fixture's `seen`.
    static let seen = date("2026-10-22T16:31:05+03:00")
}
