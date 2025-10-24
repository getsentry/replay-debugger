import XCTest
@testable import SentryReplayDebugger

final class DOMDocumentNodeTests: XCTestCase {

    func testInit() {
        // Given/When
        let doc = DOMDocumentNode(id: 1)

        // Then
        XCTAssertEqual(doc.id, 1)
        XCTAssertNil(doc.parent)
        XCTAssertTrue(doc.childNodes.isEmpty)
    }

    func testAppendChild() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element = DOMElementNode(id: 2, tagName: "div")

        // When
        doc.appendChild(element)

        // Then
        XCTAssertEqual(doc.childNodes.count, 1)
        XCTAssertEqual(doc.childNodes[0].id, 2)
        XCTAssertEqual(element.parent?.id, 1)
    }

    func testFindNode_FastLookup() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element1 = DOMElementNode(id: 2, tagName: "div")
        let element2 = DOMElementNode(id: 3, tagName: "span")
        let element3 = DOMElementNode(id: 4, tagName: "p")

        doc.appendChild(element1)
        element1.appendChild(element2)
        element2.appendChild(element3)

        // When
        let found = doc.findNode(byId: 4)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, 4)
    }

    func testFindNode_NotFound() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element = DOMElementNode(id: 2, tagName: "div")
        doc.appendChild(element)

        // When
        let found = doc.findNode(byId: 999)

        // Then
        XCTAssertNil(found)
    }

    func testToHTML_EmptyDocument() {
        // Given
        let doc = DOMDocumentNode(id: 1)

        // When
        let html = doc.toHTML()

        // Then
        XCTAssertEqual(html, "")
    }

    func testToHTML_WithChildren() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element = DOMElementNode(id: 2, tagName: "div")
        doc.appendChild(element)

        // When
        let html = doc.toHTML()

        // Then
        XCTAssertTrue(html.contains("<div"))
        XCTAssertTrue(html.contains("</div>"))
    }

    func testCopy() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element = DOMElementNode(id: 2, tagName: "div")
        let text = DOMTextNode(id: 3, textContent: "Hello")

        doc.appendChild(element)
        element.appendChild(text)

        // When
        let copied = doc.copy() as! DOMDocumentNode

        // Then
        XCTAssertEqual(copied.id, doc.id)
        XCTAssertEqual(copied.childNodes.count, 1)
        XCTAssertNotIdentical(copied, doc)
        XCTAssertNotIdentical(copied.childNodes[0], doc.childNodes[0])
    }

    func testRootDocument() {
        // Given
        let doc = DOMDocumentNode(id: 1)
        let element = DOMElementNode(id: 2, tagName: "div")
        let text = DOMTextNode(id: 3, textContent: "Hello")

        doc.appendChild(element)
        element.appendChild(text)

        // When/Then
        XCTAssertEqual(doc.rootDocument?.id, 1)
        XCTAssertEqual(element.rootDocument?.id, 1)
        XCTAssertEqual(text.rootDocument?.id, 1)
    }
}

final class DOMDocumentTypeNodeTests: XCTestCase {

    func testInit() {
        // Given/When
        let doctype = DOMDocumentTypeNode(id: 1, name: "html", publicId: "", systemId: "")

        // Then
        XCTAssertEqual(doctype.id, 1)
        XCTAssertEqual(doctype.name, "html")
        XCTAssertEqual(doctype.publicId, "")
        XCTAssertEqual(doctype.systemId, "")
    }

    func testToHTML() {
        // Given
        let doctype = DOMDocumentTypeNode(id: 1, name: "html", publicId: "", systemId: "")

        // When
        let html = doctype.toHTML()

        // Then
        XCTAssertEqual(html, "<!DOCTYPE html>")
    }

