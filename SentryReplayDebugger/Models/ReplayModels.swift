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

    static func == (lhs: ReplayEvent, rhs: ReplayEvent) -> Bool {
        return lhs.id == rhs.id && lhs.timestamp == rhs.timestamp
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestamp)
    }
}

