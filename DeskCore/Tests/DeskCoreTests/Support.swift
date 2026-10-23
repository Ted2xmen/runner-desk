import Foundation
import ShelfRunnerCore
@testable import DeskCore

/// The protocol v1 fixtures, copied unchanged from the runner repo's `fixtures/protocol/v1/`
/// at the pinned revision.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func status(_ name: String) throws -> StatusV1 {
        guard case .status(let s) = StatusReader.read(try data(name)) else { throw CocoaError(.fileReadCorruptFile) }
        return s
    }

    /// The fixtures' offset (+03:00), so clock times are stable on any machine.
    static let tz = TimeZone(secondsFromGMT: 3 * 3600)!

    static func date(_ iso: String) -> Date { DeskTime.parse(iso)! }

    /// The busy fixture's `seen`.
    static let seen = date("2026-10-22T16:31:05+03:00")
}