    func testCopy() {
        // Given
        let doctype = DOMDocumentTypeNode(id: 1, name: "html", publicId: "public", systemId: "system")

        // When
        let copied = doctype.copy() as! DOMDocumentTypeNode

        // Then
        XCTAssertEqual(copied.id, doctype.id)
        XCTAssertEqual(copied.name, doctype.name)
        XCTAssertEqual(copied.publicId, doctype.publicId)
        XCTAssertEqual(copied.systemId, doctype.systemId)
        XCTAssertNotIdentical(copied, doctype)
    }
}

final class DOMElementNodeTests: XCTestCase {

    func testInit_Basic() {
        // Given/When
        let element = DOMElementNode(id: 1, tagName: "div")

        // Then
        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.tagName, "div")
        XCTAssertTrue(element.attributes.isEmpty)
        XCTAssertFalse(element.isSVG)
    }

    func testInit_WithAttributes() {
        // Given/When
        let element = DOMElementNode(id: 1, tagName: "div", attributes: ["class": "container", "id": "main"])

        // Then
        XCTAssertEqual(element.attributes["class"], "container")
        XCTAssertEqual(element.attributes["id"], "main")
    }

    func testInit_SVG() {
        // Given/When
        let element = DOMElementNode(id: 1, tagName: "svg", isSVG: true)

        // Then
        XCTAssertTrue(element.isSVG)
    }

    func testToHTML_Simple() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "div")

        // When
        let html = element.toHTML()

        // Then
        XCTAssertTrue(html.contains("<div"))
        XCTAssertTrue(html.contains("data-rr-id=\"1\""))
        XCTAssertTrue(html.contains("</div>"))
    }

    func testToHTML_WithAttributes() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "div", attributes: ["class": "test", "id": "container"])

        // When
        let html = element.toHTML()

        // Then
        XCTAssertTrue(html.contains("class=\"test\""))
        XCTAssertTrue(html.contains("id=\"container\""))
        XCTAssertTrue(html.contains("data-rr-id=\"1\""))
    }

    func testToHTML_WithChildren() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "div")
        let text = DOMTextNode(id: 2, textContent: "Hello World")
        element.appendChild(text)

        // When
        let html = element.toHTML()

        // Then
        XCTAssertTrue(html.contains("<div"))
        XCTAssertTrue(html.contains("Hello World"))
        XCTAssertTrue(html.contains("</div>"))
    }

    func testToHTML_VoidElement() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "br")

        // When
        let html = element.toHTML()

        // Then
        XCTAssertEqual(html, "<br data-rr-id=\"1\">")
        XCTAssertFalse(html.contains("</br>"))
    }

    func testToHTML_VoidElements() {
        // Test all void elements
        let voidTags = ["area", "base", "br", "col", "embed", "hr", "img", "input",
                       "link", "meta", "param", "source", "track", "wbr"]

        for tag in voidTags {
            let element = DOMElementNode(id: 1, tagName: tag)
            let html = element.toHTML()

            XCTAssertTrue(html.starts(with: "<\(tag)"), "Void element \(tag) should have opening tag")
            XCTAssertFalse(html.contains("</\(tag)>"), "Void element \(tag) should not have closing tag")
        }
    }

    func testToHTML_AttributeEscaping() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "div", attributes: ["data-value": "test\"value&more"])

        // When
        let html = element.toHTML()

        // Then
        XCTAssertTrue(html.contains("&quot;"))
        XCTAssertTrue(html.contains("&amp;"))
    }

    func testToHTML_StyleElement() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        let text = DOMTextNode(id: 2, textContent: ".class { color: red; }", isStyle: true)
        style.appendChild(text)

        // When
        let html = style.toHTML()

        // Then
        XCTAssertTrue(html.contains("<style"))
        XCTAssertTrue(html.contains(".class { color: red; }"))
        XCTAssertTrue(html.contains("</style>"))
    }

    func testCSSRules_Initialize() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        let text = DOMTextNode(id: 2, textContent: ".test { color: blue; }", isStyle: true)
        style.appendChild(text)

        // When
        style.initializeCSSRules()

        // Then
        XCTAssertNotNil(style.cssRules)
        XCTAssertEqual(style.cssRules?.count, 1)
        XCTAssertTrue(style.cssRules?.first?.contains(".test") ?? false)
    }

    func testCSSRules_Add() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        style.cssRules = []

        // When
        style.addCSSRule(".new { color: green; }", at: 0)

        // Then
        XCTAssertEqual(style.cssRules?.count, 1)
        XCTAssertEqual(style.cssRules?[0], ".new { color: green; }")
    }

    func testCSSRules_Remove() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        style.cssRules = [".rule1 {}", ".rule2 {}", ".rule3 {}"]

        // When
        style.removeCSSRule(at: 1)

        // Then
        XCTAssertEqual(style.cssRules?.count, 2)
        XCTAssertEqual(style.cssRules?[0], ".rule1 {}")
        XCTAssertEqual(style.cssRules?[1], ".rule3 {}")
    }

    func testCSSRules_Replace() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        style.cssRules = [".old {}"]

        // When
        style.replaceCSSRules(with: ".new { color: red; }")

        // Then
        XCTAssertEqual(style.cssRules?.count, 1)
        XCTAssertEqual(style.cssRules?[0], ".new { color: red; }")
    }

    func testToHTML_WithCSSRules() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        style.cssRules = [".rule1 { color: red; }", ".rule2 { color: blue; }"]

        // When
        let html = style.toHTML()

        // Then
        XCTAssertTrue(html.contains(".rule1 { color: red; }"))
        XCTAssertTrue(html.contains(".rule2 { color: blue; }"))
    }

    func testCopy() {
        // Given
        let element = DOMElementNode(id: 1, tagName: "div", attributes: ["class": "test"])
        let child = DOMTextNode(id: 2, textContent: "Hello")
        element.appendChild(child)

        // When
        let copied = element.copy() as! DOMElementNode

        // Then
        XCTAssertEqual(copied.id, element.id)
        XCTAssertEqual(copied.tagName, element.tagName)
        XCTAssertEqual(copied.attributes["class"], "test")
        XCTAssertEqual(copied.childNodes.count, 1)
        XCTAssertNotIdentical(copied, element)
    }

    func testCopy_WithCSSRules() {
        // Given
        let style = DOMElementNode(id: 1, tagName: "style")
        style.cssRules = [".rule {}"]

        // When
        let copied = style.copy() as! DOMElementNode

        // Then
        XCTAssertNotNil(copied.cssRules)
        XCTAssertEqual(copied.cssRules?.count, 1)
    }
}

