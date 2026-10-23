import Foundation
import ShelfRunnerCore

/// `runnerdesk://job/<id>`: Shelf's "Open in Desk" and the runner's notification click.
public enum DeskURL {
    public static let scheme = "runnerdesk"

    /// The job id, or nil for any other shape or an id that is not a runner job id (`q-…`, `s-…`).
    public static func jobID(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "job" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1, url.query == nil, url.fragment == nil else { return nil }
        let id = String(parts[0])
        return JobID.isValid(id) ? id : nil
    }

    public static func url(job id: String) -> URL? { URL(string: "\(scheme)://job/\(id)") }
}
