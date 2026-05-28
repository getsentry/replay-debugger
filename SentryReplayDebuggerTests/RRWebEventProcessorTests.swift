import XCTest

@testable import SentryReplayDebugger

final class RRWebEventProcessorTests: XCTestCase {

    // MARK: - RenderState Tests

    func testRenderState_InitialState() {
        // Given/When
        let state = RRWebEventProcessor.RenderState()

        // Then
        XCTAssertNil(state.domTree)
        XCTAssertNil(state.viewportWidth)
        XCTAssertNil(state.viewportHeight)
        XCTAssertNil(state.href)
        XCTAssertNil(state.html)
    }

    func testRenderState_HTML() {
        // Given
        var state = RRWebEventProcessor.RenderState()
        let doc = DOMDocumentNode(id: 1)
        let div = DOMElementNode(id: 2, tagName: "div")
        doc.appendChild(div)
        state.domTree = doc

        // When
        let html = state.html

        // Then
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("<div") ?? false)
    }

    func testRenderState_Copy() {
        // Given
        var state = RRWebEventProcessor.RenderState()
        let doc = DOMDocumentNode(id: 1)
        state.domTree = doc
        state.viewportWidth = 1920
        state.viewportHeight = 1080
        state.href = "https://example.com"

        // When
        let copied = state.copy()

        // Then
        XCTAssertNotNil(copied.domTree)
        XCTAssertEqual(copied.viewportWidth, 1920)
        XCTAssertEqual(copied.viewportHeight, 1080)
        XCTAssertEqual(copied.href, "https://example.com")

        // Verify deep copy (different object instances)
        XCTAssertNotIdentical(copied.domTree as AnyObject, state.domTree as AnyObject)
    }

    // MARK: - processEvents Basic Tests

    func testProcessEvents_EmptyEvents() {
        // Given
        let events: [ReplayEvent] = []

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 0)

        // Then
        XCTAssertNil(state.domTree)
    }

    func testProcessEvents_InvalidIndex_Negative() {
        // Given
        let now = Date()
        let events = [ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: -1)

        // Then
        XCTAssertNil(state.domTree)
    }

    func testProcessEvents_InvalidIndex_OutOfBounds() {
        // Given
        let now = Date()
        let events = [ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 10)

        // Then
        XCTAssertNil(state.domTree)
    }

    func testProcessEvents_FullSnapshot() {
        // Given
        let now = Date()
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": [],
        ]
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["node": nodeData])
        let events = [event]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 0)

        // Then
        XCTAssertNotNil(state.domTree)
        XCTAssertTrue(state.domTree is DOMElementNode)
    }

    func testProcessEvents_SkipsCustomEvents() {
        // Given - Custom events (type 5) should be skipped
        let now = Date()
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": [],
        ]
        let fullSnapshotEvent = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["node": nodeData])
        let customEvent = ReplayEvent(id: "2", type: 5, timestamp: now.addingTimeInterval(1), data: [:])

        let events = [fullSnapshotEvent, customEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        XCTAssertNotNil(state.domTree)
        // Custom event should not affect the DOM
    }

    func testProcessEvents_WithMeta() {
        // Given
        let now = Date()
        let metaEvent = ReplayEvent(
            id: "1", type: 4, timestamp: now,
            data: [
                "width": 1920,
                "height": 1080,
                "href": "https://example.com",
            ])
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": [],
        ]
        let fullSnapshotEvent = ReplayEvent(
            id: "2", type: 2, timestamp: now.addingTimeInterval(1), data: ["node": nodeData])

        let events = [metaEvent, fullSnapshotEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1, metaIndex: 0)

        // Then
        XCTAssertEqual(state.viewportWidth, 1920)
        XCTAssertEqual(state.viewportHeight, 1080)
        XCTAssertEqual(state.href, "https://example.com")
        XCTAssertNotNil(state.domTree)
    }

    func testProcessEvents_StartFromIndex() {
        // Given
        let now = Date()
        let event1 = ReplayEvent(id: "1", type: 0, timestamp: now, data: [:])
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": [],
        ]
        let event2 = ReplayEvent(id: "2", type: 2, timestamp: now.addingTimeInterval(1), data: ["node": nodeData])

        let events = [event1, event2]

        // When - Start from index 1
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1, startFromIndex: 1)

        // Then
        XCTAssertNotNil(state.domTree)
        // Should have processed only event2
    }

    // MARK: - processEventsIncremental Tests

    func testProcessEventsIncremental_InvalidIndices() {
        // Given
        let now = Date()
        let events = [ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])]
        let startingState = RRWebEventProcessor.RenderState()

        // When - Invalid indices
        let state1 = RRWebEventProcessor.processEventsIncremental(events, from: -1, to: 0, startingState: startingState)
        let state2 = RRWebEventProcessor.processEventsIncremental(events, from: 0, to: 10, startingState: startingState)
        let state3 = RRWebEventProcessor.processEventsIncremental(events, from: 1, to: 0, startingState: startingState)

        // Then
        XCTAssertNil(state1.domTree)
        XCTAssertNil(state2.domTree)
        XCTAssertNil(state3.domTree)
    }

    func testProcessEventsIncremental_DeepCopy() {
        // Given
        var startingState = RRWebEventProcessor.RenderState()
        let doc = DOMDocumentNode(id: 1)
        let div = DOMElementNode(id: 2, tagName: "div")
        doc.appendChild(div)
        startingState.domTree = doc

        let events: [ReplayEvent] = []

        // When
        let newState = RRWebEventProcessor.processEventsIncremental(
            events, from: 0, to: -1, startingState: startingState)

        // Then - Should be a deep copy, not the same object
        XCTAssertNotNil(newState.domTree)
        XCTAssertNotIdentical(newState.domTree as AnyObject, startingState.domTree as AnyObject)
    }

    func testProcessEventsIncremental_ProcessesRange() {
        // Given
        let now = Date()
        var startingState = RRWebEventProcessor.RenderState()
        let doc = DOMDocumentNode(id: 1)
        startingState.domTree = doc

        let metaEvent = ReplayEvent(
            id: "1", type: 4, timestamp: now,
            data: [
                "width": 1024,
                "height": 768,
            ])

        let events = [metaEvent]

        // When
        let newState = RRWebEventProcessor.processEventsIncremental(
            events, from: 0, to: 0, startingState: startingState)

        // Then
        XCTAssertEqual(newState.viewportWidth, 1024)
        XCTAssertEqual(newState.viewportHeight, 768)
    }

    // MARK: - Meta Event Processing Tests

    func testProcessMeta() {
        // Given
        let now = Date()
        let metaEvent = ReplayEvent(
            id: "1", type: 4, timestamp: now,
            data: [
                "width": 1920,
                "height": 1080,
                "href": "https://test.com",
            ])

        // When
        let state = RRWebEventProcessor.processEvents([metaEvent], upToIndex: 0)

        // Then
        XCTAssertEqual(state.viewportWidth, 1920)
        XCTAssertEqual(state.viewportHeight, 1080)
        XCTAssertEqual(state.href, "https://test.com")
    }

    func testProcessMeta_PartialData() {
        // Given - Only width provided
        let now = Date()
        let metaEvent = ReplayEvent(
            id: "1", type: 4, timestamp: now,
            data: [
                "width": 800
            ])

        // When
        let state = RRWebEventProcessor.processEvents([metaEvent], upToIndex: 0)

        // Then
        XCTAssertEqual(state.viewportWidth, 800)
        XCTAssertNil(state.viewportHeight)
        XCTAssertNil(state.href)
    }

    // MARK: - Mutation Event Processing Tests

    func testProcessMutation_AddNode() {
        // Given - Setup initial DOM
        let now = Date()
        let doc = DOMDocumentNode(id: 0)
        let body = DOMElementNode(id: 1, tagName: "body")
        doc.appendChild(body)

        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "body",
                            "attributes": [:],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // Mutation event to add a div
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "adds": [
                    [
                        "parentId": 1,
                        "node": [
                            "type": 2,
                            "id": 2,
                            "tagName": "div",
                            "attributes": ["class": "new"],
                            "childNodes": [],
                        ],
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let bodyNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertEqual(bodyNode?.childNodes.count, 1)

        let addedDiv = bodyNode?.childNodes[0] as? DOMElementNode
        XCTAssertEqual(addedDiv?.tagName, "div")
        XCTAssertEqual(addedDiv?.attributes["class"], "new")
    }

    func testProcessMutation_RemoveNode() {
        // Given - Setup initial DOM with a node to remove
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "body",
                            "attributes": [:],
                            "childNodes": [
                                [
                                    "type": 2,
                                    "id": 2,
                                    "tagName": "div",
                                    "attributes": [:],
                                    "childNodes": [],
                                ]
                            ],
                        ]
                    ],
                ]
            ])

        // Mutation event to remove the div
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "removes": [
                    [
                        "id": 2,
                        "parentId": 1,
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let bodyNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertEqual(bodyNode?.childNodes.count, 0)
        XCTAssertNil(state.domTree?.findNode(byId: 2))
    }

    func testProcessMutation_TextUpdate() {
        // Given - Setup initial DOM with text node
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "div",
                            "attributes": [:],
                            "childNodes": [
                                [
                                    "type": 3,
                                    "id": 2,
                                    "textContent": "Old text",
                                ]
                            ],
                        ]
                    ],
                ]
            ])

        // Mutation event to update text
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "texts": [
                    [
                        "id": 2,
                        "value": "New text",
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let textNode = state.domTree?.findNode(byId: 2) as? DOMTextNode
        XCTAssertEqual(textNode?.textContent, "New text")
    }

    func testProcessMutation_AttributeUpdate() {
        // Given - Setup initial DOM
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "div",
                            "attributes": ["class": "old"],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // Mutation event to update attribute
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "attributes": [
                    [
                        "id": 1,
                        "attributes": [
                            "class": "new",
                            "id": "test",
                        ],
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let divNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertEqual(divNode?.attributes["class"], "new")
        XCTAssertEqual(divNode?.attributes["id"], "test")
    }

    func testProcessMutation_AttributeUpdate_RRWidth() {
        // Given - Setup initial DOM
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "div",
                            "attributes": [:],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // Mutation event with rr_width
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "attributes": [
                    [
                        "id": 1,
                        "attributes": [
                            "rr_width": "100"
                        ],
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let divNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertTrue(divNode?.attributes["style"]?.contains("width: 100px") ?? false)
    }

    func testProcessMutation_AttributeUpdate_CSSText() {
        // Given - Setup initial DOM with link element
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "link",
                            "attributes": [:],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // Mutation event with _cssText
        let mutationEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 0,  // Mutation
                "attributes": [
                    [
                        "id": 1,
                        "attributes": [
                            "_cssText": ".test { color: red; }"
                        ],
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, mutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let styleNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertEqual(styleNode?.tagName, "style")
        XCTAssertEqual(styleNode?.childNodes.count, 1)
    }

    // MARK: - StyleSheetRule Event Processing Tests

    func testProcessStyleSheetRule_Replace() {
        // Given - Setup initial DOM with style element
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "style",
                            "attributes": [:],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // StyleSheetRule event to replace CSS
        let styleSheetEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 8,  // StyleSheetRule
                "id": 1,
                "replace": ".new { color: blue; }",
            ])

        let events = [fullSnapshotEvent, styleSheetEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let styleNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertNotNil(styleNode?.cssRules)
        XCTAssertTrue(styleNode?.cssRules?.first?.contains("blue") ?? false)
    }

    func testProcessStyleSheetRule_AddRule() {
        // Given - Setup initial DOM with style element
        let now = Date()
        let fullSnapshotEvent = ReplayEvent(
            id: "1", type: 2, timestamp: now,
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "style",
                            "attributes": [
                                "_cssText": ".old {}"
                            ],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        // StyleSheetRule event to add CSS rule
        let styleSheetEvent = ReplayEvent(
            id: "2", type: 3, timestamp: now.addingTimeInterval(1),
            data: [
                "source": 8,  // StyleSheetRule
                "id": 1,
                "adds": [
                    [
                        "rule": ".new { color: red; }",
                        "index": 0,
                    ]
                ],
            ])

        let events = [fullSnapshotEvent, styleSheetEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 1)

        // Then
        let styleNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertNotNil(styleNode?.cssRules)
    }

    // MARK: - Event Type Processing Tests

    func testProcessEvents_DomContentLoaded() {
        // Given - DomContentLoaded event (type 0) should be no-op
        let now = Date()
        let event = ReplayEvent(id: "1", type: 0, timestamp: now, data: [:])

        // When
        let state = RRWebEventProcessor.processEvents([event], upToIndex: 0)

        // Then
        XCTAssertNil(state.domTree)  // Should not affect state
    }

    func testProcessEvents_Load() {
        // Given - Load event (type 1) should be no-op
        let now = Date()
        let event = ReplayEvent(id: "1", type: 1, timestamp: now, data: [:])

        // When
        let state = RRWebEventProcessor.processEvents([event], upToIndex: 0)

        // Then
        XCTAssertNil(state.domTree)  // Should not affect state
    }

    func testProcessEvents_Plugin() {
        // Given - Plugin event (type 6) should be skipped
        let now = Date()
        let event = ReplayEvent(id: "1", type: 6, timestamp: now, data: [:])

        // When
        let state = RRWebEventProcessor.processEvents([event], upToIndex: 0)

        // Then
        XCTAssertNil(state.domTree)  // Should not affect state
    }

    // MARK: - Complex Integration Tests

    func testCompleteEventSequence() {
        // Given - A complete sequence of events
        let now = Date()
        let metaEvent = ReplayEvent(
            id: "1", type: 4, timestamp: now,
            data: [
                "width": 1920,
                "height": 1080,
            ])

        let fullSnapshotEvent = ReplayEvent(
            id: "2", type: 2, timestamp: now.addingTimeInterval(1),
            data: [
                "node": [
                    "type": 0,
                    "id": 0,
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 1,
                            "tagName": "body",
                            "attributes": [:],
                            "childNodes": [],
                        ]
                    ],
                ]
            ])

        let addMutationEvent = ReplayEvent(
            id: "3", type: 3, timestamp: now.addingTimeInterval(2),
            data: [
                "source": 0,
                "adds": [
                    [
                        "parentId": 1,
                        "node": [
                            "type": 2,
                            "id": 2,
                            "tagName": "div",
                            "attributes": ["class": "container"],
                            "childNodes": [],
                        ],
                    ]
                ],
            ])

        let events = [metaEvent, fullSnapshotEvent, addMutationEvent]

        // When
        let state = RRWebEventProcessor.processEvents(events, upToIndex: 2, metaIndex: 0)

        // Then
        XCTAssertEqual(state.viewportWidth, 1920)
        XCTAssertEqual(state.viewportHeight, 1080)

        let bodyNode = state.domTree?.findNode(byId: 1) as? DOMElementNode
        XCTAssertEqual(bodyNode?.childNodes.count, 1)

        let divNode = state.domTree?.findNode(byId: 2) as? DOMElementNode
        XCTAssertEqual(divNode?.attributes["class"], "container")
    }
}
