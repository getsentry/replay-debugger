import Foundation

/// Normalizes the timestamp formats found in rrweb replay payloads, where epoch
/// values may arrive in either seconds or milliseconds.
enum ReplayTimestamp {
    /// Threshold of Jan 1, 2020 expressed in milliseconds. Any epoch value larger
    /// than this is treated as milliseconds; anything smaller is treated as seconds.
    private static let millisecondThreshold: TimeInterval = 1_577_836_800_000

    /// Converts a numeric epoch value (seconds or milliseconds) to a `Date`.
    static func date(fromEpoch value: TimeInterval) -> Date {
        let seconds = value > millisecondThreshold ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// Parses a timestamp from a raw JSON value, accepting either a numeric epoch
    /// (seconds or milliseconds) or an ISO8601 string. Returns `nil` if neither.
    static func date(from value: Any?) -> Date? {
        if let interval = value as? TimeInterval {
            return date(fromEpoch: interval)
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}
