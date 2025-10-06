import Foundation

/// Represents a node in the DOM tree, mirroring rrweb's serialized node structure
class DOMNode {
    let id: Int
    var parent: DOMNode?

    init(id: Int) {
        self.id = id
    }

    /// Recursively serialize this node and its children to HTML
    func toHTML() -> String {
        fatalError("toHTML() must be implemented by subclass")
    }

    /// Find a node by ID in this subtree
    func findNode(byId id: Int) -> DOMNode? {
        if self.id == id {
            return self
        }

        if let container = self as? DOMContainerNode {
            for child in container.childNodes {
                if let found = child.findNode(byId: id) {
                    return found
                }
            }
        }

        return nil
    }

    /// Create a deep copy of this node
    func copy() -> DOMNode {
        fatalError("copy() must be implemented by subclass")
    }
}

/// Base class for nodes that can contain children
class DOMContainerNode: DOMNode {
    var childNodes: [DOMNode] = []

    func appendChild(_ child: DOMNode) {
        child.parent = self
        childNodes.append(child)
    }

    func insertBefore(_ child: DOMNode, before: DOMNode?) {
        child.parent = self

        if let beforeNode = before,
           let index = childNodes.firstIndex(where: { $0.id == beforeNode.id }) {
            childNodes.insert(child, at: index)
        } else {
            childNodes.append(child)
        }
    }

    func insertAfter(_ child: DOMNode, after: DOMNode?) {
        child.parent = self

        if let afterNode = after,
           let index = childNodes.firstIndex(where: { $0.id == afterNode.id }) {
            childNodes.insert(child, at: index + 1)
        } else {
            childNodes.insert(child, at: 0)
        }
    }

    func removeChild(_ child: DOMNode) {
        if let index = childNodes.firstIndex(where: { $0.id == child.id }) {
            childNodes[index].parent = nil
            childNodes.remove(at: index)
        }
    }
}

/// Document node (type 0)
class DOMDocumentNode: DOMContainerNode {
    override func toHTML() -> String {
        return childNodes.map { $0.toHTML() }.joined()
    }

    override func copy() -> DOMNode {
        let copied = DOMDocumentNode(id: id)
        for child in childNodes {
            let copiedChild = child.copy()
            copied.appendChild(copiedChild)
        }
        return copied
    }
}

/// DocumentType node (type 1) - <!DOCTYPE html>
class DOMDocumentTypeNode: DOMNode {
    let name: String
    let publicId: String
    let systemId: String

    init(id: Int, name: String, publicId: String, systemId: String) {
        self.name = name
        self.publicId = publicId
        self.systemId = systemId
        super.init(id: id)
    }

    override func toHTML() -> String {
        return "<!DOCTYPE \(name)>"
    }

    override func copy() -> DOMNode {
        return DOMDocumentTypeNode(id: id, name: name, publicId: publicId, systemId: systemId)
    }
}

/// Element node (type 2)
class DOMElementNode: DOMContainerNode {
    let tagName: String
    var attributes: [String: String]
    let isSVG: Bool

    /// CSS rules for <style> elements (managed by StyleSheetRule events)
    /// When set, this takes precedence over child text nodes for rendering
    var cssRules: [String]?

    init(id: Int, tagName: String, attributes: [String: String] = [:], isSVG: Bool = false) {
        self.tagName = tagName
        self.attributes = attributes
        self.isSVG = isSVG
        super.init(id: id)
    }

    /// Initialize CSS rules from current text content (for style elements)
    func initializeCSSRules() {
        guard tagName.lowercased() == "style" else { return }

        // Extract CSS text from child text nodes
        var cssText = ""
        for child in childNodes {
            if let textNode = child as? DOMTextNode {
                cssText += textNode.textContent
            }
        }

        // Split into rules (simple heuristic: split by closing brace followed by whitespace)
        // This is a simplified parser - in reality CSS can be more complex
        if !cssText.isEmpty {
            // For now, treat the entire content as one rule
            // StyleSheetRule events will handle individual rule manipulation
            cssRules = [cssText]
        } else {
            cssRules = []
        }
    }

    /// Add a CSS rule at the specified index
    func addCSSRule(_ rule: String, at index: Int?) {
        if cssRules == nil {
            initializeCSSRules()
        }

        guard var rules = cssRules else { return }

        if let index = index, index >= 0 && index <= rules.count {
            rules.insert(rule, at: index)
        } else {
            rules.append(rule)
        }

        cssRules = rules
    }

    /// Remove CSS rule at the specified index
    func removeCSSRule(at index: Int) {
        guard var rules = cssRules, index >= 0 && index < rules.count else {
            return
        }

        rules.remove(at: index)
        cssRules = rules
    }

    /// Replace all CSS rules
    func replaceCSSRules(with text: String) {
        cssRules = [text]
    }

    override func toHTML() -> String {
        let tag = tagName.lowercased()

        // Build attributes string
        var attrsString = ""
        if !attributes.isEmpty {
            let sortedAttrs = attributes.sorted { $0.key < $1.key }
            attrsString = " " + sortedAttrs.map { key, value in
                // Escape attribute values
                let escapedValue = value
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                return "\(key)=\"\(escapedValue)\""
            }.joined(separator: " ")
        }

        // Void elements (self-closing)
        let voidElements = ["area", "base", "br", "col", "embed", "hr", "img", "input",
                           "link", "meta", "param", "source", "track", "wbr"]
        if voidElements.contains(tag) {
            return "<\(tag)\(attrsString)>"
        }

        // For style elements with cssRules, use those instead of child nodes
        if tag == "style", let rules = cssRules {
            let cssContent = rules.joined(separator: "\n")
            return "<\(tag)\(attrsString)>\(cssContent)</\(tag)>"
        }

        // Regular elements with children
        let childrenHTML = childNodes.map { $0.toHTML() }.joined()
        return "<\(tag)\(attrsString)>\(childrenHTML)</\(tag)>"
    }

    override func copy() -> DOMNode {
        let copied = DOMElementNode(id: id, tagName: tagName, attributes: attributes, isSVG: isSVG)

        // Deep copy cssRules array if it exists
        if let rules = cssRules {
            copied.cssRules = rules.map { $0 }
        }

        // Deep copy children
        for child in childNodes {
            let copiedChild = child.copy()
            copied.appendChild(copiedChild)
        }

        return copied
    }
}

/// Text node (type 3)
class DOMTextNode: DOMNode {
    var textContent: String
    let isStyle: Bool

    init(id: Int, textContent: String, isStyle: Bool = false) {
        self.textContent = textContent
        self.isStyle = isStyle
        super.init(id: id)
    }

    override func toHTML() -> String {
        // Don't escape text content in style tags
        if isStyle {
            return textContent
        }

        // Escape HTML entities in regular text
        return textContent
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    override func copy() -> DOMNode {
        return DOMTextNode(id: id, textContent: textContent, isStyle: isStyle)
    }
}

/// CDATA node (type 4)
class DOMCDATANode: DOMNode {
    override func toHTML() -> String {
        return ""
    }

    override func copy() -> DOMNode {
        return DOMCDATANode(id: id)
    }
}

/// Comment node (type 5)
class DOMCommentNode: DOMNode {
    let textContent: String

    init(id: Int, textContent: String) {
        self.textContent = textContent
        super.init(id: id)
    }

    override func toHTML() -> String {
        return "<!--\(textContent)-->"
    }

    override func copy() -> DOMNode {
        return DOMCommentNode(id: id, textContent: textContent)
    }
}
