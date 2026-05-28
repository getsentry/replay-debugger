import AppKit
import SwiftUI

/// A split view that automatically persists its divider position
struct PersistentVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let autosaveName: String
    let top: Top
    let bottom: Bottom

    init(autosaveName: String, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.autosaveName = autosaveName
        self.top = top()
        self.bottom = bottom()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autosaveName = NSSplitView.AutosaveName(autosaveName)

        let topHosting = NSHostingView(rootView: top)
        let bottomHosting = NSHostingView(rootView: bottom)

        splitView.addArrangedSubview(topHosting)
        splitView.addArrangedSubview(bottomHosting)

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if splitView.arrangedSubviews.count >= 2 {
            if let topHosting = splitView.arrangedSubviews[0] as? NSHostingView<Top> {
                topHosting.rootView = top
            }
            if let bottomHosting = splitView.arrangedSubviews[1] as? NSHostingView<Bottom> {
                bottomHosting.rootView = bottom
            }
        }
    }
}

struct PersistentHSplitView<Left: View, Right: View>: NSViewRepresentable {
    let autosaveName: String
    let left: Left
    let right: Right

    init(autosaveName: String, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.autosaveName = autosaveName
        self.left = left()
        self.right = right()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = NSSplitView.AutosaveName(autosaveName)

        let leftHosting = NSHostingView(rootView: left)
        let rightHosting = NSHostingView(rootView: right)

        splitView.addArrangedSubview(leftHosting)
        splitView.addArrangedSubview(rightHosting)

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if splitView.arrangedSubviews.count >= 2 {
            if let leftHosting = splitView.arrangedSubviews[0] as? NSHostingView<Left> {
                leftHosting.rootView = left
            }
            if let rightHosting = splitView.arrangedSubviews[1] as? NSHostingView<Right> {
                rightHosting.rootView = right
            }
        }
    }
}

struct SearchMatch: Identifiable {
    let id = UUID()
    let segmentId: String
    let eventId: String
    let matchText: String
    let jsonPath: [String]?  // Path to matched item in JSON (e.g., ["data", "attributes", "0", "name"])
    let matchType: MatchType