final class DOMTextNodeTests: XCTestCase {

    func testInit() {
        // Given/When
        let text = DOMTextNode(id: 1, textContent: "Hello World")

        // Then
        XCTAssertEqual(text.id, 1)
        XCTAssertEqual(text.textContent, "Hello World")
        XCTAssertFalse(text.isStyle)
    }

    func testInit_StyleText() {
        // Given/When
        let text = DOMTextNode(id: 1, textContent: ".class {}", isStyle: true)

        // Then
        XCTAssertTrue(text.isStyle)
    }

    func testToHTML_Plain() {
        // Given
        let text = DOMTextNode(id: 1, textContent: "Hello World")

        // When
        let html = text.toHTML()

        // Then
        XCTAssertEqual(html, "Hello World")
    }

    func testToHTML_WithHTMLEntities() {
        // Given
        let text = DOMTextNode(id: 1, textContent: "<div>Test & \"quotes\"</div>")

        // When
        let html = text.toHTML()

        // Then
        XCTAssertEqual(html, "&lt;div&gt;Test &amp; \"quotes\"&lt;/div&gt;")
        XCTAssertFalse(html.contains("<div>"))
    }

    func testToHTML_StyleText_NoEscaping() {
        // Given
        let text = DOMTextNode(id: 1, textContent: ".class { content: '<>&'; }", isStyle: true)

        // When
        let html = text.toHTML()

        // Then
        XCTAssertEqual(html, ".class { content: '<>&'; }")
        XCTAssertFalse(html.contains("&lt;"))
    }

