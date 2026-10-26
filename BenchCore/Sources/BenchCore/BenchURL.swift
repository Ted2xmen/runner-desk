import Foundation
import ShelfBridgeCore

/// `shelfbench://job/<id>`: Shelf's "Open in Bench" and Bridge's notification click.
/// `shelfbench://enable?path=<percent-encoded absolute path>`: Shelf's "Enable in Shelf Bench".
public enum BenchURL {
    public static let scheme = "shelfbench"

    /// What an `enable` link asks for.
    public enum EnableLink: Equatable, Sendable {
        /// The decoded path, not yet checked (see `EnableFolder.check`).
        case path(String)
        /// An `enable` link without one usable `path` value.
        case malformed
    }

    /// Longest path accepted from a link, in UTF-8 bytes (`PATH_MAX`).
    static let maxPathBytes = 1024

    /// nil for anything but an `enable` link. The query must hold exactly one `path` item with a
    /// non-empty value; no fragment, no other items, no NUL or line break in the value.
    public static func enableLink(_ url: URL) -> EnableLink? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "enable" else { return nil }
        guard url.path.isEmpty || url.path == "/", url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1, items[0].name == "path",
              let value = items[0].value, !value.isEmpty, value.utf8.count <= maxPathBytes,
              !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" })
        else { return .malformed }
        return .path(value)
    }

    /// The `enable` link for a path: every character outside the unreserved set percent-encoded.
    public static func url(enable path: String) -> URL? {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "\(scheme)://enable?path=\(encoded)")
    }

    /// The job id, or nil for any other shape or an id that is not a Bridge job id (`q-…`, `s-…`).
    public static func jobID(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "job" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 1, url.query == nil, url.fragment == nil else { return nil }
        let id = String(parts[0])
        return JobID.isValid(id) ? id : nil
    }

    public static func url(job id: String) -> URL? { URL(string: "\(scheme)://job/\(id)") }
}
