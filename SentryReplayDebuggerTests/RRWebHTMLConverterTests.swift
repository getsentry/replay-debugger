import XCTest
@testable import SentryReplayDebugger

final class RRWebHTMLConverterTests: XCTestCase {

    // MARK: - convertToDOMTree Tests

    func testConvertToDOMTree_InvalidEventType() {
        // Given - Event type is not FullSnapshot (2)
        let now = Date()
        let event = ReplayEvent(id: "1", type: 3, timestamp: now, data: [:])

        // When
        let result = RRWebHTMLConverter.convertToDOMTree(event)

        // Then
        XCTAssertNil(result)
    }

    func testConvertToDOMTree_MissingNode() {
        // Given - Event has no node data
        let now = Date()
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: [:])

        // When
        let result = RRWebHTMLConverter.convertToDOMTree(event)

        // Then
        XCTAssertNil(result)
    }

    func testConvertToDOMTree_DirectNode() {
        // Given - Node is directly in event.data["node"]
        let now = Date()
        let nodeData: [String: Any] = [
            "type": 0,
            "id": 1,
            "childNodes": []
        ]
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["node": nodeData])

        // When
        let result = RRWebHTMLConverter.convertToDOMTree(event)

        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result is DOMDocumentNode)
        XCTAssertEqual(result?.id, 1)
    }

    func testConvertToDOMTree_NestedNode() {
        // Given - Node is in event.data["data"]["node"]
        let now = Date()
        let nodeData: [String: Any] = [
            "type": 0,
            "id": 1,
            "childNodes": []
        ]
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["data": ["node": nodeData]])

        // When
        let result = RRWebHTMLConverter.convertToDOMTree(event)

        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(result is DOMDocumentNode)
        XCTAssertEqual(result?.id, 1)
    }

    // MARK: - convertToHTML Tests

    func testConvertToHTML_Success() {
        // Given
        let now = Date()
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": []
        ]
        let event = ReplayEvent(id: "1", type: 2, timestamp: now, data: ["node": nodeData])

        // When
        let html = RRWebHTMLConverter.convertToHTML(event)

        // Then
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("<div") ?? false)
        XCTAssertTrue(html?.contains("</div>") ?? false)
    }

    func testConvertToHTML_InvalidEvent() {
        // Given
        let now = Date()
        let event = ReplayEvent(id: "1", type: 3, timestamp: now, data: [:])

        // When
        let html = RRWebHTMLConverter.convertToHTML(event)

        // Then
        XCTAssertNil(html)
    }

    // MARK: - buildDocumentNode Tests

    func testBuildDocumentNode() {
        // Given
        let nodeData: [String: Any] = [
            "type": 0,
            "id": 1,
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNotNil(node)
        XCTAssertTrue(node is DOMDocumentNode)
        XCTAssertEqual(node?.id, 1)
    }

    func testBuildDocumentNode_WithChildren() {
        // Given
        let childData: [String: Any] = [
            "type": 2,
            "id": 2,
            "tagName": "div",
            "attributes": [:],
            "childNodes": []
        ]
        let nodeData: [String: Any] = [
            "type": 0,
            "id": 1,
            "childNodes": [childData]
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMDocumentNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.childNodes.count, 1)
        XCTAssertEqual(node?.childNodes[0].id, 2)
    }

    // MARK: - buildDocumentTypeNode Tests

    func testBuildDocumentTypeNode() {
        // Given
        let nodeData: [String: Any] = [
            "type": 1,
            "id": 1,
            "name": "html",
            "publicId": "",
            "systemId": ""
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMDocumentTypeNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.name, "html")
        XCTAssertEqual(node?.publicId, "")
        XCTAssertEqual(node?.systemId, "")
    }

    func testBuildDocumentTypeNode_Defaults() {
        // Given - Missing optional fields
        let nodeData: [String: Any] = [
            "type": 1,
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMDocumentTypeNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.name, "html")
        XCTAssertEqual(node?.publicId, "")
        XCTAssertEqual(node?.systemId, "")
    }

    // MARK: - buildElementNode Tests

    func testBuildElementNode_Simple() {
        // Given
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [:],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.tagName, "div")
        XCTAssertTrue(node?.attributes.isEmpty ?? false)
    }

    func testBuildElementNode_WithAttributes() {
        // Given
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [
                "class": "container",
                "id": "main"
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertEqual(node?.attributes["class"], "container")
        XCTAssertEqual(node?.attributes["id"], "main")
    }

    func testBuildElementNode_SVG() {
        // Given
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "svg",
            "attributes": [:],
            "isSVG": true,
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertTrue(node?.isSVG ?? false)
    }

    func testBuildElementNode_RRWidth() {
        // Given - rr_width should be converted to inline style
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": ["rr_width": "100"],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node?.attributes["style"])
        XCTAssertTrue(node?.attributes["style"]?.contains("width: 100px") ?? false)
        XCTAssertNil(node?.attributes["rr_width"], "rr_width should be filtered out")
    }

    func testBuildElementNode_RRHeight() {
        // Given - rr_height should be converted to inline style
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": ["rr_height": 200],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node?.attributes["style"])
        XCTAssertTrue(node?.attributes["style"]?.contains("height: 200px") ?? false)
        XCTAssertNil(node?.attributes["rr_height"], "rr_height should be filtered out")
    }

    func testBuildElementNode_RRWidthAndHeight() {
        // Given
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [
                "rr_width": "100",
                "rr_height": "200"
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node?.attributes["style"])
        XCTAssertTrue(node?.attributes["style"]?.contains("width: 100px") ?? false)
        XCTAssertTrue(node?.attributes["style"]?.contains("height: 200px") ?? false)
    }

    func testBuildElementNode_LinkToStyle() {
        // Given - <link> with _cssText should become <style>
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "link",
            "attributes": [
                "_cssText": ".class { color: red; }"
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertEqual(node?.tagName, "style")
        XCTAssertEqual(node?.childNodes.count, 1)

        let textNode = node?.childNodes[0] as? DOMTextNode
        XCTAssertEqual(textNode?.textContent, ".class { color: red; }")
        XCTAssertTrue(textNode?.isStyle ?? false)
    }

    func testBuildElementNode_StyleWithCSSText() {
        // Given - <style> with _cssText
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "style",
            "attributes": [
                "_cssText": ".test { background: blue; }"
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertEqual(node?.tagName, "style")
        XCTAssertEqual(node?.childNodes.count, 1)

        let textNode = node?.childNodes[0] as? DOMTextNode
        XCTAssertEqual(textNode?.textContent, ".test { background: blue; }")
    }

    func testBuildElementNode_BooleanAttribute() {
        // Given - Boolean attribute (e.g., disabled=true)
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "input",
            "attributes": [
                "disabled": true as Any
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        // Boolean attributes should be set to the key name when true
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.attributes["disabled"], "1")
    }

    func testBuildElementNode_NumericAttribute() {
        // Given - Numeric attribute
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "input",
            "attributes": [
                "maxlength": 100
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertEqual(node?.attributes["maxlength"], "100")
    }

    func testBuildElementNode_MissingTagName() {
        // Given - No tagName
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "attributes": [:],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNil(node)
    }

    // MARK: - buildTextNode Tests

    func testBuildTextNode() {
        // Given
        let nodeData: [String: Any] = [
            "type": 3,
            "id": 1,
            "textContent": "Hello World"
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMTextNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.textContent, "Hello World")
        XCTAssertFalse(node?.isStyle ?? true)
    }

    func testBuildTextNode_Style() {
        // Given
        let nodeData: [String: Any] = [
            "type": 3,
            "id": 1,
            "textContent": ".class { color: red; }",
            "isStyle": true
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMTextNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertTrue(node?.isStyle ?? false)
    }

    func testBuildTextNode_MissingContent() {
        // Given - No textContent
        let nodeData: [String: Any] = [
            "type": 3,
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNil(node)
    }

    // MARK: - buildCommentNode Tests

    func testBuildCommentNode() {
        // Given
        let nodeData: [String: Any] = [
            "type": 5,
            "id": 1,
            "textContent": "This is a comment"
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMCommentNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.textContent, "This is a comment")
    }

    func testBuildCommentNode_MissingContent() {
        // Given - No textContent
        let nodeData: [String: Any] = [
            "type": 5,
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNil(node)
    }

    // MARK: - buildCDATANode Tests

    func testBuildCDATANode() {
        // Given
        let nodeData: [String: Any] = [
            "type": 4,
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNotNil(node)
        XCTAssertTrue(node is DOMCDATANode)
    }

    // MARK: - Invalid Type Tests

    func testBuildDOMNode_InvalidType() {
        // Given - Invalid type
        let nodeData: [String: Any] = [
            "type": 99,
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNil(node)
    }

    func testBuildDOMNode_MissingType() {
        // Given - No type field
        let nodeData: [String: Any] = [
            "id": 1
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNil(node)
    }

    func testBuildDOMNode_DefaultId() {
        // Given - No id field
        let nodeData: [String: Any] = [
            "type": 2,
            "tagName": "div",
            "attributes": [:],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData)

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.id, -1)
    }

    // MARK: - Complex Integration Tests

    func testBuildCompleteTree() {
        // Given - Complete HTML structure
        let htmlNodeData: [String: Any] = [
            "type": 2,
            "id": 2,
            "tagName": "html",
            "attributes": [:],
            "childNodes": [
                [
                    "type": 2,
                    "id": 3,
                    "tagName": "head",
                    "attributes": [:],
                    "childNodes": []
                ],
                [
                    "type": 2,
                    "id": 4,
                    "tagName": "body",
                    "attributes": [:],
                    "childNodes": [
                        [
                            "type": 2,
                            "id": 5,
                            "tagName": "div",
                            "attributes": ["class": "container"],
                            "childNodes": [
                                [
                                    "type": 3,
                                    "id": 6,
                                    "textContent": "Hello World"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let documentData: [String: Any] = [
            "type": 0,
            "id": 1,
            "childNodes": [htmlNodeData]
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: documentData) as? DOMDocumentNode

        // Then
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.childNodes.count, 1)

        let html = node?.toHTML()
        XCTAssertTrue(html?.contains("<html") ?? false)
        XCTAssertTrue(html?.contains("<head") ?? false)
        XCTAssertTrue(html?.contains("<body") ?? false)
        XCTAssertTrue(html?.contains("class=\"container\"") ?? false)
        XCTAssertTrue(html?.contains("Hello World") ?? false)
    }

    func testBuildTree_WithDoctype() {
        // Given - Document with DOCTYPE
        let documentData: [String: Any] = [
            "type": 0,
            "id": 0,
            "childNodes": [
                [
                    "type": 1,
                    "id": 1,
                    "name": "html",
                    "publicId": "",
                    "systemId": ""
                ],
                [
                    "type": 2,
                    "id": 2,
                    "tagName": "html",
                    "attributes": [:],
                    "childNodes": []
                ]
            ]
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: documentData) as? DOMDocumentNode

        // Then
        XCTAssertEqual(node?.childNodes.count, 2)

        let html = node?.toHTML()
        XCTAssertTrue(html?.contains("<!DOCTYPE html>") ?? false)
        XCTAssertTrue(html?.contains("<html") ?? false)
    }

    func testStyleAttributeParsing_OverrideWidth() {
        // Given - Existing style with width that should be overridden
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [
                "style": "width: 50px; color: red",
                "rr_width": "100"
            ],
            "childNodes": []
        ]

        // When
        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode

        // Then
        XCTAssertNotNil(node?.attributes["style"])
        XCTAssertTrue(node?.attributes["style"]?.contains("width: 100px") ?? false)
        XCTAssertTrue(node?.attributes["style"]?.contains("color: red") ?? false)
        XCTAssertFalse(node?.attributes["style"]?.contains("width: 50px") ?? true)
    }

    func testConvertAttributeValue_NumericString() {
        // This tests the internal logic via observable behavior
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [
                "rr_width": "100"
            ],
            "childNodes": []
        ]

        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode
        XCTAssertTrue(node?.attributes["style"]?.contains("100px") ?? false)
    }

    func testConvertAttributeValue_StringWithUnit() {
        // Test that values with units are preserved
        let nodeData: [String: Any] = [
            "type": 2,
            "id": 1,
            "tagName": "div",
            "attributes": [
                "style": "width: 50%"
            ],
            "childNodes": []
        ]

        let node = RRWebHTMLConverter.buildDOMNode(from: nodeData) as? DOMElementNode
        XCTAssertTrue(node?.attributes["style"]?.contains("50%") ?? false)
    }
}
