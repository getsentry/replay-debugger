import XCTest
@testable import SentryReplayDebugger

final class ReplaySegmentTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization_WithSortedEvents() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now.addingTimeInterval(1), data: [:])
        let event3 = ReplayEvent(id: "3", type: 4, timestamp: now.addingTimeInterval(2), data: [:])
        let events = [event1, event2, event3]

        // When
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: events)

        // Then
        XCTAssertEqual(segment.id, "seg-1")
        XCTAssertEqual(segment.timestamp, now)
        XCTAssertEqual(segment.events(useSortedOrder: true).count, 3)
        XCTAssertFalse(segment.wasResorted, "Events should not be marked as resorted when already sorted")
    }

    func testInitialization_WithUnsortedEvents() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now.addingTimeInterval(2), data: [:])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now, data: [:])
        let event3 = ReplayEvent(id: "3", type: 4, timestamp: now.addingTimeInterval(1), data: [:])
        let events = [event1, event2, event3]

        // When
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: events)

        // Then
        XCTAssertTrue(segment.wasResorted, "Events should be marked as resorted when not sorted")

        let sortedEvents = segment.events(useSortedOrder: true)
        XCTAssertEqual(sortedEvents[0].id, "2")
        XCTAssertEqual(sortedEvents[1].id, "3")
        XCTAssertEqual(sortedEvents[2].id, "1")
    }

    func testInitialization_WithEmptyEvents() {
        // Given
        let now = Date()
        let events: [ReplayEvent] = []

        // When
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: events)

        // Then
        XCTAssertEqual(segment.id, "seg-1")
        XCTAssertEqual(segment.events(useSortedOrder: true).count, 0)
        XCTAssertFalse(segment.wasResorted, "Empty events should not trigger resort")
    }

    func testInitialization_WithSingleEvent() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])
        let events = [event]

        // When
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: events)

        // Then
        XCTAssertEqual(segment.events(useSortedOrder: true).count, 1)
        XCTAssertFalse(segment.wasResorted, "Single event should not trigger resort")
    }

    func testInitialization_WithIdenticalTimestamps() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["a": 1])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now, data: ["b": 2])
        let event3 = ReplayEvent(id: "3", type: 4, timestamp: now, data: ["c": 3])
        let events = [event1, event2, event3]

        // When
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: events)

        // Then
        XCTAssertFalse(segment.wasResorted, "Events with identical timestamps maintain order")
        XCTAssertEqual(segment.events(useSortedOrder: true).count, 3)
    }

    // MARK: - Events Method Tests

    func testEventsWithSortedOrder_True() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now.addingTimeInterval(2), data: [:])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now, data: [:])
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: [event1, event2])

        // When
        let sortedEvents = segment.events(useSortedOrder: true)

        // Then
        XCTAssertEqual(sortedEvents.count, 2)
        XCTAssertEqual(sortedEvents[0].id, "2")
        XCTAssertEqual(sortedEvents[1].id, "1")
    }

    func testEventsWithSortedOrder_False() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now.addingTimeInterval(2), data: [:])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now, data: [:])
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: [event1, event2])

        // When
        let originalEvents = segment.events(useSortedOrder: false)

        // Then
        XCTAssertEqual(originalEvents.count, 2)
        XCTAssertEqual(originalEvents[0].id, "1")
        XCTAssertEqual(originalEvents[1].id, "2")
    }

    // MARK: - Approximate Size Tests

    func testApproximateSize_WithEvents() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["key": "value"])
        let event2 = ReplayEvent(id: "2", type: 3, timestamp: now.addingTimeInterval(1), data: ["foo": "bar"])
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: [event1, event2])

        // Then
        XCTAssertGreaterThan(segment.approximateSize, 0, "Approximate size should be greater than 0")
    }

    func testApproximateSize_WithEmptyEvents() {
        // Given
        let now = Date()
        let segment = ReplaySegment(id: "seg-1", timestamp: now, events: [])

        // Then
        // Empty array still has some JSON representation
        XCTAssertGreaterThanOrEqual(segment.approximateSize, 0)
    }

    // MARK: - Equatable Tests

    func testEquatable_SameSegments() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])

        let segment1 = ReplaySegment(id: "seg-1", timestamp: now, events: [event])
        let segment2 = ReplaySegment(id: "seg-1", timestamp: now.addingTimeInterval(10), events: [event])

        // Then
        XCTAssertEqual(segment1, segment2, "Segments with same ID should be equal")
    }

    func testEquatable_DifferentIds() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])

        let segment1 = ReplaySegment(id: "seg-1", timestamp: now, events: [event])
        let segment2 = ReplaySegment(id: "seg-2", timestamp: now, events: [event])

        // Then
        XCTAssertNotEqual(segment1, segment2, "Segments with different IDs should not be equal")
    }

    // MARK: - Hashable Tests

    func testHashable_SameSegments() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])
        let segment1 = ReplaySegment(id: "seg-1", timestamp: now, events: [event])
        let segment2 = ReplaySegment(id: "seg-1", timestamp: now.addingTimeInterval(10), events: [event])

        // When
        var set = Set<ReplaySegment>()
        set.insert(segment1)
        set.insert(segment2)

        // Then
        XCTAssertEqual(set.count, 1, "Same segment IDs should produce same hash")
    }

    func testHashable_DifferentSegments() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])
        let segment1 = ReplaySegment(id: "seg-1", timestamp: now, events: [event])
        let segment2 = ReplaySegment(id: "seg-2", timestamp: now, events: [event])

        // When
        var set = Set<ReplaySegment>()
        set.insert(segment1)
        set.insert(segment2)

        // Then
        XCTAssertEqual(set.count, 2, "Different segment IDs should produce different hashes")
    }
}