    func testCopy() {
        // Given
        let text = DOMTextNode(id: 1, textContent: "Hello", isStyle: true)

        // When
        let copied = text.copy() as! DOMTextNode

        // Then
        XCTAssertEqual(copied.id, text.id)
        XCTAssertEqual(copied.textContent, text.textContent)
        XCTAssertEqual(copied.isStyle, text.isStyle)
        XCTAssertNotIdentical(copied, text)
    }
}

final class DOMCommentNodeTests: XCTestCase {

    func testInit() {
        // Given/When
        let comment = DOMCommentNode(id: 1, textContent: "This is a comment")

        // Then
        XCTAssertEqual(comment.id, 1)
        XCTAssertEqual(comment.textContent, "This is a comment")
    }

    func testToHTML() {
        // Given
        let comment = DOMCommentNode(id: 1, textContent: "Comment text")

        // When
        let html = comment.toHTML()

        // Then
        XCTAssertEqual(html, "<!--Comment text-->")
    }

    func testCopy() {
        // Given
        let comment = DOMCommentNode(id: 1, textContent: "Test")

        // When
        let copied = comment.copy() as! DOMCommentNode

        // Then
        XCTAssertEqual(copied.id, comment.id)
        XCTAssertEqual(copied.textContent, comment.textContent)
        XCTAssertNotIdentical(copied, comment)
    }
}

final class DOMCDATANodeTests: XCTestCase {

    func testInit() {
        // Given/When
        let cdata = DOMCDATANode(id: 1)

        // Then
        XCTAssertEqual(cdata.id, 1)
    }

    func testToHTML() {
        // Given
        let cdata = DOMCDATANode(id: 1)

        // When
        let html = cdata.toHTML()

        // Then
        XCTAssertEqual(html, "")
    }

    func testCopy() {
        // Given
        let cdata = DOMCDATANode(id: 1)

        // When
        let copied = cdata.copy() as! DOMCDATANode

        // Then
        XCTAssertEqual(copied.id, cdata.id)
        XCTAssertNotIdentical(copied, cdata)
    }
}

final class DOMContainerNodeTests: XCTestCase {

    func testAppendChild() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "First")
        let child2 = DOMTextNode(id: 3, textContent: "Second")

        // When
        container.appendChild(child1)
        container.appendChild(child2)

        // Then
        XCTAssertEqual(container.childNodes.count, 2)
        XCTAssertEqual(container.childNodes[0].id, 2)
        XCTAssertEqual(container.childNodes[1].id, 3)
        XCTAssertEqual(child1.parent?.id, 1)
        XCTAssertEqual(child2.parent?.id, 1)
    }

    func testInsertBefore_WithReference() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "First")
        let child2 = DOMTextNode(id: 3, textContent: "Third")
        let child3 = DOMTextNode(id: 4, textContent: "Second")

        container.appendChild(child1)
        container.appendChild(child2)

        // When
        container.insertBefore(child3, before: child2)

        // Then
        XCTAssertEqual(container.childNodes.count, 3)
        XCTAssertEqual(container.childNodes[0].id, 2)
        XCTAssertEqual(container.childNodes[1].id, 4)
        XCTAssertEqual(container.childNodes[2].id, 3)
    }

    func testInsertBefore_NoReference() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "First")
        let child2 = DOMTextNode(id: 3, textContent: "Second")

        container.appendChild(child1)

        // When
        container.insertBefore(child2, before: nil)

        // Then
        XCTAssertEqual(container.childNodes.count, 2)
        XCTAssertEqual(container.childNodes[1].id, 3)
    }

    func testInsertAfter_WithReference() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "First")
        let child2 = DOMTextNode(id: 3, textContent: "Third")
        let child3 = DOMTextNode(id: 4, textContent: "Second")

        container.appendChild(child1)
        container.appendChild(child2)

        // When
        container.insertAfter(child3, after: child1)

        // Then
        XCTAssertEqual(container.childNodes.count, 3)
        XCTAssertEqual(container.childNodes[0].id, 2)
        XCTAssertEqual(container.childNodes[1].id, 4)
        XCTAssertEqual(container.childNodes[2].id, 3)
    }

    func testInsertAfter_NoReference() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "Second")
        let child2 = DOMTextNode(id: 3, textContent: "First")

        container.appendChild(child1)

        // When
        container.insertAfter(child2, after: nil)

        // Then
        XCTAssertEqual(container.childNodes.count, 2)
        XCTAssertEqual(container.childNodes[0].id, 3)
        XCTAssertEqual(container.childNodes[1].id, 2)
    }

    func testRemoveChild() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMTextNode(id: 2, textContent: "First")
        let child2 = DOMTextNode(id: 3, textContent: "Second")
        let child3 = DOMTextNode(id: 4, textContent: "Third")

        container.appendChild(child1)
        container.appendChild(child2)
        container.appendChild(child3)

        // When
        container.removeChild(child2)

        // Then
        XCTAssertEqual(container.childNodes.count, 2)
        XCTAssertEqual(container.childNodes[0].id, 2)
        XCTAssertEqual(container.childNodes[1].id, 4)
        XCTAssertNil(child2.parent)
    }

    func testFindNode_InSubtree() {
        // Given
        let container = DOMElementNode(id: 1, tagName: "div")
        let child1 = DOMElementNode(id: 2, tagName: "span")
        let child2 = DOMElementNode(id: 3, tagName: "p")
        let grandchild = DOMTextNode(id: 4, textContent: "Text")

        container.appendChild(child1)
        container.appendChild(child2)
        child2.appendChild(grandchild)

        // When
        let found = container.findNode(byId: 4)

        // Then
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, 4)
    }
}

