import Foundation

/// Processes rrweb events sequentially to build the rendered HTML state
struct RRWebEventProcessor {

    struct RenderState {
        var domTree: DOMNode?
        var viewportWidth: CGFloat?
        var viewportHeight: CGFloat?
        var href: String?

        /// Generates HTML from the current DOM tree
        var html: String? {
            return domTree?.toHTML()
        }
    }

    /// Processes events up to and including the target event index
    /// - Parameters:
    ///   - events: All events from the segment
    ///   - targetIndex: The index of the selected event to process up to (inclusive)
    /// - Returns: The render state after processing all events up to the target
    static func processEvents(_ events: [ReplayEvent], upToIndex targetIndex: Int) -> RenderState {
        var state = RenderState()

        // Validate index
        guard targetIndex >= 0 && targetIndex < events.count else {
            return state
        }

        // Process all events up to and including the target
        for i in 0...targetIndex {
            let event = events[i]

            // Skip Custom events (type 5) as they don't affect rendering
            if event.type == 5 {
                continue
            }

            processEvent(event, state: &state)
        }

        return state
    }

    /// Processes events incrementally from a starting index to a target index
    /// - Parameters:
    ///   - events: All events from the segment
    ///   - fromIndex: The starting index (inclusive)
    ///   - toIndex: The ending index (inclusive)
    ///   - startingState: The current render state to build upon
    /// - Returns: The updated render state after processing the incremental events
    static func processEventsIncremental(
        _ events: [ReplayEvent],
        from fromIndex: Int,
        to toIndex: Int,
        startingState: RenderState
    ) -> RenderState {
        var state = startingState

        // Validate indices
        guard fromIndex >= 0,
              toIndex < events.count,
              fromIndex <= toIndex else {
            return state
        }

        // Process events in the range
        for i in fromIndex...toIndex {
            let event = events[i]

            // Skip Custom events (type 5) as they don't affect rendering
            if event.type == 5 {
                continue
            }

            processEvent(event, state: &state)
        }

        return state
    }

    private static func processEvent(_ event: ReplayEvent, state: inout RenderState) {
        switch event.type {
        case 0: // DomContentLoaded
            // No-op for rendering
            break

        case 1: // Load
            // No-op for rendering
            break

        case 2: // FullSnapshot
            processFullSnapshot(event, state: &state)

        case 3: // IncrementalSnapshot
            processIncrementalSnapshot(event, state: &state)

        case 4: // Meta
            processMeta(event, state: &state)

        case 6: // Plugin
            // Skip for now
            break

        default:
            break
        }
    }

    private static func processFullSnapshot(_ event: ReplayEvent, state: inout RenderState) {
        // Convert the full snapshot to a DOM tree
        if let domTree = RRWebHTMLConverter.convertToDOMTree(event) {
            state.domTree = domTree
        }
    }

    private static func processIncrementalSnapshot(_ event: ReplayEvent, state: inout RenderState) {
        guard let source = event.data["source"] as? Int else {
            return
        }

        switch source {
        case 0: // Mutation
            processMutation(event, state: &state)
        case 8: // StyleSheetRule
            processStyleSheetRule(event, state: &state)
        default:
            // Other incremental snapshot types not yet implemented
            break
        }
    }

