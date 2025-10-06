import Foundation

/// Beautifies HTML by adding proper indentation
struct HTMLBeautifier {

    static func beautify(_ html: String) -> String {
        var result = ""
        var indentLevel = 0
        let indentString = "  " // 2 spaces

        // Split by tags
        var currentPos = html.startIndex
        var inTag = false
        var tagContent = ""
        var textContent = ""

        while currentPos < html.endIndex {
            let char = html[currentPos]

            if char == "<" {
                // Process any text content before this tag
                if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result += String(repeating: indentString, count: indentLevel)
                    result += textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    result += "\n"
                }
                textContent = ""

                inTag = true
                tagContent = String(char)
            } else if char == ">" && inTag {
                tagContent += String(char)
                inTag = false

                // Process the tag
                let trimmedTag = tagContent.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if it's a closing tag
                if trimmedTag.hasPrefix("</") {
                    indentLevel = max(0, indentLevel - 1)
                    result += String(repeating: indentString, count: indentLevel)
                    result += trimmedTag
                    result += "\n"
                }
                // Check if it's a self-closing tag or special tag
                else if trimmedTag.hasSuffix("/>") ||
                        trimmedTag.hasPrefix("<!") ||
                        trimmedTag.hasPrefix("<?") {
                    result += String(repeating: indentString, count: indentLevel)
                    result += trimmedTag
                    result += "\n"
                }
                // Opening tag
                else {
                    result += String(repeating: indentString, count: indentLevel)
                    result += trimmedTag
                    result += "\n"

                    // Check if it's an inline or void element that shouldn't increase indent
                    let tagName = extractTagName(from: trimmedTag)
                    let voidElements = Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"])

                    if !voidElements.contains(tagName.lowercased()) {
                        indentLevel += 1
                    }
                }

                tagContent = ""
            } else {
                if inTag {
                    tagContent += String(char)
                } else {
                    textContent += String(char)
                }
            }

            currentPos = html.index(after: currentPos)
        }

        // Process any remaining text
        if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result += String(repeating: indentString, count: indentLevel)
            result += textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            result += "\n"
        }

        return result
    }

    private static func extractTagName(from tag: String) -> String {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "/", with: "")

        if let spaceIndex = cleaned.firstIndex(of: " ") {
            return String(cleaned[..<spaceIndex])
        }

        return cleaned
    }
}