final class ReplayEventTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        // Given
        let now = Date()
        let data: [String: Any] = ["key": "value", "number": 42]

        // When
        let event = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)

        // Then
        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.type, 2)
        XCTAssertEqual(event.timestamp, now)
        XCTAssertEqual(event.data["key"] as? String, "value")
        XCTAssertEqual(event.data["number"] as? Int, 42)
    }

    func testInitialization_WithEmptyData() {
        // Given
        let now = Date()
        let data: [String: Any] = [:]

        // When
        let event = ReplayEvent(id: "event-1", type: 3, timestamp: now, data: data)

        // Then
        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.type, 3)
        XCTAssertEqual(event.timestamp, now)
        XCTAssertTrue(event.data.isEmpty)
    }

    func testInitialization_WithComplexData() {
        // Given
        let now = Date()
        let data: [String: Any] = [
            "nested": ["inner": "value"],
            "array": [1, 2, 3],
            "bool": true
        ]

        // When
        let event = ReplayEvent(id: "event-1", type: 4, timestamp: now, data: data)

        // Then
        XCTAssertEqual(event.type, 4)
        XCTAssertNotNil(event.data["nested"])
        XCTAssertNotNil(event.data["array"])
        XCTAssertNotNil(event.data["bool"])
    }

    // MARK: - Event Type Tests

    func testEventTypes_ValidRange() {
        // Test all valid RRWeb event types (0-6)
        let now = Date()
        for type in 0...6 {
            let event = ReplayEvent(id: "event-\(type)", type: type, timestamp: now, data: [:])
            XCTAssertEqual(event.type, type)
        }
    }

    // MARK: - Equatable Tests

    func testEquatable_SameEvents() {
        // Given
        let now = Date()
        let data: [String: Any] = ["key": "value"]
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)
        let event2 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)

        // Then
        XCTAssertEqual(event1, event2)
    }

    func testEquatable_DifferentIds() {
        // Given
        let now = Date()
        let data: [String: Any] = ["key": "value"]
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)
        let event2 = ReplayEvent(id: "event-2", type: 2, timestamp: now, data: data)

        // Then
        XCTAssertNotEqual(event1, event2)
    }

    func testEquatable_DifferentTimestamps() {
        // Given
        let now = Date()
        let data: [String: Any] = ["key": "value"]
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)
        let event2 = ReplayEvent(id: "event-1", type: 2, timestamp: now.addingTimeInterval(1), data: data)

        // Then
        XCTAssertNotEqual(event1, event2)
    }

    func testEquatable_DifferentTypes() {
        // Given - Different types don't affect equality (only id and timestamp)
        let now = Date()
        let data: [String: Any] = ["key": "value"]
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)
        let event2 = ReplayEvent(id: "event-1", type: 3, timestamp: now, data: data)

        // Then
        XCTAssertEqual(event1, event2, "Events with same ID and timestamp should be equal regardless of type")
    }

    // MARK: - Hashable Tests

    func testHashable_SameEvents() {
        // Given
        let now = Date()
        let data: [String: Any] = ["key": "value"]
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)
        let event2 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: data)

        // When
        var set = Set<ReplayEvent>()
        set.insert(event1)
        set.insert(event2)

        // Then
        XCTAssertEqual(set.count, 1, "Same events should produce same hash")
    }

    func testHashable_DifferentEvents() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "event-1", type: 2, timestamp: now, data: [:])
        let event2 = ReplayEvent(id: "event-2", type: 3, timestamp: now.addingTimeInterval(1), data: [:])

        // When
        var set = Set<ReplayEvent>()
        set.insert(event1)
        set.insert(event2)

        // Then
        XCTAssertEqual(set.count, 2, "Different events should produce different hashes")
    }

    // MARK: - Edge Case Tests

    func testTimestamp_PastDate() {
        // Given
        let pastDate = Date(timeIntervalSince1970: 0)
        let event = ReplayEvent(id: "event-1", type: 2, timestamp: pastDate, data: [:])

        // Then
        XCTAssertEqual(event.timestamp, pastDate)
    }

    func testTimestamp_FutureDate() {
        // Given
        let futureDate = Date(timeIntervalSince1970: 2000000000)
        let event = ReplayEvent(id: "event-1", type: 2, timestamp: futureDate, data: [:])

        // Then
        XCTAssertEqual(event.timestamp, futureDate)
    }

    func testIdentifiable_Protocol() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "unique-id-123", type: 2, timestamp: now, data: [:])

        // Then - Verify Identifiable conformance
        XCTAssertEqual(event.id, "unique-id-123")
    }
}
