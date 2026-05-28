import XCTest

@testable import SentryReplayDebugger

final class HTMLBeautifierTests: XCTestCase {

    // MARK: - Basic Formatting Tests

    func testBeautify_EmptyString() {
        // Given
        let html = ""

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertEqual(result, "")
    }

    func testBeautify_SingleTag() {
        // Given
        let html = "<div></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("</div>"))
    }

    func testBeautify_NestedTags() {
        // Given
        let html = "<div><span></span></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<div>"))
        XCTAssertTrue(lines[1].contains("  <span>"))  // Should be indented
        XCTAssertTrue(lines[2].contains("  </span>"))
        XCTAssertTrue(lines[3].contains("</div>"))
    }

    func testBeautify_DeeplyNestedTags() {
        // Given
        let html = "<div><ul><li><a></a></li></ul></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<div>"))
        XCTAssertTrue(lines[1].contains("  <ul>"))
        XCTAssertTrue(lines[2].contains("    <li>"))
        XCTAssertTrue(lines[3].contains("      <a>"))
        XCTAssertTrue(lines[4].contains("      </a>"))
        XCTAssertTrue(lines[5].contains("    </li>"))
        XCTAssertTrue(lines[6].contains("  </ul>"))
        XCTAssertTrue(lines[7].contains("</div>"))
    }

    // MARK: - Text Content Tests

    func testBeautify_WithTextContent() {
        // Given
        let html = "<div>Hello World</div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("Hello World"))
        XCTAssertTrue(result.contains("</div>"))
    }

    func testBeautify_WithNestedTextContent() {
        // Given
        let html = "<div><p>Paragraph text</p></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("  <p>"))
        XCTAssertTrue(result.contains("    Paragraph text"))
        XCTAssertTrue(result.contains("  </p>"))
        XCTAssertTrue(result.contains("</div>"))
    }

    func testBeautify_TextContentWhitespaceHandling() {
        // Given
        let html = "<div>  \n  Text with whitespace  \n  </div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("Text with whitespace"))
        XCTAssertFalse(result.contains("  \n  Text"))
    }

    // MARK: - Void Element Tests

    func testBeautify_VoidElement_Br() {
        // Given
        let html = "<div><br></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<div>"))
        XCTAssertTrue(lines[1].contains("  <br>"))
        XCTAssertTrue(lines[2].contains("</div>"))
    }

    func testBeautify_VoidElement_Img() {
        // Given
        let html = "<div><img src=\"test.jpg\"></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<div>"))
        XCTAssertTrue(lines[1].contains("  <img"))
        XCTAssertTrue(lines[2].contains("</div>"))
    }

    func testBeautify_MultipleVoidElements() {
        // Given
        let html = "<div><br><hr><img></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("  <br>"))
        XCTAssertTrue(result.contains("  <hr>"))
        XCTAssertTrue(result.contains("  <img>"))
    }

    func testBeautify_AllVoidElements() {
        // Test all void elements maintain same indent level
        let voidTags = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr",
        ]

        for tag in voidTags {
            let html = "<div><\(tag)></div>"
            let result = HTMLBeautifier.beautify(html)

            let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            XCTAssertTrue(lines[0].contains("<div>"), "Opening div should be at level 0")
            XCTAssertTrue(lines[1].contains("  <\(tag)"), "Void element \(tag) should be indented once")
            XCTAssertTrue(lines[2].contains("</div>"), "Closing div should be at level 0")
        }
    }

    // MARK: - Self-Closing Tag Tests

    func testBeautify_SelfClosingTag() {
        // Given
        let html = "<div><br/></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("  <br/>"))
    }

    func testBeautify_SelfClosingTag_WithAttributes() {
        // Given
        let html = "<div><img src=\"test.jpg\"/></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("  <img"))
        XCTAssertTrue(result.contains("/>"))
    }

    // MARK: - Special Tag Tests

    func testBeautify_DOCTYPE() {
        // Given
        let html = "<!DOCTYPE html><html></html>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<!DOCTYPE html>"))
        XCTAssertTrue(lines[1].contains("<html>"))
    }

    func testBeautify_Comment() {
        // Given
        let html = "<div><!-- Comment --></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<!-- Comment -->"))
    }

    func testBeautify_XMLDeclaration() {
        // Given
        let html = "<?xml version=\"1.0\"?><root></root>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<?xml"))
    }

    // MARK: - Attribute Tests

    func testBeautify_WithAttributes() {
        // Given
        let html = "<div class=\"container\" id=\"main\"><p>Text</p></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("class=\"container\""))
        XCTAssertTrue(result.contains("id=\"main\""))
    }

    func testBeautify_ComplexAttributes() {
        // Given
        let html = "<a href=\"https://example.com\" target=\"_blank\" data-value=\"test\">Link</a>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("href="))
        XCTAssertTrue(result.contains("target="))
        XCTAssertTrue(result.contains("data-value="))
    }

    // MARK: - Complex Structure Tests

    func testBeautify_CompleteHTMLDocument() {
        // Given
        let html =
            "<!DOCTYPE html><html><head><title>Test</title></head><body><div class=\"container\"><h1>Title</h1><p>Paragraph</p></div></body></html>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<!DOCTYPE html>"))
        XCTAssertTrue(result.contains("<html>"))
        XCTAssertTrue(result.contains("  <head>"))
        XCTAssertTrue(result.contains("    <title>"))
        XCTAssertTrue(result.contains("  <body>"))
        XCTAssertTrue(result.contains("    <div"))
        XCTAssertTrue(result.contains("      <h1>"))
    }

    func testBeautify_List() {
        // Given
        let html = "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<ul>"))
        XCTAssertTrue(lines[1].contains("  <li>"))
        XCTAssertTrue(lines[2].contains("    Item 1"))
        XCTAssertTrue(lines[3].contains("  </li>"))
    }

    func testBeautify_Table() {
        // Given
        let html = "<table><tr><td>Cell 1</td><td>Cell 2</td></tr></table>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("  <tr>"))
        XCTAssertTrue(result.contains("    <td>"))
        XCTAssertTrue(result.contains("      Cell"))
    }

    // MARK: - Edge Cases

    func testBeautify_OnlyWhitespace() {
        // Given
        let html = "   \n\n   "

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertEqual(result, "")
    }

    func testBeautify_NoClosingTags() {
        // Given - Some elements like <br> don't have closing tags
        let html = "<div><p>Text<br>More text</div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("<br>"))
        XCTAssertTrue(result.contains("</div>"))
    }

    func testBeautify_ConsecutiveTags() {
        // Given
        let html = "<div><p></p><p></p><p></p></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].contains("<div>"))
        XCTAssertTrue(lines[1].contains("  <p>"))
        XCTAssertTrue(lines[2].contains("  </p>"))
        XCTAssertTrue(lines[3].contains("  <p>"))
    }

    func testBeautify_MixedContent() {
        // Given
        let html = "<div>Text before<span>Span text</span>Text after</div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("Text before"))
        XCTAssertTrue(result.contains("<span>"))
        XCTAssertTrue(result.contains("Span text"))
        XCTAssertTrue(result.contains("Text after"))
    }

    func testBeautify_EmptyTags() {
        // Given
        let html = "<div><span></span><p></p></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div>"))
        XCTAssertTrue(result.contains("  <span>"))
        XCTAssertTrue(result.contains("  </span>"))
        XCTAssertTrue(result.contains("  <p>"))
        XCTAssertTrue(result.contains("  </p>"))
    }

    // MARK: - Indentation Tests

    func testBeautify_TwoSpaceIndent() {
        // Given
        let html = "<div><p></p></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        // Check that nested elements are indented by exactly 2 spaces
        XCTAssertTrue(lines[1].hasPrefix("  <p>"))
        XCTAssertTrue(lines[2].hasPrefix("  </p>"))
    }

    func testBeautify_MultipleIndentLevels() {
        // Given
        let html = "<div><div><div></div></div></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertTrue(lines[0].hasPrefix("<div>"))
        XCTAssertTrue(lines[1].hasPrefix("  <div>"))
        XCTAssertTrue(lines[2].hasPrefix("    <div>"))
        XCTAssertTrue(lines[3].hasPrefix("    </div>"))
        XCTAssertTrue(lines[4].hasPrefix("  </div>"))
        XCTAssertTrue(lines[5].hasPrefix("</div>"))
    }

    // MARK: - Real-World Examples

    func testBeautify_NavBar() {
        // Given
        let html = "<nav><ul><li><a href=\"#\">Home</a></li><li><a href=\"#\">About</a></li></ul></nav>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<nav>"))
        XCTAssertTrue(result.contains("  <ul>"))
        XCTAssertTrue(result.contains("    <li>"))
        XCTAssertTrue(result.contains("      <a"))
    }

    func testBeautify_Form() {
        // Given
        let html = "<form><label>Name</label><input type=\"text\"><button type=\"submit\">Submit</button></form>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<form>"))
        XCTAssertTrue(result.contains("  <label>"))
        XCTAssertTrue(result.contains("  <input"))
        XCTAssertTrue(result.contains("  <button"))
    }

    func testBeautify_Card() {
        // Given
        let html =
            "<div class=\"card\"><div class=\"card-header\"><h3>Title</h3></div><div class=\"card-body\"><p>Content</p></div></div>"

        // When
        let result = HTMLBeautifier.beautify(html)

        // Then
        XCTAssertTrue(result.contains("<div class=\"card\">"))
        XCTAssertTrue(result.contains("  <div class=\"card-header\">"))
        XCTAssertTrue(result.contains("    <h3>"))
        XCTAssertTrue(result.contains("  <div class=\"card-body\">"))
    }

    // MARK: - Performance Tests

    func testBeautify_LargeDocument() {
        // Given - Generate a large HTML document
        var html = "<html><body>"
        for i in 0..<100 {
            html += "<div id=\"div\(i)\"><p>Paragraph \(i)</p></div>"
        }
        html += "</body></html>"

        // When
        let startTime = Date()
        let result = HTMLBeautifier.beautify(html)
        let endTime = Date()

        // Then
        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThan(endTime.timeIntervalSince(startTime), 1.0, "Should complete in less than 1 second")
    }
}