final class DOMTreeIntegrationTests: XCTestCase {

    func testBuildCompleteDOM() {
        // Given - Build a complete DOM tree
        let doc = DOMDocumentNode(id: 0)
        let doctype = DOMDocumentTypeNode(id: 1, name: "html", publicId: "", systemId: "")
        let html = DOMElementNode(id: 2, tagName: "html")
        let head = DOMElementNode(id: 3, tagName: "head")
        let body = DOMElementNode(id: 4, tagName: "body")
        let div = DOMElementNode(id: 5, tagName: "div", attributes: ["class": "container"])
        let text = DOMTextNode(id: 6, textContent: "Hello World")

        // When - Assemble the tree
        doc.appendChild(doctype)
        doc.appendChild(html)
        html.appendChild(head)
        html.appendChild(body)
        body.appendChild(div)
        div.appendChild(text)

        // Then - Verify structure
        XCTAssertEqual(doc.childNodes.count, 2)
        XCTAssertEqual(html.childNodes.count, 2)
        XCTAssertEqual(body.childNodes.count, 1)
        XCTAssertEqual(div.childNodes.count, 1)

        // Verify HTML output
        let html_output = doc.toHTML()
        XCTAssertTrue(html_output.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html_output.contains("<html"))
        XCTAssertTrue(html_output.contains("<body"))
        XCTAssertTrue(html_output.contains("class=\"container\""))
        XCTAssertTrue(html_output.contains("Hello World"))
    }

    func testDeepCopy_CompleteTree() {
        // Given
        let doc = DOMDocumentNode(id: 0)
        let html = DOMElementNode(id: 1, tagName: "html")
        let body = DOMElementNode(id: 2, tagName: "body")
        let div = DOMElementNode(id: 3, tagName: "div")

        doc.appendChild(html)
        html.appendChild(body)
        body.appendChild(div)

        // When
        let copied = doc.copy() as! DOMDocumentNode

        // Then - Verify deep copy
        XCTAssertNotIdentical(copied, doc)
        XCTAssertNotIdentical(copied.childNodes[0], doc.childNodes[0])

        let copiedHtml = copied.childNodes[0] as! DOMContainerNode
        let originalHtml = doc.childNodes[0] as! DOMContainerNode

        XCTAssertNotIdentical(copiedHtml.childNodes[0], originalHtml.childNodes[0])
    }
}