    enum MatchType {
        case eventData
        case eventId
        case eventType
    }
}

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var segments: [ReplaySegment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var enabledEventTypes: Set<String> = [
        "DomContentLoaded", "Load", "FullSnapshot", "IncrementalSnapshot", "Meta", "Custom",
        "Plugin",
    ]
    @State private var enabledIncrementalSources: Set<Int> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]
    @State private var enabledCustomTags: Set<String> = []
    @State private var selectedSegmentIDs: Set<String> = []
    @State private var selectedEvent: ReplayEvent?
    @State private var useSortedOrder = true
    @State private var timestampFilterOperator: String = ">"
    @State private var timestampFilterText: String = ""
    @State private var timestampFilterValue: String = ""
    @State private var nodeIdFilterText: String = ""
    @State private var nodeIdFilter: Int?
    @State private var nodeIdFilterAllReferences: Bool = false
    @State private var highlightedNodeId: Int?
    @State private var showHighlightError: Bool = false
    @State private var highlightErrorMessage: String = ""
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // HTML Source view state
    @State private var showHTMLSource: Bool = false
    @State private var htmlSourceSearchQuery: String = ""

    // Global search
    @State private var showGlobalSearch = false
    @State private var globalSearchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentSearchIndex: Int = 0
    @FocusState private var searchFieldFocused: Bool
    @State private var shouldScrollToSelection: Bool = false
    @State private var currentSearchMatch: SearchMatch?

    // Event type counts (computed when filter inspector is shown)
    @State private var eventTypeCounts: [String: Int] = [:]
    @State private var incrementalSourceCounts: [Int: Int] = [:]
    @State private var customTagCounts: [String: Int] = [:]
    @State private var allCustomTags: [String] = []

    // Performance: Cache for allEvents (always chronologically sorted for HTML renderer)
    @State private var cachedAllEvents: [ReplayEvent] = []
    @State private var cachedAllEventsSegmentCount: Int = 0

    // Performance: Pre-computed segment boundaries
    @State private var segmentBoundaries: [Int] = []

    // Performance: Pre-computed indices for FullSnapshot (type 2) and Meta (type 4) events
    @State private var fullSnapshotIndices: [Int] = []
    @State private var metaIndices: [Int] = []

    // Performance: Event-based RenderState caching (shared across all HTML renderers)
    @State private var htmlRenderStateCache: [Int: RRWebEventProcessor.RenderState] = [:]
    private let cacheInterval: Int = 250

    // Performance: Cache filtered segments to avoid recomputation
    @State private var cachedFilteredSegments: [ReplaySegment] = []
    @State private var filterCacheKey: String = ""

    // Performance: Cache displayedSegment lookup
    @State private var cachedDisplayedSegment: ReplaySegment?
    @State private var cachedDisplayedSegmentId: String?

    private var selectedSegments: [ReplaySegment] {
        filteredSegments.filter { selectedSegmentIDs.contains($0.id) }
    }

    private var primarySelectedSegment: ReplaySegment? {
        guard let firstID = selectedSegmentIDs.sorted().first else { return nil }
        return filteredSegments.first { $0.id == firstID }
    }

    func setTimestampFilter(_ timestamp: Date) {
        timestampFilterValue = String(format: "%.3f", timestamp.timeIntervalSince1970)
    }

    // Event types ordered by their enum values (0-6)
    private let allEventTypes = [
        "DomContentLoaded", "Load", "FullSnapshot", "IncrementalSnapshot", "Meta", "Custom",
        "Plugin",
    ]

    // IncrementalSnapshot source types ordered by their enum values (0-16)
    private let incrementalSourceTypes: [(id: Int, name: String)] = [
        (0, "Mutation"),
        (1, "MouseMove"),
        (2, "MouseInteraction"),
        (3, "Scroll"),
        (4, "ViewportResize"),
        (5, "Input"),
        (6, "TouchMove"),
        (7, "MediaInteraction"),
        (8, "StyleSheetRule"),
        (9, "CanvasMutation"),
        (10, "Font"),
        (11, "Log"),
        (12, "Drag"),
        (13, "StyleDeclaration"),
        (14, "Selection"),
        (15, "AdoptedStyleSheet"),
        (16, "CustomElement"),
    ]

    private var hasActiveFilters: Bool {
        // Check if any event types are disabled
        let allTypesEnabled = enabledEventTypes.count == allEventTypes.count
        // Check if any incremental sources are disabled
        let allIncrementalSourcesEnabled =
            enabledIncrementalSources.count == incrementalSourceTypes.count
        // Check if any custom tags are disabled
        let allCustomTagsEnabled =
            allCustomTags.isEmpty || enabledCustomTags.count == allCustomTags.count
        // Check if timestamp filter is active
        let hasTimestampFilter = !timestampFilterValue.isEmpty
        // Check if node ID filter is active
        let hasNodeIdFilter = nodeIdFilter != nil

        return !allTypesEnabled || !allIncrementalSourcesEnabled || !allCustomTagsEnabled
            || hasTimestampFilter || hasNodeIdFilter
    }

    private var totalSegmentsDuration: String? {
        guard !segments.isEmpty else { return nil }

        let allTimestamps = segments.flatMap { segment in
            segment.events(useSortedOrder: useSortedOrder).map { $0.effectiveTimestamp }
        }

        guard let firstTimestamp = allTimestamps.min(),
            let lastTimestamp = allTimestamps.max(),
            firstTimestamp != lastTimestamp
        else {
            return nil
        }

        return formatDuration(lastTimestamp.timeIntervalSince(firstTimestamp))
    }

    private var parsedTimestampFilter: TimeInterval? {
        guard !timestampFilterValue.isEmpty,
            let value = Double(timestampFilterValue)
        else {
            return nil
        }

        // If value is greater than a reasonable timestamp in seconds (year 2020+),
        // assume it's in milliseconds and convert to seconds
        if value > 1_577_836_800_000 {
            return value / 1000
        } else {
            return value
        }
    }

    private var currentFilterCacheKey: String {
        "\(segments.count)-\(enabledEventTypes.sorted().joined())-\(enabledIncrementalSources.sorted().map { String($0) }.joined())-\(enabledCustomTags.sorted().joined())-\(timestampFilterOperator)-\(timestampFilterValue)-\(nodeIdFilter?.description ?? "")-\(nodeIdFilterAllReferences)"
    }

    private func eventReferencesNode(_ event: ReplayEvent, nodeId: Int, allReferences: Bool) -> Bool {
        // Recursively search through the event data for any occurrence of the node ID
        func searchForNodeId(in data: Any) -> Bool {
            if let dict = data as? [String: Any] {
                // Check if this object has an "id" field matching our target
                if let id = dict["id"] as? Int, id == nodeId {
                    return true
                }

                // If allReferences is enabled, also check other reference fields
                if allReferences {
                    // Common reference field patterns: parentId, nextId, previousId, etc.
                    for (key, value) in dict {
                        let lowerKey = key.lowercased()
                        if lowerKey.hasSuffix("id") || lowerKey == "id" {
                            if let refId = value as? Int, refId == nodeId {
                                return true
                            }
                        }
                    }
                }

                // Recursively search all values
                for (_, value) in dict {
                    if searchForNodeId(in: value) {
                        return true
                    }
                }
            } else if let array = data as? [Any] {
                // Search through array elements
                for item in array {
                    if searchForNodeId(in: item) {
                        return true
                    }
                }
            } else if let num = data as? Int, num == nodeId {
                // Direct number match
                return true
            }

            return false
        }

        return searchForNodeId(in: event.data)
    }

    private func findNodeIdPath(nodeId: Int, in data: Any, currentPath: [String] = []) -> [String]? {
        if let dict = data as? [String: Any] {
            // Check if this object contains an "id" field matching our target
            if let id = dict["id"] as? Int, id == nodeId {
                // Return the path to this parent object, not the id field
                return currentPath
            }

            // Recursively search all values
            for (key, value) in dict {
                let newPath = currentPath + [key]

                // Recursively search in nested structures
                if let foundPath = findNodeIdPath(nodeId: nodeId, in: value, currentPath: newPath) {
                    return foundPath
                }
            }
        } else if let array = data as? [Any] {
            for (index, item) in array.enumerated() {
                let newPath = currentPath + ["\(index)"]

                if let foundPath = findNodeIdPath(nodeId: nodeId, in: item, currentPath: newPath) {
                    return foundPath
                }
            }
        }

        return nil
    }

    private var filteredSegments: [ReplaySegment] {
        // Return cached result if key matches
        if currentFilterCacheKey == filterCacheKey {
            return cachedFilteredSegments
        }

        // Early return if no filters are active
        let hasEventTypeFilters = enabledEventTypes.count < allEventTypes.count
        let hasIncrementalSourceFilters =
            enabledIncrementalSources.count < incrementalSourceTypes.count
        let hasCustomTagFilters =
            !allCustomTags.isEmpty && enabledCustomTags.count < allCustomTags.count
        let hasTimestampFilter = parsedTimestampFilter != nil
        let hasNodeIdFilter = nodeIdFilter != nil

        if !hasEventTypeFilters && !hasIncrementalSourceFilters && !hasCustomTagFilters
            && !hasTimestampFilter && !hasNodeIdFilter
        {
            return segments
        }

        return segments.map { segment in
            // OPTIMIZATION: Store sortedEvents in local variable
            let sortedEvents = segment.sortedEvents
            let filteredEvents = sortedEvents.filter { event in
                // Apply event type filter - only show events whose type is enabled
                if hasEventTypeFilters {
                    let baseType = ContentView.baseTypeName(for: event.type)
                    if !enabledEventTypes.contains(baseType) {
                        return false
                    }
                }

                // Apply IncrementalSnapshot source filter if this is an IncrementalSnapshot
                // Only check if some sources are disabled
                if hasIncrementalSourceFilters && event.type == 3 {
                    if let source = event.data["source"] as? Int {
                        if !enabledIncrementalSources.contains(source) {
                            return false
                        }
                    }
                }

                // Apply Custom tag filter if this is a Custom event
                // Only check if some tags are disabled
                if !allCustomTags.isEmpty && allCustomTags.count != enabledCustomTags.count
                    && event.type == 5
                {
                    if let customType = extractCustomEventType(from: event.data) {
                        if !enabledCustomTags.contains(customType) {
                            return false
                        }
                    }
                }

                // Apply timestamp filter
                if let timestampFilter = parsedTimestampFilter {
                    let eventTimestamp = event.timestamp.timeIntervalSince1970
                    if timestampFilterOperator == ">" {
                        if eventTimestamp <= timestampFilter {
                            return false
                        }
                    } else {
                        if eventTimestamp >= timestampFilter {
                            return false
                        }
                    }
                }

                // Apply node ID filter
                if let nodeId = nodeIdFilter {
                    if !eventReferencesNode(
                        event, nodeId: nodeId, allReferences: nodeIdFilterAllReferences)
                    {
                        return false
                    }
                }

                return true
            }

            // Keep segment even if no events match - just show empty event list
            return ReplaySegment(
                id: segment.id, timestamp: segment.timestamp, events: filteredEvents)
        }
    }

    private func updateFilterCache() {
        let newKey = currentFilterCacheKey
        if newKey != filterCacheKey {
            // Invalidate cache first to force recomputation
            filterCacheKey = ""
            cachedFilteredSegments = []

            // Now recompute with new key
            cachedFilteredSegments = filteredSegments
            filterCacheKey = newKey
        }
    }

    var body: some View {
        Group {
            if segments.isEmpty {
                emptyOrLoadingView
            } else {
                replayView
            }
        }
        .toolbar {}
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 290, ideal: 390, max: 520)
        }
        .alert("Element Not Found", isPresented: $showHighlightError) {
            Button("OK") {}
        } message: {
            Text(highlightErrorMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = errorMessage {
                statusBar(message: errorMessage, isError: true)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Check if a text field has focus (to avoid interfering with text input)
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return event
                }

                // Cmd+F for search
                if event.modifierFlags.contains(.command)
                    && event.charactersIgnoringModifiers == "f"
                {
                    showGlobalSearch = true
                    searchFieldFocused = true
                    return nil
                }

                // Cmd+V for loading from clipboard
                if event.modifierFlags.contains(.command)
                    && event.charactersIgnoringModifiers == "v"
                {
                    loadFromClipboard()
                    return nil
                }

                // Arrow key navigation (only if no text field is focused)
                switch event.keyCode {
                case 126:  // Up arrow
                    selectPreviousEvent()
                    return nil
                case 125:  // Down arrow
                    selectNextEvent()
                    return nil
                case 123:  // Left arrow
                    selectPreviousSegment()
                    return nil
                case 124:  // Right arrow
                    selectNextSegment()
                    return nil
                default:
                    break
                }

                return event
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onChange(of: segments) {
            // Clear render state cache when data changes
            htmlRenderStateCache = [:]

            // Update event cache when segments change
            updateEventCache()

            // Update filter cache when segments change
            updateFilterCache()
            updateDisplayedSegmentCache()

            // Recompute event counts when segments change
            computeEventCounts()

            if !segments.isEmpty && selectedSegmentIDs.isEmpty {
                if let first = filteredSegments.first {
                    selectedSegmentIDs = [first.id]
                }
                selectedEvent = displayedSegment?.events(useSortedOrder: useSortedOrder).first
            }
        }
        .onChange(of: enabledEventTypes) {
            updateFilterCache()
            updateDisplayedSegmentCache()
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: enabledIncrementalSources) {
            updateFilterCache()
            updateDisplayedSegmentCache()
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: timestampFilterValue) {
            updateFilterCache()
            updateDisplayedSegmentCache()
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: timestampFilterOperator) {
            updateFilterCache()
            updateDisplayedSegmentCache()
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: nodeIdFilter) {
            updateFilterCache()
            updateDisplayedSegmentCache()
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: selectedSegmentIDs) {
            updateDisplayedSegmentCache()
        }
        .onChange(of: globalSearchQuery) {
            performGlobalSearch()
        }
        .safeAreaInset(edge: .top) {
            if showGlobalSearch {
                globalSearchBar
            }
        }
    }

    // MARK: - View Components

    private var globalSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search all segments and events...", text: $globalSearchQuery)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onSubmit {
                    if !searchMatches.isEmpty {
                        nextSearchMatch()
                    }
                }

            if !globalSearchQuery.isEmpty {
                Text("\(currentSearchIndex + 1) of \(searchMatches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: previousSearchMatch) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(searchMatches.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button(action: nextSearchMatch) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(searchMatches.isEmpty)
                .keyboardShortcut("g", modifiers: [.command])

                Button(action: {
                    globalSearchQuery = ""
                    searchMatches = []
                    currentSearchIndex = 0
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                showGlobalSearch = false
                globalSearchQuery = ""
                searchMatches = []
                currentSearchIndex = 0
            }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }

    private var emptyOrLoadingView: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading replay…")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView()
            }
        }
        .navigationTitle("Replay Debugger")
    }

    private var replayView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 280, ideal: 380, max: 500)
        } content: {
            eventsListContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
        } detail: {
            detailContent
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
    }

    private var sidebarContent: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedSegmentIDs) {
                ForEach(Array(filteredSegments.enumerated()), id: \.element.id) { index, segment in
                    segmentRowWithDivider(segment: segment, index: index)
                        .id(segment.id)
                }
            }
            .listStyle(.sidebar)
            .environment(\.controlActiveState, .key)
            .onChange(of: selectedSegmentIDs) {
                if let segment = primarySelectedSegment {
                    selectedEvent = segment.events(useSortedOrder: useSortedOrder).first
                    if shouldScrollToSelection {
                        withAnimation {
                            proxy.scrollTo(segment.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle("Segments")
        .navigationSubtitle(segmentSubtitle)
    }

    private var userProfileMenu: some View {
        Menu {
            if let profile = authService.userProfile {
                Text(profile.email)
                Divider()
            }
            Button(action: { authService.logout() }) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 8) {
                UserAvatarView(profile: authService.userProfile, size: 22)
                if let profile = authService.userProfile {
                    Text(profile.name)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var segmentSubtitle: String {
        let count = "\(filteredSegments.count) segments"
        if let duration = totalSegmentsDuration {
            return "\(count) • \(duration)"
        }
        return count
    }

    @ViewBuilder
    private func segmentRowWithDivider(segment: ReplaySegment, index: Int) -> some View {
        SegmentRowView(
            segment: segment,
            isSelected: selectedSegmentIDs.contains(segment.id),
            originalSegment: segments.first(where: { $0.id == segment.id }),
            previousSegment: index > 0 ? segments[index - 1] : nil,
            onTimestampClick: { timestamp in
                setTimestampFilter(timestamp)
            },
            selectedCount: selectedSegmentIDs.contains(segment.id) ? selectedSegmentIDs.count : 1,
            onExport: { preserveSegments in
                if selectedSegmentIDs.contains(segment.id) {
                    exportSegments(selectedSegments, preserveSegments: preserveSegments)
                } else {
                    exportSegments([segment], preserveSegments: false)
                }
            },
            onCopyToClipboard: { preserveSegments in
                if selectedSegmentIDs.contains(segment.id) {
                    copySegmentsToClipboard(selectedSegments, preserveSegments: preserveSegments)
                } else {
                    copySegmentsToClipboard([segment], preserveSegments: false)
                }
            }
        )
        .tag(segment.id)
    }

    private func exportSegments(_ segments: [ReplaySegment], preserveSegments: Bool) {
        guard !segments.isEmpty else { return }
        SegmentExporter.exportToFile(segments, preserveSegments: preserveSegments)
    }

    private func copySegmentsToClipboard(_ segments: [ReplaySegment], preserveSegments: Bool) {
        guard !segments.isEmpty else { return }
        SegmentExporter.copyToClipboard(segments, preserveSegments: preserveSegments)
    }

    private var eventsListContent: some View {
        Group {
            if let segment = displayedSegment {
                eventsListView(for: segment)
            } else {
                ContentUnavailableView(
                    "No Segment Selected",
                    systemImage: "square.stack.3d.up",
                    description: Text("Select a segment from the sidebar to view its events")
                )
            }
        }
    }

    private func eventsListView(for segment: ReplaySegment) -> some View {
        let events = segment.events(useSortedOrder: useSortedOrder)
        let eventsArray = Array(events.enumerated())

        return ScrollViewReader { proxy in
            Group {
                if events.isEmpty && hasActiveFilters {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "tray")
                    } description: {
                        Text("No events match the current filters")
                    } actions: {
                        Button("Clear All Filters") {
                            clearAllFilters()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $selectedEvent) {
                        ForEach(eventsArray, id: \.element.id) { index, event in
                            let previousEvent: ReplayEvent? = index > 0 ? events[index - 1] : nil
                            EventRowView(
                                event: event,
                                isSelected: selectedEvent?.id == event.id,
                                previousEvent: previousEvent,
                                onTimestampClick: { timestamp in
                                    setTimestampFilter(timestamp)
                                }
                            )
                            .tag(event)
                            .id(event.id)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.controlActiveState, .key)
                    .onChange(of: selectedEvent) {
                        if let event = selectedEvent {
                            // Only scroll if this selection is from search
                            if shouldScrollToSelection {
                                withAnimation {
                                    proxy.scrollTo(event.id, anchor: .center)
                                }
                                // Reset flag after scrolling
                                shouldScrollToSelection = false
                            }
                        }
                    }
                    .navigationTitle("Events")
                    .navigationSubtitle("\(events.count) events")

                }
            }
        }
    }

    private var detailContent: some View {
        PersistentVSplitView(autosaveName: "main-detail-split") {
            // Top pane: JSON Inspector
            Group {
                if let selectedEvent = selectedEvent {
                    VStack(spacing: 0) {
                        // Header
                        HStack(alignment: .center) {
                            Text("Event Details")
                                .font(.headline)

                            Spacer()

                            if let timeFromStart = timeFromStart(for: selectedEvent) {
                                Text(timeFromStart)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .foregroundColor(.secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            Text(ContentView.displayName(for: selectedEvent))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding()

                        JSONInspectorView(
                            data: selectedEvent.data,
                            onHighlightElement: highlightElement,
                            onFindInSource: findInSource,
                            onFilterForNode: filterForNode,
                            onFilterForNodeAllReferences: filterForNodeAllReferences,
                            highlightPath: {
                                // Priority: search match > node filter
                                if let searchMatch = currentSearchMatch,
                                    searchMatch.matchType == .eventData
                                {
                                    return searchMatch.jsonPath
                                } else if let nodeId = nodeIdFilter {
                                    return findNodeIdPath(nodeId: nodeId, in: selectedEvent.data)
                                }
                                return nil
                            }(),
                            searchQuery: currentSearchMatch?.matchType == .eventData
                                ? globalSearchQuery
                                : (nodeIdFilter != nil ? "\(nodeIdFilter!)" : nil)
                        )
                        .id(selectedEvent.id)
                    }
                } else {
                    ContentUnavailableView(
                        "No Event Selected",
                        systemImage: "calendar.badge.clock",
                        description: Text("Select an event to view its details")
                    )
                }
            }
            .frame(minHeight: 100)
        } bottom: {
            // Bottom pane: HTML Renderer
            Group {
                if let eventIndex = selectedEventGlobalIndex {
                    HTMLRenderPanel(
                        events: allEvents,
                        selectedEventIndex: eventIndex,
                        fullSnapshotIndices: fullSnapshotIndices,
                        metaIndices: metaIndices,
                        renderStateCache: $htmlRenderStateCache,
                        cacheInterval: cacheInterval,
                        highlightedNodeId: $highlightedNodeId,
                        onHighlightError: showHighlightErrorAlert,
                        showSource: $showHTMLSource,
                        sourceSearchQuery: $htmlSourceSearchQuery
                    )
                } else {
                    VStack {
                        ProgressView()
                        Text("Loading HTML renderer...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                userProfileMenu
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { loadFromClipboard() }) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(isLoading)
                .help("Load replay from clipboard: Sentry URL, cURL, or JSON (⌘V)")

                Button(action: { showInspector.toggle() }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundColor(hasActiveFilters ? .accentColor : nil)
                }
                .help("Show filter inspector")
            }
        }
    }

    /// Flattened array of all events from all segments (cached for performance)
    private var allEvents: [ReplayEvent] {
        return cachedAllEvents
    }

    /// Update cache and segment boundaries
    /// Note: Always uses sorted (chronological) order for HTML rendering correctness
    private func updateEventCache() {
        // HTML renderer MUST use chronologically sorted events
        cachedAllEvents = segments.flatMap { $0.sortedEvents }
        cachedAllEventsSegmentCount = segments.count

        // Also update segment boundaries and event type indices
        var boundaries: [Int] = [0]
        var cumulative = 0
        var fullSnapshots: [Int] = []
        var metas: [Int] = []

        for segment in segments {
            // OPTIMIZATION: Always use sorted events for HTML renderer - stored in local variable
            let events = segment.sortedEvents

            // Build indices for FullSnapshot and Meta events
            for (localIndex, event) in events.enumerated() {
                let globalIndex = cumulative + localIndex
                if event.type == 2 {  // FullSnapshot
                    fullSnapshots.append(globalIndex)
                } else if event.type == 4 {  // Meta
                    metas.append(globalIndex)
                }
            }

            cumulative += events.count
            boundaries.append(cumulative)
        }

        segmentBoundaries = boundaries
        fullSnapshotIndices = fullSnapshots
        metaIndices = metas
    }

    /// Global index of the selected event in the flattened events array
    /// Note: Uses sortedEvents to match the allEvents array used by HTML renderer
    private var selectedEventGlobalIndex: Int? {
        guard let selectedEvent = selectedEvent,
            let primarySegment = primarySelectedSegment
        else {
            return nil
        }

        // Find the original segment index by matching segment ID
        guard let originalSegmentIndex = segments.firstIndex(where: { $0.id == primarySegment.id })
        else {
            return nil
        }

        // Find the event's position within the sorted segment events
        // Must use sortedEvents to match allEvents which always uses sorted order
        let originalSegmentEvents = segments[originalSegmentIndex].sortedEvents
        guard
            let eventIndexInSegment = originalSegmentEvents.firstIndex(where: {
                $0.id == selectedEvent.id && $0.timestamp == selectedEvent.timestamp
            })
        else {
            return nil
        }

        // O(1) lookup using pre-computed segment boundaries
        guard originalSegmentIndex < segmentBoundaries.count else {
            return nil
        }
        let globalIndex = segmentBoundaries[originalSegmentIndex] + eventIndexInSegment

        return globalIndex
    }

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            // Clear filters button (always shown, disabled when no filters)
            HStack {
                Button(action: clearAllFilters) {
                    Label("Clear All Filters", systemImage: "xmark.circle")
                }
                .disabled(!hasActiveFilters)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Form {
                // 1. Display Options
                Section("Display Options") {
                    Toggle("Use Sorted Order", isOn: $useSortedOrder)
                }

                // 2. Node ID Filter
                Section("Node Filter") {
                    HStack {
                        ZStack(alignment: .trailing) {
                            TextField("Node ID", text: $nodeIdFilterText)
                                .textFieldStyle(.roundedBorder)
                                .padding(.trailing, !nodeIdFilterText.isEmpty ? 24 : 0)
                                .onSubmit {
                                    // Only update filter when user presses Enter
                                    if nodeIdFilterText.isEmpty {
                                        nodeIdFilter = nil
                                    } else if let intValue = Int(nodeIdFilterText) {
                                        nodeIdFilter = intValue
                                    }
                                }

                            if !nodeIdFilterText.isEmpty {
                                Button(action: {
                                    nodeIdFilterText = ""
                                    nodeIdFilter = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.small)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onChange(of: nodeIdFilter) { _, newValue in
                        // Sync text field when filter changes externally (e.g., from context menu)
                        if let newValue = newValue {
                            nodeIdFilterText = String(newValue)
                        } else if nodeIdFilterText.isEmpty == false {
                            // Only clear text if it's not already empty
                            nodeIdFilterText = ""
                        }
                    }

                    Toggle("All References", isOn: $nodeIdFilterAllReferences)
                }

                // 3. Time Filter
                Section("Time Filter") {
                    HStack {
                        Text("Direction")
                        Spacer()
                        Picker("Operator", selection: $timestampFilterOperator) {
                            Text("After").tag(">")
                            Text("Before").tag("<")
                        }
                        .labelsHidden()
                    }

                    ZStack(alignment: .trailing) {
                        TextField("Timestamp", text: $timestampFilterText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.trailing, !timestampFilterText.isEmpty ? 24 : 0)
                            .onSubmit {
                                // Only update filter when user presses Enter
                                timestampFilterValue = timestampFilterText
                            }
                            .onChange(of: timestampFilterValue) { _, newValue in
                                // Sync text field when filter changes externally
                                if timestampFilterText != newValue {
                                    timestampFilterText = newValue
                                }
                            }

                        if !timestampFilterText.isEmpty {
                            Button(action: {
                                timestampFilterText = ""
                                timestampFilterValue = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 4. Event Filters
                Section("Event Type Filters") {
                    ForEach(allEventTypes, id: \.self) { eventType in
                        Toggle(
                            isOn: Binding(
                                get: { enabledEventTypes.contains(eventType) },
                                set: { isEnabled in
                                    if isEnabled {
                                        enabledEventTypes.insert(eventType)
                                    } else {
                                        enabledEventTypes.remove(eventType)
                                    }
                                }
                            )
                        ) {
                            HStack {
                                Text(eventType)
                                Spacer()
                                let count = eventTypeCounts[eventType] ?? 0
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(count > 0 ? .white : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(
                                                count > 0
                                                    ? Color.secondary : Color.secondary.opacity(0.2)
                                            )
                                    )
                            }
                        }
                    }
                }

                // IncrementalSnapshot source filters (only shown when IncrementalSnapshot is enabled)
                if enabledEventTypes.contains("IncrementalSnapshot") {
                    Section("IncrementalSnapshot Sources") {
                        ForEach(incrementalSourceTypes, id: \.id) { source in
                            Toggle(
                                isOn: Binding(
                                    get: { enabledIncrementalSources.contains(source.id) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            enabledIncrementalSources.insert(source.id)
                                        } else {
                                            enabledIncrementalSources.remove(source.id)
                                        }
                                    }
                                )
                            ) {
                                HStack {
                                    Text(source.name)
                                    Spacer()
                                    let count = incrementalSourceCounts[source.id] ?? 0
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(count > 0 ? .white : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    count > 0
                                                        ? Color.secondary
                                                        : Color.secondary.opacity(0.2))
                                        )
                                }
                            }
                        }
                    }
                }

                // Custom event tag filters (only shown when Custom is enabled)
                if enabledEventTypes.contains("Custom") && !allCustomTags.isEmpty {
                    Section("Custom Event Tags") {
                        ForEach(allCustomTags, id: \.self) { tag in
                            Toggle(
                                isOn: Binding(
                                    get: { enabledCustomTags.contains(tag) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            enabledCustomTags.insert(tag)
                                        } else {
                                            enabledCustomTags.remove(tag)
                                        }
                                    }
                                )
                            ) {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    let count = customTagCounts[tag] ?? 0
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(count > 0 ? .white : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    count > 0
                                                        ? Color.secondary
                                                        : Color.secondary.opacity(0.2))
                                        )
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Replay")
        .onAppear {
            computeEventCounts()
        }
    }

    private func clearAllFilters() {
        enabledEventTypes = Set(allEventTypes)
        enabledIncrementalSources = Set(incrementalSourceTypes.map { $0.id })
        enabledCustomTags = Set(allCustomTags)
        timestampFilterText = ""
        timestampFilterValue = ""
        nodeIdFilterText = ""
        nodeIdFilter = nil
    }

    private func computeEventCounts() {
        var typeCounts: [String: Int] = [:]
        var sourceCounts: [Int: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var tags: Set<String> = []

        for segment in segments {
            for event in segment.sortedEvents {
                // Count by base event type
                let baseType = ContentView.baseTypeName(for: event.type)
                typeCounts[baseType, default: 0] += 1

                // Count by incremental source if it's an IncrementalSnapshot
                if event.type == 3, let source = event.data["source"] as? Int {
                    sourceCounts[source, default: 0] += 1
                }

                // Count by custom event type if it's a Custom event
                if event.type == 5 {
                    if let customType = extractCustomEventType(from: event.data) {
                        tagCounts[customType, default: 0] += 1
                        tags.insert(customType)
                    }
                }
            }
        }

        eventTypeCounts = typeCounts
        incrementalSourceCounts = sourceCounts
        customTagCounts = tagCounts
        allCustomTags = Array(tags).sorted()

        // Initialize enabled custom tags with all tags if empty
        if enabledCustomTags.isEmpty {
            enabledCustomTags = tags
        }
    }

    private func extractCustomEventType(from eventData: [String: Any]) -> String? {
        guard let tag = eventData["tag"] as? String else {
            return nil
        }

        switch tag {
        case "performanceSpan":
            if let payload = eventData["payload"] as? [String: Any],
                let op = payload["op"] as? String
            {
                return op
            }
        case "breadcrumb":
            if let payload = eventData["payload"] as? [String: Any],
                let category = payload["category"] as? String
            {
                return category
            }
        default:
            return tag
        }

        return tag
    }

    private func highlightElement(nodeId: Int) {
        highlightedNodeId = nodeId
        showHighlightError = false
    }

    private func findInSource(nodeId: Int) {
        // Switch to Source tab
        showHTMLSource = true
        // Search for the node ID in HTML
        htmlSourceSearchQuery = "data-rr-id=\"\(nodeId)\""
    }

    private func filterForNode(nodeId: Int) {
        nodeIdFilter = nodeId
        nodeIdFilterAllReferences = false
        showInspector = true
    }

    private func filterForNodeAllReferences(nodeId: Int) {
        nodeIdFilter = nodeId
        nodeIdFilterAllReferences = true
        showInspector = true
    }

    private func showHighlightErrorAlert(message: String) {
        highlightErrorMessage = message
        showHighlightError = true
    }

    private func statusBar(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .red : .blue)

            Text(message)
                .font(.callout)

            Spacer()

            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Color.red.opacity(0.9) : Color.blue.opacity(0.9))
    }

    private func timeFromStart(for event: ReplayEvent) -> String? {
        guard !allEvents.isEmpty else { return nil }
        let firstEvent = allEvents[0]
        let timeDiff = event.effectiveTimestamp.timeIntervalSince(firstEvent.effectiveTimestamp)

        // Format as +MM:SS.mmm
        let minutes = Int(timeDiff) / 60
        let seconds = Int(timeDiff) % 60
        let milliseconds = Int((timeDiff.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "+%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private func updateSelectedSegmentAfterFilter() {
        guard !selectedSegmentIDs.isEmpty else { return }

        if let displayedSegment = displayedSegment {
            selectedEvent = displayedSegment.events(useSortedOrder: useSortedOrder).first
        }
    }

    // MARK: - Global Search Functions

    private func findJSONPath(for query: String, in data: Any, currentPath: [String] = [])
        -> [String]?
    {
        let queryLower = query.lowercased()

        if let dict = data as? [String: Any] {
            for (key, value) in dict {
                let newPath = currentPath + [key]

                // Check if the key or value matches
                if key.lowercased().contains(queryLower) {
                    return newPath
                }

                if let stringValue = value as? String, stringValue.lowercased().contains(queryLower) {
                    return newPath
                }

                if let numberValue = value as? NSNumber,
                    "\(numberValue)".lowercased().contains(queryLower)
                {
                    return newPath
                }

                // Recursively search in nested structures
                if let foundPath = findJSONPath(for: query, in: value, currentPath: newPath) {
                    return foundPath
                }
            }
        } else if let array = data as? [Any] {
            for (index, item) in array.enumerated() {
                let newPath = currentPath + ["\(index)"]

                if let foundPath = findJSONPath(for: query, in: item, currentPath: newPath) {
                    return foundPath
                }
            }
        } else if let stringValue = data as? String, stringValue.lowercased().contains(queryLower) {
            return currentPath
        } else if let numberValue = data as? NSNumber,
            "\(numberValue)".lowercased().contains(queryLower)
        {
            return currentPath
        }

        return nil
    }

    private func performGlobalSearch() {
        searchMatches = []
        currentSearchIndex = 0
        currentSearchMatch = nil

        guard !globalSearchQuery.isEmpty else { return }

        let query = globalSearchQuery.lowercased()

        for segment in segments {
            for event in segment.events(useSortedOrder: useSortedOrder) {
                // Search in event data
                if let jsonData = try? JSONSerialization.data(
                    withJSONObject: event.data, options: []),
                    let jsonString = String(data: jsonData, encoding: .utf8),
                    jsonString.lowercased().contains(query)
                {
                    // Find the specific path in the JSON where the match occurred
                    let path = findJSONPath(for: query, in: event.data)
                    searchMatches.append(
                        SearchMatch(
                            segmentId: segment.id,
                            eventId: event.id,
                            matchText: "Event data",
                            jsonPath: path,
                            matchType: .eventData
                        ))
                }

                // Search in event ID
                if event.id.lowercased().contains(query) {
                    searchMatches.append(
                        SearchMatch(
                            segmentId: segment.id,
                            eventId: event.id,
                            matchText: "Event ID: \(event.id)",
                            jsonPath: nil,
                            matchType: .eventId
                        ))
                }

                // Search in event type
                let eventType = ContentView.displayName(for: event)
                if eventType.lowercased().contains(query) {
                    searchMatches.append(
                        SearchMatch(
                            segmentId: segment.id,
                            eventId: event.id,
                            matchText: "Event type: \(eventType)",
                            jsonPath: nil,
                            matchType: .eventType
                        ))
                }
            }

            // Search in segment ID
            if segment.id.lowercased().contains(query) {
                if let firstEvent = segment.events(useSortedOrder: useSortedOrder).first {
                    searchMatches.append(
                        SearchMatch(
                            segmentId: segment.id,
                            eventId: firstEvent.id,
                            matchText: "Segment ID: \(segment.id)",
                            jsonPath: nil,
                            matchType: .eventId
                        ))
                }
            }
        }

        // Select first match
        if !searchMatches.isEmpty {
            selectSearchMatch(at: 0)
        }
    }

    private func nextSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchMatches.count
        selectSearchMatch(at: currentSearchIndex)
    }

    private func previousSearchMatch() {
        guard !searchMatches.isEmpty else { return }
        currentSearchIndex =
            currentSearchIndex > 0 ? currentSearchIndex - 1 : searchMatches.count - 1
        selectSearchMatch(at: currentSearchIndex)
    }

    private func selectSearchMatch(at index: Int) {
        guard index < searchMatches.count else { return }
        let match = searchMatches[index]
        currentSearchMatch = match

        // Find and select the segment
        if let segment = segments.first(where: { $0.id == match.segmentId }) {
            shouldScrollToSelection = true
            selectedSegmentIDs = [segment.id]

            // Find and select the event
            let events = segment.events(useSortedOrder: useSortedOrder)
            if let event = events.first(where: { $0.id == match.eventId }) {
                selectedEvent = event
            }
        }
    }

    private func selectNextEvent() {
        guard let currentEvent = selectedEvent,
            let segment = displayedSegment
        else { return }

        let events = segment.events(useSortedOrder: useSortedOrder)
        if let currentIndex = events.firstIndex(where: { $0.id == currentEvent.id }),
            currentIndex + 1 < events.count
        {
            selectedEvent = events[currentIndex + 1]
        }
    }

    private func selectPreviousEvent() {
        guard let currentEvent = selectedEvent,
            let segment = displayedSegment
        else { return }

        let events = segment.events(useSortedOrder: useSortedOrder)
        if let currentIndex = events.firstIndex(where: { $0.id == currentEvent.id }),
            currentIndex > 0
        {
            selectedEvent = events[currentIndex - 1]
        }
    }

    private func selectNextSegment() {
        guard let currentSegment = primarySelectedSegment else {
            // If no segment selected, select first
            if let first = filteredSegments.first {
                selectedSegmentIDs = [first.id]
            }
            return
        }

        if let currentIndex = filteredSegments.firstIndex(where: { $0.id == currentSegment.id }),
            currentIndex + 1 < filteredSegments.count
        {
            selectedSegmentIDs = [filteredSegments[currentIndex + 1].id]
        }
    }

    private func selectPreviousSegment() {
        guard let currentSegment = primarySelectedSegment else {
            // If no segment selected, select last
            if let last = filteredSegments.last {
                selectedSegmentIDs = [last.id]
            }
            return
        }

        if let currentIndex = filteredSegments.firstIndex(where: { $0.id == currentSegment.id }),
            currentIndex > 0
        {
            selectedSegmentIDs = [filteredSegments[currentIndex - 1].id]
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sentry-replay-debugger", url.host == "open" else { return }
        loadFromClipboard()
    }

    private func loadFromJSON(_ jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            errorMessage = "Invalid JSON encoding"
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)

            if let outerArray = jsonObject as? [Any] {
                var parsedSegments: [ReplaySegment] = []

                for (index, item) in outerArray.enumerated() {
                    if let eventsArray = item as? [[String: Any]] {
                        let segment = createSegmentFromEvents(eventsArray, id: "segment-\(index)")
                        parsedSegments.append(segment)
                    }
                }

                if !parsedSegments.isEmpty {
                    segments = parsedSegments
                    errorMessage = nil
                } else if let eventsArray = jsonObject as? [[String: Any]] {
                    segments = [createSegmentFromEvents(eventsArray, id: "segment-0")]
                    errorMessage = nil
                } else if let segmentsArray = jsonObject as? [[String: Any]] {
                    segments = parseSegmentsFromClipboard(segmentsArray)
                    errorMessage = nil
                }
            } else if let singleSegment = jsonObject as? [String: Any] {
                segments = parseSegmentsFromClipboard([singleSegment])
                errorMessage = nil
            } else {
                errorMessage = "Invalid JSON format - expected segment or event data"
            }
        } catch {
            errorMessage = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func fetchReplayFromURL(_ url: String) {
        let urlComponents: SentryURLComponents
        do {
            urlComponents = try SentryURLParser.parse(url: url)
        } catch {
            errorMessage = "Invalid Sentry replay URL: \(error.localizedDescription)"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedSegments = try await SentryAPIService.shared.fetchReplaySegments(
                    orgSlug: urlComponents.orgSlug,
                    projectId: urlComponents.projectId,
                    replayId: urlComponents.replayId
                )

                self.segments = fetchedSegments
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to fetch replay data: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func loadFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let clipboardText = pasteboard.string(forType: .string) else {
            errorMessage = "No text found in clipboard"
            return
        }

        let trimmedText = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if clipboard contains a Sentry replay URL
        do {
            _ = try SentryURLParser.parse(url: trimmedText)
            fetchReplayFromURL(trimmedText)
            return
        } catch let error as SentryURLParseError {
            // Recognized as a Sentry URL but missing required parts
            if error != .unrecognizedFormat && error != .invalidURL {
                errorMessage = error.localizedDescription
                return
            }
        } catch {
            // Not a recognizable Sentry URL; fall through to other clipboard formats.
        }

        // Check if clipboard contains a cURL command
        if trimmedText.lowercased().hasPrefix("curl") {
            loadFromCURLCommand(trimmedText)
            return
        }

        loadFromJSON(clipboardText)
    }

    private func loadFromCURLCommand(_ curlCommand: String) {
        Task {
            do {
                isLoading = true
                errorMessage = nil

                NSLog("📋 Loading from CURL command")
                let fetchedSegments = try await SentryAPIService.shared.fetchReplaySegmentsFromCURL(
                    curlCommand)

                segments = fetchedSegments
                isLoading = false
                errorMessage = nil
                NSLog("✅ Successfully loaded \(fetchedSegments.count) segments from CURL")
            } catch {
                isLoading = false
                errorMessage = "Failed to load from CURL: \(error.localizedDescription)"
                NSLog("❌ CURL load failed: \(error)")
            }
        }
    }

    private func createSegmentFromEvents(_ eventsArray: [[String: Any]], id: String)
        -> ReplaySegment
    {
        let events = eventsArray.enumerated().map { index, eventData in
            let eventId = eventData["id"] as? String ?? "event-\(index)"
            let type = parseEventType(eventData["type"])
            let timestamp = parseTimestamp(from: eventData["timestamp"]) ?? Date()

            let data = eventData["data"] as? [String: Any] ?? eventData

            return ReplayEvent(id: eventId, type: type, timestamp: timestamp, data: data)
        }

        let timestamp = events.first?.timestamp ?? Date()
        return ReplaySegment(id: id, timestamp: timestamp, events: events)
    }

    private func parseSegmentsFromClipboard(_ jsonArray: [[String: Any]]) -> [ReplaySegment] {
        return jsonArray.compactMap { segmentData in
            guard let id = segmentData["id"] as? String ?? segmentData["segment_id"] as? String
            else {
                return nil
            }

            let timestamp = parseTimestamp(from: segmentData["timestamp"]) ?? Date()
            let events = parseEventsFromSegmentData(segmentData)

            return ReplaySegment(id: id, timestamp: timestamp, events: events)
        }
    }

    private func parseEventsFromSegmentData(_ segmentData: [String: Any]) -> [ReplayEvent] {
        if let eventsArray = segmentData["events"] as? [[String: Any]] {
            return eventsArray.enumerated().compactMap { index, eventData in
                let id = eventData["id"] as? String ?? "event-\(index)"
                let type = parseEventType(eventData["type"])
                let timestamp = parseTimestamp(from: eventData["timestamp"]) ?? Date()

                let data = eventData["data"] as? [String: Any] ?? eventData

                return ReplayEvent(id: id, type: type, timestamp: timestamp, data: data)
            }
        } else {
            var data = segmentData
            data.removeValue(forKey: "id")
            data.removeValue(forKey: "segment_id")

            return [ReplayEvent(id: "event-1", type: -1, timestamp: Date(), data: data)]
        }
    }

    private func parseTimestamp(from value: Any?) -> Date? {
        ReplayTimestamp.date(from: value)
    }

    private func parseEventType(_ value: Any?) -> Int {
        guard let typeValue = value else { return -1 }

        // Handle both string and numeric types
        if let stringValue = typeValue as? String, let intValue = Int(stringValue) {
            return intValue
        } else if let intValue = typeValue as? Int {
            return intValue
        }

        return -1
    }

    // Display name for event type in UI
    static func displayName(for event: ReplayEvent) -> String {
        switch event.type {
        case 0: return "DomContentLoaded"
        case 1: return "Load"
        case 2: return "FullSnapshot"
        case 3: return incrementalSnapshotDisplayName(eventData: event.data)
        case 4: return "Meta"
        case 5: return customEventDisplayName(eventData: event.data)
        case 6: return "Plugin"
        default: return "unknown(\(event.type))"
        }
    }

    // Base event type name for filtering
    static func baseTypeName(for eventType: Int) -> String {
        switch eventType {
        case 0: return "DomContentLoaded"
        case 1: return "Load"
        case 2: return "FullSnapshot"
        case 3: return "IncrementalSnapshot"
        case 4: return "Meta"
        case 5: return "Custom"
        case 6: return "Plugin"
        default: return "unknown"
        }
    }

    static func incrementalSnapshotDisplayName(eventData: [String: Any]) -> String {
        // eventData is already the inner "data" object from the event
        guard let source = eventData["source"] else {
            return "IncrementalSnapshot"
        }

        // Handle numeric source values
        let sourceNumber: Int
        if let stringValue = source as? String, let intValue = Int(stringValue) {
            sourceNumber = intValue
        } else if let intValue = source as? Int {
            sourceNumber = intValue
        } else {
            return "IncrementalSnapshot"
        }

        // Map to rrweb IncrementalSource enum
        switch sourceNumber {
        case 0:
            // For Mutation events, don't include count in name (shown as badge)
            return "Mutation"
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
        default: return "IncrementalSnapshot"
        }
    }

    static func calculateMutationCount(eventData: [String: Any]) -> Int {
        var count = 0

        if let adds = eventData["adds"] as? [[String: Any]] {
            count += adds.count
        }
        if let removes = eventData["removes"] as? [[String: Any]] {
            count += removes.count
        }
        if let attributes = eventData["attributes"] as? [[String: Any]] {
            count += attributes.count
        }
        if let texts = eventData["texts"] as? [[String: Any]] {
            count += texts.count
        }

        return count
    }

    static func customEventDisplayName(eventData: [String: Any]) -> String {
        // eventData is already the inner "data" object from the event
        guard let tag = eventData["tag"] as? String else {
            return "Custom"
        }

        switch tag {
        case "performanceSpan":
            if let payload = eventData["payload"] as? [String: Any],
                let op = payload["op"] as? String
            {
                return op
            }
        case "breadcrumb":
            if let payload = eventData["payload"] as? [String: Any],
                let category = payload["category"] as? String
            {
                return category
            }
        default:
            break
        }

        return tag
    }

    private var currentDisplayedSegmentCacheKey: String? {
        guard let primarySegment = primarySelectedSegment else { return nil }
        return "\(primarySegment.id)-\(currentFilterCacheKey)"
    }

    private var displayedSegment: ReplaySegment? {
        guard let primarySegment = primarySelectedSegment else {
            return nil
        }

        // Return cached result if segment ID and filters match
        if let cacheKey = currentDisplayedSegmentCacheKey,
            cachedDisplayedSegmentId == cacheKey
        {
            return cachedDisplayedSegment
        }

        // Lookup segment in filtered list
        return filteredSegments.first(where: { $0.id == primarySegment.id })
    }

    private func updateDisplayedSegmentCache() {
        if let cacheKey = currentDisplayedSegmentCacheKey {
            if cachedDisplayedSegmentId != cacheKey {
                // Invalidate cache first to force recomputation
                cachedDisplayedSegmentId = nil
                cachedDisplayedSegment = nil

                // Now recompute with new key
                cachedDisplayedSegment = displayedSegment
                cachedDisplayedSegmentId = cacheKey
            }
        } else {
            // Clear cache when no segment selected
            cachedDisplayedSegment = nil
            cachedDisplayedSegmentId = nil
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, minutes)
        }
    }
}

#Preview {
    ContentView()
}