    private static func processMutation(_ event: ReplayEvent, state: inout RenderState) {
        guard let domTree = state.domTree else {
            return
        }

        // Process removes first (in reverse order to avoid index issues)
        if let removes = event.data["removes"] as? [[String: Any]] {
            for removeData in removes {
                guard let nodeId = removeData["id"] as? Int,
                      let parentId = removeData["parentId"] as? Int else {
                    continue
                }

                if let nodeToRemove = domTree.findNode(byId: nodeId),
                   let parent = domTree.findNode(byId: parentId) as? DOMContainerNode {
                    parent.removeChild(nodeToRemove)
                }
            }
        }

        // Process text mutations
        if let texts = event.data["texts"] as? [[String: Any]] {
            for textData in texts {
                guard let nodeId = textData["id"] as? Int else {
                    continue
                }

                if let textNode = domTree.findNode(byId: nodeId) as? DOMTextNode,
                   let value = textData["value"] as? String {
                    textNode.textContent = value
                }
            }
        }

        // Process attribute mutations
        if let attributes = event.data["attributes"] as? [[String: Any]] {
            for attrData in attributes {
                guard let nodeId = attrData["id"] as? Int,
                      let attrs = attrData["attributes"] as? [String: Any] else {
                    continue
                }

                if let elementNode = domTree.findNode(byId: nodeId) as? DOMElementNode {
                    // Handle special rr_ attributes that become inline styles
                    var inlineStyles: [String: String] = [:]

                    for (key, value) in attrs {
                        // Handle special attributes
                        if key == "rr_width" {
                            if let styleValue = convertAttributeValueToStyle(value) {
                                inlineStyles["width"] = styleValue
                            }
                            continue
                        } else if key == "rr_height" {
                            if let styleValue = convertAttributeValueToStyle(value) {
                                inlineStyles["height"] = styleValue
                            }
                            continue
                        } else if key == "_cssText" {
                            // Handle _cssText for style elements
                            if elementNode.tagName.lowercased() == "style" {
                                // Update or add text node with CSS content
                                if let cssText = value as? String {
                                    // Remove existing text nodes and add new one
                                    elementNode.childNodes.removeAll { $0 is DOMTextNode }
                                    let textNode = DOMTextNode(id: -1, textContent: cssText, isStyle: true)
                                    elementNode.appendChild(textNode)
                                }
                            }
                            continue
                        }

                        // Regular attributes
                        if value is NSNull {
                            elementNode.attributes.removeValue(forKey: key)
                        } else if let stringValue = value as? String {
                            elementNode.attributes[key] = stringValue
                        } else if let numValue = value as? NSNumber {
                            elementNode.attributes[key] = "\(numValue)"
                        } else if let dictValue = value as? [String: Any], key == "style" {
                            // Handle style as dictionary (e.g., {"opacity": "1", "transform": "none"})
                            let styleString = dictValue.map { property, value in
                                "\(property): \(value)"
                            }.joined(separator: "; ")
                            elementNode.attributes[key] = styleString
                        }
                    }

                    // Apply inline styles by merging with existing style attribute
                    if !inlineStyles.isEmpty {
                        let existingStyle = elementNode.attributes["style"] ?? ""
                        var styles = parseStyleAttribute(existingStyle)

                        // Merge new styles (these override existing)
                        for (property, value) in inlineStyles {
                            styles[property] = value
                        }

                        // Reconstruct style string
                        elementNode.attributes["style"] = styles.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
                    }
                }
            }
        }

        // Process adds last
        if let adds = event.data["adds"] as? [[String: Any]] {
            for addData in adds {
                guard let parentId = addData["parentId"] as? Int,
                      let nodeData = addData["node"] as? [String: Any],
                      let parent = domTree.findNode(byId: parentId) as? DOMContainerNode else {
                    continue
                }

                // Build the new node from serialized data
                if let newNode = RRWebHTMLConverter.buildDOMNode(from: nodeData) {
                    // Handle positioning with previousId or nextId
                    if let previousId = addData["previousId"] as? Int,
                       let previousNode = domTree.findNode(byId: previousId) {
                        parent.insertAfter(newNode, after: previousNode)
                    } else if let nextId = addData["nextId"] as? Int,
                              let nextNode = domTree.findNode(byId: nextId) {
                        parent.insertBefore(newNode, before: nextNode)
                    } else {
                        parent.appendChild(newNode)
                    }
                }
            }
        }
    }

    private static func processStyleSheetRule(_ event: ReplayEvent, state: inout RenderState) {
        guard let domTree = state.domTree else {
            return
        }

        // Get the target style element by id or styleId
        var styleElement: DOMElementNode?

        if let id = event.data["id"] as? Int {
            styleElement = domTree.findNode(byId: id) as? DOMElementNode
        } else if let styleId = event.data["styleId"] as? Int {
            styleElement = domTree.findNode(byId: styleId) as? DOMElementNode
        }

        guard let element = styleElement, element.tagName.lowercased() == "style" else {
            return
        }

        // Handle replace or replaceSync (complete replacement of stylesheet)
        if let replace = event.data["replace"] as? String {
            element.replaceCSSRules(with: replace)
            return
        } else if let replaceSync = event.data["replaceSync"] as? String {
            element.replaceCSSRules(with: replaceSync)
            return
        }

        // Initialize CSS rules if not already done
        if element.cssRules == nil {
            element.initializeCSSRules()
        }

        // Process removes first (in reverse order to avoid index issues)
        if let removes = event.data["removes"] as? [[String: Any]] {
            // Sort by index descending to remove from end first
            let sortedRemoves = removes.compactMap { removeData -> Int? in
                if let index = removeData["index"] as? Int {
                    return index
                } else if let indexArray = removeData["index"] as? [Int], let firstIndex = indexArray.first {
                    // For nested indices, use the first index
                    return firstIndex
                }
                return nil
            }.sorted(by: >)

            for index in sortedRemoves {
                element.removeCSSRule(at: index)
            }
        }

        // Process adds
        if let adds = event.data["adds"] as? [[String: Any]] {
            for addData in adds {
                guard let rule = addData["rule"] as? String else {
                    continue
                }

                var index: Int?
                if let indexValue = addData["index"] as? Int {
                    index = indexValue
                } else if let indexArray = addData["index"] as? [Int], let firstIndex = indexArray.first {
                    // For nested indices, use the first index
                    index = firstIndex
                }

                element.addCSSRule(rule, at: index)
            }
        }
    }

    private static func processMeta(_ event: ReplayEvent, state: inout RenderState) {
        // Extract viewport dimensions from meta event
        if let width = event.data["width"] as? NSNumber {
            state.viewportWidth = CGFloat(width.doubleValue)
        }

        if let height = event.data["height"] as? NSNumber {
            state.viewportHeight = CGFloat(height.doubleValue)
        }

        if let href = event.data["href"] as? String {
            state.href = href
        }
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

    /// Converts an attribute value to a CSS style value
    private static func convertAttributeValueToStyle(_ value: Any) -> String? {
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
        return nil
    }
}
