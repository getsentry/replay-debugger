import Foundation

/// Converts rrweb full snapshot events to HTML and DOM trees
struct RRWebHTMLConverter {

    /// Converts a full snapshot event to a DOM tree
    /// - Parameter event: The ReplayEvent with type 2 (FullSnapshot)
    /// - Returns: Root DOMNode of the tree
    static func convertToDOMTree(_ event: ReplayEvent) -> DOMNode? {
        guard event.type == 2 else {  // EventType.FullSnapshot
            return nil
        }

        // Try to find the node - it could be at event.data["node"] or event.data["data"]["node"]
        var node: [String: Any]?

        if let directNode = event.data["node"] as? [String: Any] {
            node = directNode
        } else if let data = event.data["data"] as? [String: Any],
            let nestedNode = data["node"] as? [String: Any]
        {
            node = nestedNode
        }

        guard let node = node else {
            return nil
        }

        return buildDOMNode(from: node)
    }

    /// Converts a full snapshot event to HTML string
    /// - Parameter event: The ReplayEvent with type 2 (FullSnapshot)
    /// - Returns: HTML string representation of the DOM
    static func convertToHTML(_ event: ReplayEvent) -> String? {
        return convertToDOMTree(event)?.toHTML()
    }

    /// Builds a DOM node tree from rrweb serialized node data
    /// - Parameter node: The serialized node dictionary
    /// - Returns: A DOMNode instance representing the node and its children
    static func buildDOMNode(from node: [String: Any]) -> DOMNode? {
        guard let type = node["type"] as? Int else {
            return nil
        }

        // Extract id - default to -1 if not present (for root nodes)
        let id = node["id"] as? Int ?? -1

        switch type {
        case 0:  // Document node
            return buildDocumentNode(from: node, id: id)
        case 1:  // DocumentType node
            return buildDocumentTypeNode(from: node, id: id)
        case 2:  // Element node
            return buildElementNode(from: node, id: id)
        case 3:  // Text node
            return buildTextNode(from: node, id: id)
        case 4:  // CDATA node
            return buildCDATANode(from: node, id: id)
        case 5:  // Comment node
            return buildCommentNode(from: node, id: id)
        default:
            return nil
        }
    }

    private static func buildDocumentNode(from node: [String: Any], id: Int) -> DOMDocumentNode? {
        let docNode = DOMDocumentNode(id: id)

        if let childNodes = node["childNodes"] as? [[String: Any]] {
            for childData in childNodes {
                if let childNode = buildDOMNode(from: childData) {
                    docNode.appendChild(childNode)
                }
            }
        }

        return docNode
    }

    private static func buildDocumentTypeNode(from node: [String: Any], id: Int) -> DOMDocumentTypeNode {
        let name = node["name"] as? String ?? "html"
        let publicId = node["publicId"] as? String ?? ""
        let systemId = node["systemId"] as? String ?? ""

        return DOMDocumentTypeNode(id: id, name: name, publicId: publicId, systemId: systemId)
    }

