import SwiftUI

struct JSONInspectorView: View {
    let data: [String: Any]
    let onHighlightElement: ((Int) -> Void)?
    let onFindInSource: ((Int) -> Void)?
    let onFilterForNode: ((Int) -> Void)?
    let onFilterForNodeAllReferences: ((Int) -> Void)?
    let highlightPath: [String]?  // Path to highlight (from search)
    let searchQuery: String?  // Query to highlight within the value
    @State private var expandedKeys: Set<String> = []
    @State private var largeArrayLimits: [String: Int] = [:]  // Track display limits for large arrays
    @State private var scrollToKey: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(data.keys.sorted()), id: \.self) { key in
                        JSONKeyValueView(
                            key: key,
                            value: data[key] ?? "null",
                            level: 0,
                            expandedKeys: $expandedKeys,
                            largeArrayLimits: $largeArrayLimits,
                            parentKey: nil,
                            rootData: data,
                            onHighlightElement: onHighlightElement,
                            onFindInSource: onFindInSource,
                            onFilterForNode: onFilterForNode,
                            onFilterForNodeAllReferences: onFilterForNodeAllReferences,
                            highlightPath: highlightPath,
                            currentPath: [key],
                            searchQuery: searchQuery
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(red: 0.98, green: 0.98, blue: 0.98))
            .font(.system(size: 11, design: .monospaced))
            .onAppear {
                expandToHighlightedPath()
            }
            .onChange(of: data.keys.sorted().joined()) {
                expandToHighlightedPath()
            }
            .onChange(of: highlightPath) {
                expandToHighlightedPath()
            }
            .onChange(of: scrollToKey) {
                if let key = scrollToKey {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(key, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func expandTopLevelItems() {
        expandedKeys.removeAll()
        for key in data.keys {
            let value = data[key]
            if value is [String: Any] || value is [Any] {
                expandedKeys.insert("0-\(key)")
            }
        }
    }

    private func expandToHighlightedPath() {
        if let path = highlightPath, !path.isEmpty {
            // Expand all keys along the path
            for i in 0..<path.count {
                let pathSegment = path[i]
                let keyPath = "\(i)-\(pathSegment)"
                expandedKeys.insert(keyPath)
            }

            // Set scroll target to the final key in the path
            if let lastKey = path.last {
                let level = path.count - 1
                scrollToKey = "\(level)-\(lastKey)"
            }
        } else {
            expandTopLevelItems()
        }
    }
}

struct JSONKeyValueView: View {
    let key: String
    let value: Any
    let level: Int
    @Binding var expandedKeys: Set<String>
    @Binding var largeArrayLimits: [String: Int]
    @State private var isHovered = false
    let parentKey: String?
    let rootData: [String: Any]
    let onHighlightElement: ((Int) -> Void)?
    let onFindInSource: ((Int) -> Void)?
    let onFilterForNode: ((Int) -> Void)?
    let onFilterForNodeAllReferences: ((Int) -> Void)?
    let highlightPath: [String]?
    let currentPath: [String]
    let searchQuery: String?

    init(
        key: String, value: Any, level: Int, expandedKeys: Binding<Set<String>>,
        largeArrayLimits: Binding<[String: Int]>, parentKey: String? = nil, rootData: [String: Any],
        onHighlightElement: ((Int) -> Void)? = nil, onFindInSource: ((Int) -> Void)? = nil,
        onFilterForNode: ((Int) -> Void)? = nil, onFilterForNodeAllReferences: ((Int) -> Void)? = nil,
        highlightPath: [String]? = nil, currentPath: [String] = [], searchQuery: String? = nil
    ) {
        self.key = key
        self.value = value
        self.level = level
        self._expandedKeys = expandedKeys
        self._largeArrayLimits = largeArrayLimits
        self.parentKey = parentKey
        self.rootData = rootData
        self.onHighlightElement = onHighlightElement
        self.onFindInSource = onFindInSource
        self.onFilterForNode = onFilterForNode
        self.onFilterForNodeAllReferences = onFilterForNodeAllReferences
        self.highlightPath = highlightPath
        self.currentPath = currentPath
        self.searchQuery = searchQuery
    }

    private var isHighlighted: Bool {
        guard let highlightPath = highlightPath else { return false }
        return currentPath == highlightPath
    }

    private var isExpanded: Bool {
        expandedKeys.contains(keyPath)
    }

    private var keyPath: String {
        "\(level)-\(key)"
    }

    private var indentation: CGFloat {
        CGFloat(level * 12)  // Smaller indentation like Chrome
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Indentation spacer
                Color.clear.frame(width: indentation, height: 1)

                // Expand/collapse triangle
                if isExpandableValue {
                    Button(action: toggleExpansion) {
                        Image(systemName: isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                            .frame(width: 12, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12, height: 16)
                }

                // Key name
                Button(action: isExpandableValue ? toggleExpansion : {}) {
                    HStack(spacing: 0) {
                        Text(key)
                            .foregroundColor(Color(red: 0.55, green: 0.06, blue: 0.55))  // Purple like Chrome
                            .fontWeight(.medium)

                        Text(":")
                            .foregroundColor(Color.black)

                        Text(" ")
                            .foregroundColor(Color.black)

                        if !isExpandableValue {
                            valueText
                        } else {
                            objectPreview
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .frame(height: 16)
            .background(
                isHighlighted ? Color.yellow.opacity(0.4) : (isHovered ? Color.black.opacity(0.05) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .id(keyPath)
            .contextMenu {
                if key == "id" || key.hasSuffix(".id") || key == "nextId" || key == "parentId" {
                    if let idValue = extractIdValue(from: value) {
                        if onHighlightElement != nil {
                            Button(action: {
                                onHighlightElement?(idValue)
                            }) {
                                Label("Highlight Element", systemImage: "scope")
                            }
                        }

                        if onFindInSource != nil {
                            Button(action: {
                                onFindInSource?(idValue)
                            }) {
                                Label("Find in Source", systemImage: "doc.text.magnifyingglass")
                            }
                        }

                        if onFilterForNode != nil {
                            Button(action: {
                                onFilterForNode?(idValue)
                            }) {
                                Label("Filter for Node", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        }

                        if onFilterForNodeAllReferences != nil {
                            Button(action: {
                                onFilterForNodeAllReferences?(idValue)
                            }) {
                                Label(
                                    "Filter for all Node References",
                                    systemImage: "line.3.horizontal.decrease.circle.fill")
                            }
                        }

                        Divider()
                    }
                }

                Button("Copy") {
                    copyValue()
                }

                if isExpandableValue {
                    Divider()

                    Button("Expand All") {
                        expandRecursively()
                    }

                    Menu("Expand") {
                        Button("1 Level") {
                            expandLevels(1)
                        }

                        Button("2 Levels") {
                            expandLevels(2)
                        }

                        Button("3 Levels") {
                            expandLevels(3)
                        }

                        Button("4 Levels") {
                            expandLevels(4)
                        }

                        Button("5 Levels") {
                            expandLevels(5)
                        }
                    }

                    Button("Collapse All") {
                        collapseRecursively()
                    }
                }
            }

            // Expanded content
            if isExpanded && isExpandableValue {
                expandedContent
            }
        }
    }

    private var isExpandableValue: Bool {
        value is [String: Any] || value is [Any]
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedKeys.remove(keyPath)
        } else {
            expandedKeys.insert(keyPath)
        }
    }

    private func expandRecursively() {
        expandedKeys.insert(keyPath)
        recursivelyModifyKeys(value: value, currentLevel: level, expand: true)
    }

    private func collapseRecursively() {
        expandedKeys.remove(keyPath)
        recursivelyModifyKeys(value: value, currentLevel: level, expand: false)
    }

    private func expandLevels(_ levels: Int) {
        expandedKeys.insert(keyPath)
        expandKeysToDepth(value: value, currentLevel: level, currentDepth: 0, maxDepth: levels)
    }

    private func recursivelyModifyKeys(value: Any, currentLevel: Int, expand: Bool) {
        if let dict = value as? [String: Any] {
            for (key, nestedValue) in dict {
                let nestedPath = "\(currentLevel + 1)-\(key)"
                if nestedValue is [String: Any] || nestedValue is [Any] {
                    if expand {
                        expandedKeys.insert(nestedPath)
                    } else {
                        expandedKeys.remove(nestedPath)
                    }
                    recursivelyModifyKeys(value: nestedValue, currentLevel: currentLevel + 1, expand: expand)
                }
            }
        } else if let array = value as? [Any] {
            for (index, nestedValue) in array.enumerated() {
                let nestedPath = "\(currentLevel + 1)-\(index)"
                if nestedValue is [String: Any] || nestedValue is [Any] {
                    if expand {
                        expandedKeys.insert(nestedPath)
                    } else {
                        expandedKeys.remove(nestedPath)
                    }
                    recursivelyModifyKeys(value: nestedValue, currentLevel: currentLevel + 1, expand: expand)
                }
            }
        }
    }

    private func copyValue() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let stringToCopy: String

        if let dict = value as? [String: Any] {
            stringToCopy = jsonStringify(dict) ?? String(describing: value)
        } else if let array = value as? [Any] {
            stringToCopy = jsonStringify(array) ?? String(describing: value)
        } else if let string = value as? String {
            stringToCopy = string
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                stringToCopy = number.boolValue ? "true" : "false"
            } else {
                stringToCopy = number.stringValue
            }
        } else if value is NSNull {
            stringToCopy = "null"
        } else {
            stringToCopy = String(describing: value)
        }

        pasteboard.setString(stringToCopy, forType: .string)
    }

    private func jsonStringify(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) else {
            return nil
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func expandKeysToDepth(value: Any, currentLevel: Int, currentDepth: Int, maxDepth: Int) {
        guard currentDepth < maxDepth else { return }

        if let dict = value as? [String: Any] {
            for (key, nestedValue) in dict {
                let nestedPath = "\(currentLevel + 1)-\(key)"
                if nestedValue is [String: Any] || nestedValue is [Any] {
                    expandedKeys.insert(nestedPath)
                    expandKeysToDepth(
                        value: nestedValue, currentLevel: currentLevel + 1, currentDepth: currentDepth + 1,
                        maxDepth: maxDepth)
                }
            }
        } else if let array = value as? [Any] {
            for (index, nestedValue) in array.enumerated() {
                let nestedPath = "\(currentLevel + 1)-\(index)"
                if nestedValue is [String: Any] || nestedValue is [Any] {
                    expandedKeys.insert(nestedPath)
                    expandKeysToDepth(
                        value: nestedValue, currentLevel: currentLevel + 1, currentDepth: currentDepth + 1,
                        maxDepth: maxDepth)
                }
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        HStack(spacing: 4) {
            Text(formattedValue)
                .foregroundColor(valueColor)
                .textSelection(.enabled)

            if let enumLabel = enumLabelForValue {
                Text(enumLabel)
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(Color.blue)
                    .cornerRadius(3)
            }

            if let timestampLabel = timestampLabelForValue {
                Text(timestampLabel)
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(Color.blue)
                    .cornerRadius(3)
            }
        }
    }

    @ViewBuilder
    private var objectPreview: some View {
        if let dict = value as? [String: Any] {
            if dict.isEmpty {
                Text("{}")
                    .foregroundColor(Color.black)
            } else {
                Text(generateObjectPreview(dict))
                    .foregroundColor(Color.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let array = value as? [Any] {
            if array.isEmpty {
                Text("[]")
                    .foregroundColor(Color.black)
            } else {
                Text(generateArrayPreview(array))
                    .foregroundColor(Color.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func generateObjectPreview(_ dict: [String: Any]) -> String {
        // Sort keys by complexity (simpler values first), then alphabetically
        let sortedKeys = dict.keys.sorted { key1, key2 in
            let complexity1 = getValueComplexity(dict[key1])
            let complexity2 = getValueComplexity(dict[key2])
            if complexity1 != complexity2 {
                return complexity1 < complexity2
            }
            return key1 < key2
        }

        let keys = sortedKeys.prefix(3)
        let previews = keys.map { key in
            let valuePreview = formatValuePreview(dict[key])
            return "\(key): \(valuePreview)"
        }
        let joinedPreviews = previews.joined(separator: ", ")
        let suffix = dict.count > 3 ? ", ..." : ""
        return "{\(joinedPreviews)\(suffix)}"
    }

    private func getValueComplexity(_ value: Any?) -> Int {
        switch value {
        case is [Any], is [String: Any]:
            return 1  // Complex (arrays and objects)
        default:
            return 0  // Simple (null, numbers, strings, etc.)
        }
    }

    private func generateArrayPreview(_ array: [Any]) -> String {
        let items = array.prefix(3)
        let previews = items.map { formatValuePreview($0) }
        let joinedPreviews = previews.joined(separator: ", ")
        let suffix = array.count > 3 ? ", ..." : ""
        return "[\(joinedPreviews)\(suffix)]"
    }

    private func formatValuePreview(_ value: Any?) -> String {
        switch value {
        case let string as String:
            let truncated = string.count > 20 ? String(string.prefix(20)) + "..." : string
            return "\"\(truncated)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return "null"
        case let dict as [String: Any]:
            return generateObjectPreview(dict)
        case let array as [Any]:
            return generateArrayPreview(array)
        default:
            return String(describing: value ?? "null")
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let dict = value as? [String: Any] {
            ForEach(Array(dict.keys.sorted()), id: \.self) { nestedKey in
                JSONKeyValueView(
                    key: nestedKey,
                    value: dict[nestedKey] ?? NSNull(),
                    level: level + 1,
                    expandedKeys: $expandedKeys,
                    largeArrayLimits: $largeArrayLimits,
                    parentKey: key,
                    rootData: rootData,
                    onHighlightElement: onHighlightElement,
                    onFindInSource: onFindInSource,
                    onFilterForNode: onFilterForNode,
                    onFilterForNodeAllReferences: onFilterForNodeAllReferences,
                    highlightPath: highlightPath,
                    currentPath: currentPath + [nestedKey],
                    searchQuery: searchQuery
                )
            }
        } else if let array = value as? [Any] {
            if array.count > 100 {
                // Split into chunks of 100
                let chunkSize = 100
                let chunks = stride(from: 0, to: array.count, by: chunkSize).map { startIndex in
                    let endIndex = min(startIndex + chunkSize - 1, array.count - 1)
                    return (startIndex, endIndex)
                }

                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    let (startIndex, endIndex) = chunk
                    let chunkKey = "[\(startIndex) ... \(endIndex)]"
                    let chunkKeyPath = "\(level + 1)-\(chunkKey)"
                    let chunkArray = Array(array[startIndex...endIndex])

                    ArrayChunkView(
                        chunkKey: chunkKey,
                        chunkArray: chunkArray,
                        startIndex: startIndex,
                        level: level + 1,
                        expandedKeys: $expandedKeys,
                        largeArrayLimits: $largeArrayLimits,
                        chunkKeyPath: chunkKeyPath,
                        rootData: rootData,
                        onHighlightElement: onHighlightElement,
                        onFindInSource: onFindInSource,
                        onFilterForNode: onFilterForNode,
                        onFilterForNodeAllReferences: onFilterForNodeAllReferences,
                        highlightPath: highlightPath,
                        currentPath: currentPath,
                        searchQuery: searchQuery
                    )
                }
            } else {
                // Small arrays: render directly
                ForEach(0..<array.count, id: \.self) { index in
                    JSONKeyValueView(
                        key: "\(index)",
                        value: array[index],
                        level: level + 1,
                        expandedKeys: $expandedKeys,
                        largeArrayLimits: $largeArrayLimits,
                        parentKey: key,
                        rootData: rootData,
                        onHighlightElement: onHighlightElement,
                        onFindInSource: onFindInSource,
                        onFilterForNode: onFilterForNode,
                        onFilterForNodeAllReferences: onFilterForNodeAllReferences,
                        highlightPath: highlightPath,
                        currentPath: currentPath + ["\(index)"],
                        searchQuery: searchQuery
                    )
                }
            }
        }
    }

    private var formattedValue: String {
        switch value {
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            // Handle different number types like Chrome
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }

    private var valueColor: Color {
        switch value {
        case is String:
            return Color(red: 0.76, green: 0.09, blue: 0.09)  // Red strings like Chrome
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return Color(red: 0.13, green: 0.13, blue: 0.94)  // Blue booleans
            }
            return Color(red: 0.13, green: 0.13, blue: 0.94)  // Blue numbers
        case is NSNull:
            return Color(red: 0.5, green: 0.5, blue: 0.5)  // Gray null
        default:
            return Color.black
        }
    }

    private var timestampLabelForValue: String? {
        guard key == "timestamp" || key.hasSuffix("Timestamp") else {
            return nil
        }

        let timestamp: TimeInterval?

        if let doubleValue = value as? Double {
            // Check if it's in milliseconds or seconds
            if doubleValue > 1_577_836_800_000 {
                timestamp = doubleValue / 1000
            } else {
                timestamp = doubleValue
            }
        } else if let intValue = value as? Int {
            if intValue > 1_577_836_800_000 {
                timestamp = TimeInterval(intValue) / 1000
            } else {
                timestamp = TimeInterval(intValue)
            }
        } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            if doubleValue > 1_577_836_800_000 {
                timestamp = doubleValue / 1000
            } else {
                timestamp = doubleValue
            }
        } else {
            timestamp = nil
        }

        guard let timestamp = timestamp else {
            return nil
        }

        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        let timeString = formatter.string(from: date)
        let milliseconds = Int((timestamp.truncatingRemainder(dividingBy: 1)) * 1000)

        return "\(timeString).\(String(format: "%03d", milliseconds))"
    }

    private var enumLabelForValue: String? {
        // Map various enum properties based on context
        if key == "source" && level == 0 {
            return incrementalSourceEnumName()
        }

        // For nested properties, we need to check the parent context
        if key == "type" && level == 0 {
            // Check if this is MouseInteraction data (source = 2)
            if let source = rootData["source"] as? Int, source == 2 {
                return mouseInteractionEnumName()
            } else if let source = rootData["source"] as? String, source == "2" {
                return mouseInteractionEnumName()
            }
            // Check if this is CanvasMutation data (source = 9)
            else if let source = rootData["source"] as? Int, source == 9 {
                return canvasContextEnumName()
            } else if let source = rootData["source"] as? String, source == "9" {
                return canvasContextEnumName()
            }
        }

        if key == "pointerType" && level == 0 {
            return pointerTypeEnumName()
        }

        return nil
    }

    private func getNumericValue() -> Int? {
        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        } else if let intValue = value as? Int {
            return intValue
        } else if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func extractIdValue(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String,
            let intValue = Int(stringValue)
        {
            return intValue
        } else if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        return nil
    }

    private func incrementalSourceEnumName() -> String? {
        guard let sourceNumber = getNumericValue() else { return nil }

        // Map to rrweb IncrementalSource enum
        switch sourceNumber {
        case 0: return "Mutation"
        case 1: return "MouseMove"
        case 2: return "MouseInteraction"
        case 3: return "Scroll"
        case 4: return "ViewportResize"
        case 5: return "Input"
        case 6: return "TouchMove"
        case 7: return "MediaInteraction"
        case 8: return "StyleSheetRule"
        case 9: return "CanvasMutation"
        case 10: return "Font"
        case 11: return "Log"
        case 12: return "Drag"
        case 13: return "StyleDeclaration"
        case 14: return "Selection"
        case 15: return "AdoptedStyleSheet"
        case 16: return "CustomElement"
        default: return nil
        }
    }

    private func mouseInteractionEnumName() -> String? {
        guard let typeNumber = getNumericValue() else { return nil }

        // Map to rrweb MouseInteractions enum
        switch typeNumber {
        case 0: return "MouseUp"
        case 1: return "MouseDown"
        case 2: return "Click"
        case 3: return "ContextMenu"
        case 4: return "DblClick"
        case 5: return "Focus"
        case 6: return "Blur"
        case 7: return "TouchStart"
        case 8: return "TouchMove_Departed"
        case 9: return "TouchEnd"
        case 10: return "TouchCancel"
        default: return nil
        }
    }

    private func pointerTypeEnumName() -> String? {
        guard let typeNumber = getNumericValue() else { return nil }

        // Map to rrweb PointerTypes enum
        switch typeNumber {
        case 0: return "Mouse"
        case 1: return "Pen"
        case 2: return "Touch"
        default: return nil
        }
    }

    private func canvasContextEnumName() -> String? {
        guard let contextNumber = getNumericValue() else { return nil }

        // Map to rrweb CanvasContext enum
        switch contextNumber {
        case 0: return "2D"
        case 1: return "WebGL"
        case 2: return "WebGL2"
        default: return nil
        }
    }
}

struct ArrayChunkView: View {
    let chunkKey: String
    let chunkArray: [Any]
    let startIndex: Int
    let level: Int
    @Binding var expandedKeys: Set<String>
    @Binding var largeArrayLimits: [String: Int]
    let chunkKeyPath: String
    let rootData: [String: Any]
    let onHighlightElement: ((Int) -> Void)?
    let onFindInSource: ((Int) -> Void)?
    let onFilterForNode: ((Int) -> Void)?
    let onFilterForNodeAllReferences: ((Int) -> Void)?
    let highlightPath: [String]?
    let currentPath: [String]
    let searchQuery: String?
    @State private var isHovered = false

    private var isExpanded: Bool {
        expandedKeys.contains(chunkKeyPath)
    }

    private var indentation: CGFloat {
        CGFloat(level * 12)
    }

    private func toggleExpansion() {
        if isExpanded {
            expandedKeys.remove(chunkKeyPath)
        } else {
            expandedKeys.insert(chunkKeyPath)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chunk header
            HStack(spacing: 0) {
                // Indentation spacer
                Color.clear.frame(width: indentation, height: 1)

                // Expand/collapse triangle
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        .frame(width: 12, height: 16)
                }
                .buttonStyle(.plain)

                // Chunk label
                Button(action: toggleExpansion) {
                    HStack(spacing: 0) {
                        Text(chunkKey)
                            .foregroundColor(Color(red: 0.55, green: 0.06, blue: 0.55))
                            .fontWeight(.medium)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .frame(height: 16)
            .background(isHovered ? Color.black.opacity(0.05) : Color.clear)
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded chunk content
            if isExpanded {
                ForEach(0..<chunkArray.count, id: \.self) { relativeIndex in
                    let absoluteIndex = startIndex + relativeIndex
                    JSONKeyValueView(
                        key: "\(absoluteIndex)",
                        value: chunkArray[relativeIndex],
                        level: level + 1,
                        expandedKeys: $expandedKeys,
                        largeArrayLimits: $largeArrayLimits,
                        parentKey: chunkKey,
                        rootData: rootData,
                        onHighlightElement: onHighlightElement,
                        onFindInSource: onFindInSource,
                        onFilterForNode: onFilterForNode,
                        onFilterForNodeAllReferences: onFilterForNodeAllReferences,
                        highlightPath: highlightPath,
                        currentPath: currentPath + ["\(absoluteIndex)"],
                        searchQuery: searchQuery
                    )
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var largeArray = (0..<3000).map { $0 }

    JSONInspectorView(
        data: [
            "type": "click",
            "timestamp": 1_641_234_567,
            "coordinates": ["x": 100, "y": 200],
            "metadata": ["browser": "Chrome", "version": "98.0"],
            "active": true,
            "largeArray": largeArray,
        ], onHighlightElement: nil, onFindInSource: nil, onFilterForNode: nil, onFilterForNodeAllReferences: nil,
        highlightPath: nil, searchQuery: nil
    )
    .frame(width: 400, height: 300)
}
