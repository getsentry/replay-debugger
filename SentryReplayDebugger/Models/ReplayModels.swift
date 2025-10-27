import Foundation

struct ReplaySegment: Identifiable, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let originalEvents: [ReplayEvent]
    let sortedEvents: [ReplayEvent]
    let wasResorted: Bool
    let approximateSize: Int  // Cached - calculated once in init

    init(id: String, timestamp: Date, events: [ReplayEvent]) {
        self.id = id
        self.timestamp = timestamp
        self.originalEvents = events

        // Check if events are already sorted
        let isSorted = events.indices.dropLast().allSatisfy { i in
            events[i].timestamp <= events[i + 1].timestamp
        }

        self.wasResorted = !isSorted
        self.sortedEvents = isSorted ? events : events.sorted { $0.timestamp < $1.timestamp }

        // Calculate size once during init
        self.approximateSize = Self.calculateSize(events: events)
    }

    func events(useSortedOrder: Bool) -> [ReplayEvent] {
        return useSortedOrder ? sortedEvents : originalEvents
    }

    /// Calculate approximate size of segment in bytes (based on JSON serialization)
    private static func calculateSize(events: [ReplayEvent]) -> Int {
        do {
            // Estimate by serializing all event data to JSON
            let eventsData = events.map { event -> [String: Any] in
                return [
                    "id": event.id,
                    "type": event.type,
                    "timestamp": event.timestamp.timeIntervalSince1970,
                    "data": event.data
                ]
            }
            let jsonData = try JSONSerialization.data(withJSONObject: eventsData, options: [])
            return jsonData.count
        } catch {
            return 0
        }
    }

    static func == (lhs: ReplaySegment, rhs: ReplaySegment) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ReplayEvent: Identifiable, Hashable {
    let id: String
    let type: Int  // Raw EventType enum value (0-6)
    let timestamp: Date
    let data: [String: Any]

    init(id: String, type: Int, timestamp: Date, data: [String: Any]) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }

    /// Returns the effective timestamp for this event.
    /// For events with an endTimestamp (like resource/fetch events), returns the endTimestamp
    /// since that's when the event was actually captured. Otherwise returns the startTimestamp.
    var effectiveTimestamp: Date {
        // Check if there's an endTimestamp in the data
        if let endTimestamp = data["endTimestamp"] as? TimeInterval {
            return parseTimestamp(endTimestamp) ?? timestamp
        }
        return timestamp
    }

    private func parseTimestamp(_ value: TimeInterval) -> Date? {
        // Check if timestamp is in milliseconds
        // Use a more reasonable threshold: Jan 1, 2020 in seconds (1577836800)
        if value > 1577836800 {
            // Could be milliseconds - check if it's way too large for seconds
            if value > 1577836800000 {
                // Definitely milliseconds, convert to seconds
                return Date(timeIntervalSince1970: value / 1000)
            } else {
                // Likely seconds (between 2020-2050 range)
                return Date(timeIntervalSince1970: value)
            }
        } else {
            // Old timestamp, likely seconds
            return Date(timeIntervalSince1970: value)
        }
    }

    static func == (lhs: ReplayEvent, rhs: ReplayEvent) -> Bool {
        return lhs.id == rhs.id && lhs.timestamp == rhs.timestamp
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
    }
}

