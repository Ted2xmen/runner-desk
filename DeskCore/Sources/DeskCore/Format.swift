import Foundation

/// Times as the sidebar and the header write them.
public enum DeskFormat {
    /// "12 s ago", "5 min ago", "3 h ago", "2 d ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        return "\(s / 86_400) d ago"
    }

    /// Whole minutes from `start` to `end`, never negative.
    public static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }

    /// "14:02" in `timeZone`.
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "Mon 09:00" in `timeZone` (English weekday names: UI text is English, String Catalog later).
    public static func weekdayClock(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = calendar.component(.weekday, from: date)
        return names[(weekday - 1) % 7] + " " + clock(date, timeZone: timeZone)
    }
}
