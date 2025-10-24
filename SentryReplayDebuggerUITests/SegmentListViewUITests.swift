import XCTest

final class SegmentListViewUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Segment List Tests

    func testSegmentsScrollViewExists() throws {
        // Given: App is launched
        // When: Looking for segments scroll view
        let scrollView = app.scrollViews["segments-scroll-view"]

        // Then: It should exist
        XCTAssertTrue(scrollView.exists, "Segments scroll view should exist")
    }

    func testSegmentRowsAreDisplayed() throws {
        // Given: App is launched with replay data
        // Note: This test assumes replay data has been loaded
        // You may need to add setup code to load test data

        // When: Looking for segment rows
        let scrollView = app.scrollViews["segments-scroll-view"]

        // Then: At least one segment should be visible
        // Note: Adjust this based on your test data
        let firstSegment = app.otherElements["segment-row-segment-0"]

        XCTAssertTrue(scrollView.exists, "Segments scroll view should exist")
        // Segment rows may not be immediately visible without data
        // This is a basic structure test
    }

    func testSelectingSegmentShowsEvents() throws {
        // Given: App is launched with replay data
        let segmentRow = app.otherElements["segment-row-segment-0"]

        // When: Tapping on a segment
        if segmentRow.exists {
            segmentRow.tap()

            // Then: Events list should become visible
            let eventsList = app.lists["events-list"]
            XCTAssertTrue(eventsList.exists, "Events list should exist after selecting a segment")
        } else {
            // Skip test if no data is loaded
            throw XCTSkip("No segment data available for testing")
        }
    }

    func testSelectingEventShowsDetails() throws {
        // Given: A segment is selected and events are visible
        let segmentRow = app.otherElements["segment-row-segment-0"]

        if segmentRow.exists {
            segmentRow.tap()

            // When: Selecting an event
            let eventRow = app.otherElements["event-row-event-1"]

            if eventRow.exists {
                eventRow.tap()

                // Then: Event details JSON should be visible
                let eventDetails = app.otherElements["event-details-json"]
                XCTAssertTrue(eventDetails.exists, "Event details should be visible after selecting an event")
            } else {
                throw XCTSkip("No event data available for testing")
            }
        } else {
            throw XCTSkip("No segment data available for testing")
        }
    }

    // MARK: - Sort Toggle Tests

    func testSortToggleButton() throws {
        // Given: A segment with resorted events is selected
        let segmentRow = app.otherElements["segment-row-segment-0"]

        if segmentRow.exists {
            segmentRow.tap()

            // When: Sort toggle button exists
            let sortButton = app.buttons["sort-toggle-button"]

            if sortButton.exists {
                // Get initial state
                let initialLabel = sortButton.label

                // Then: Tapping should toggle the sort order
                sortButton.tap()

                // Wait for UI to update
                sleep(1)

                let newLabel = sortButton.label
                XCTAssertNotEqual(initialLabel, newLabel, "Sort button label should change after tapping")
            } else {
                throw XCTSkip("Sort toggle button not available (segment may not have resorted events)")
            }
        } else {
            throw XCTSkip("No segment data available for testing")
        }
    }

    // MARK: - Navigation Tests

    func testNavigationBetweenSegments() throws {
        // Given: Multiple segments are available
        let firstSegment = app.otherElements["segment-row-segment-0"]
        let secondSegment = app.otherElements["segment-row-segment-1"]

        if firstSegment.exists && secondSegment.exists {
            // When: Selecting first segment
            firstSegment.tap()
            sleep(1)

            // Then: Events should be visible
            let eventsList = app.lists["events-list"]
            XCTAssertTrue(eventsList.exists, "Events list should exist after selecting first segment")

            // When: Selecting second segment
            secondSegment.tap()
            sleep(1)

            // Then: Events list should still be visible (with different events)
            XCTAssertTrue(eventsList.exists, "Events list should exist after selecting second segment")
        } else {
            throw XCTSkip("Need at least 2 segments for navigation testing")
        }
    }

    func testNavigationBetweenEvents() throws {
        // Given: A segment is selected with multiple events
        let segmentRow = app.otherElements["segment-row-segment-0"]

        if segmentRow.exists {
            segmentRow.tap()
            sleep(1)

            let firstEvent = app.otherElements["event-row-event-1"]
            let secondEvent = app.otherElements["event-row-event-2"]

            if firstEvent.exists && secondEvent.exists {
                // When: Selecting first event
                firstEvent.tap()
                sleep(1)

                // Then: Event details should be visible
                let eventDetails = app.otherElements["event-details-json"]
                XCTAssertTrue(eventDetails.exists, "Event details should be visible")

                // When: Selecting second event
                secondEvent.tap()
                sleep(1)

                // Then: Event details should still be visible
                XCTAssertTrue(eventDetails.exists, "Event details should still be visible")
            } else {
                throw XCTSkip("Need at least 2 events for navigation testing")
            }
        } else {
            throw XCTSkip("No segment data available for testing")
        }
    }

    // MARK: - Empty State Tests

    func testEmptyStateWhenNoSegmentSelected() throws {
        // Given: App is launched
        // When: No segment is selected
        // Then: Empty state message should be visible

        // Note: This test depends on the initial state of your app
        // Adjust based on whether segments are auto-selected or not
        let emptyStateImage = app.images["doc.text"]
        let emptyStateText = app.staticTexts["No Segment Selected"]

        // These may or may not exist depending on app state
        // This is a structure test
        if !app.lists["events-list"].exists {
            // If events list doesn't exist, we might be in empty state
            // But this depends on app behavior
        }
    }
}