    private static func buildElementNode(from node: [String: Any], id: Int) -> DOMElementNode? {
        guard var tagName = node["tagName"] as? String else {
            return nil
        }

        let rawAttributes = node["attributes"] as? [String: Any] ?? [:]
        let isSVG = node["isSVG"] as? Bool ?? false

        // Convert <link> elements with _cssText to <style> elements
        var cssTextFromLink: String?
        if tagName.lowercased() == "link", let cssText = rawAttributes["_cssText"] as? String, !cssText.isEmpty {
            tagName = "style"
            cssTextFromLink = cssText
        }

        // Process special rr_ attributes that become inline styles
        var inlineStyles: [String] = []
        if let rrWidth = rawAttributes["rr_width"] {
            let widthValue = convertAttributeValueToString(rrWidth)
            inlineStyles.append("width: \(widthValue)")
        }
        if let rrHeight = rawAttributes["rr_height"] {
            let heightValue = convertAttributeValueToString(rrHeight)
            inlineStyles.append("height: \(heightValue)")
        }

        // Convert attributes to [String: String], filtering out rrweb-specific attrs
        var attributes: [String: String] = [:]
        for (key, value) in rawAttributes {
            // Skip rrweb-specific internal attributes
            if key.hasPrefix("rr_") || key == "_cssText" {
                continue
            }

            if let stringValue = value as? String {
                attributes[key] = stringValue
            } else if let numValue = value as? NSNumber {
                attributes[key] = "\(numValue)"
            } else if let boolValue = value as? Bool, boolValue {
                attributes[key] = key  // Boolean attribute
            }
        }

        // Merge rr_width/rr_height styles with existing style attribute
        // These should override any existing width/height properties
        if !inlineStyles.isEmpty {
            let existingStyle = attributes["style"] ?? ""

            if existingStyle.isEmpty {
                attributes["style"] = inlineStyles.joined(separator: "; ")
            } else {
                // Parse existing styles and replace width/height if they exist
                var styles = parseStyleAttribute(existingStyle)

                // Add rr_ styles (these will override existing width/height)
                for inlineStyle in inlineStyles {
                    let parts = inlineStyle.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let property = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        styles[property] = value
                    }
                }

                // Reconstruct style string
                attributes["style"] = styles.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            }
        }

        let elementNode = DOMElementNode(id: id, tagName: tagName, attributes: attributes, isSVG: isSVG)

        // Add child nodes
        if let childNodes = node["childNodes"] as? [[String: Any]] {
            for childData in childNodes {
                if let childNode = buildDOMNode(from: childData) {
                    elementNode.appendChild(childNode)
                }
            }
        }

        // Handle _cssText for style tags (including converted link tags)
        if tagName == "style" {
            var cssText: String?
            if let linkCSS = cssTextFromLink {
                // CSS from converted <link> element
                cssText = linkCSS
            } else if let styleCSS = rawAttributes["_cssText"] as? String {
                // CSS from regular <style> element
                cssText = styleCSS
            }

            if let cssText = cssText {
                let textNode = DOMTextNode(id: -1, textContent: cssText, isStyle: true)
                elementNode.appendChild(textNode)
            }
        }

        return elementNode
    }

    /// Parses a CSS style attribute string into a dictionary
    private static func parseStyleAttribute(_ styleString: String) -> [String: String] {
        var styles: [String: String] = [:]

        // Split by semicolon to get individual declarations
        let declarations = styleString.split(separator: ";")

        for declaration in declarations {
            let parts = declaration.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let property = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                styles[property] = value
            }
        }

        return styles
    }

    /// Converts an attribute value to a string for use in CSS
    private static func convertAttributeValueToString(_ value: Any) -> String {
        if let stringValue = value as? String {
            // Check if string is a pure number and needs 'px' unit
            if let numericValue = Double(stringValue) {
                // It's a numeric string, add px
                if numericValue == floor(numericValue) {
                    return "\(Int(numericValue))px"
                } else {
                    return "\(numericValue)px"
                }
            }
            // It's a string with units or other CSS value (e.g., "100%", "auto"), return as-is
            return stringValue
        } else if let numValue = value as? NSNumber {
            // Check if it's a whole number, if so don't add decimal
            if numValue.doubleValue == floor(numValue.doubleValue) {
                return "\(numValue.intValue)px"
            } else {
                return "\(numValue)px"
            }
        }
        return "\(value)"
    }

    private static func buildTextNode(from node: [String: Any], id: Int) -> DOMTextNode? {
        guard let textContent = node["textContent"] as? String else {
            return nil
        }

        let isStyle = node["isStyle"] as? Bool ?? false
        return DOMTextNode(id: id, textContent: textContent, isStyle: isStyle)
    }

    private static func buildCDATANode(from node: [String: Any], id: Int) -> DOMCDATANode {
        return DOMCDATANode(id: id)
    }

    private static func buildCommentNode(from node: [String: Any], id: Int) -> DOMCommentNode? {
        guard let textContent = node["textContent"] as? String else {
            return nil
        }

        return DOMCommentNode(id: id, textContent: textContent)
    }

}
