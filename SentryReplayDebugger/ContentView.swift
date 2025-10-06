import SwiftUI
import AppKit

struct SearchMatch: Identifiable {
    let id = UUID()
    let segmentId: String
    let eventId: String
    let matchText: String
}

struct ContentView: View {
    @State private var replayURL: String = ""
    @State private var segments: [ReplaySegment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedEventTypeFilter: String = "All"
    @State private var invertFilter = false
    @State private var selectedSegment: ReplaySegment?
    @State private var selectedEvent: ReplayEvent?
    @State private var useSortedOrder = true
    @State private var timestampFilterOperator: String = ">"
    @State private var timestampFilterValue: String = ""
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Global search
    @State private var showGlobalSearch = false
    @State private var globalSearchQuery: String = ""
    @State private var searchMatches: [SearchMatch] = []
    @State private var currentSearchIndex: Int = 0
    @FocusState private var searchFieldFocused: Bool

    // Performance: Cache for allEvents
    @State private var cachedAllEvents: [ReplayEvent] = []
    @State private var cachedAllEventsSegmentCount: Int = 0
    @State private var cachedAllEventsSortOrder: Bool = true

    // Performance: Pre-computed segment boundaries
    @State private var segmentBoundaries: [Int] = []

    // Performance: Pre-computed indices for FullSnapshot (type 2) and Meta (type 4) events
    @State private var fullSnapshotIndices: [Int] = []
    @State private var metaIndices: [Int] = []

    func setTimestampFilter(_ timestamp: Date) {
        timestampFilterValue = String(format: "%.3f", timestamp.timeIntervalSince1970)
    }
    
    private let eventTypes = ["All", "DomContentLoaded", "Load", "FullSnapshot", "IncrementalSnapshot", "Meta", "Custom", "Plugin"]
    
    private var totalSegmentsDuration: String? {
        guard !segments.isEmpty else { return nil }
        
        let allTimestamps = segments.flatMap { segment in
            segment.events(useSortedOrder: useSortedOrder).map { $0.timestamp }
        }
        
        guard let firstTimestamp = allTimestamps.min(),
              let lastTimestamp = allTimestamps.max(),
              firstTimestamp != lastTimestamp else {
            return nil
        }
        
        return formatDuration(lastTimestamp.timeIntervalSince(firstTimestamp))
    }
    
    private var parsedTimestampFilter: TimeInterval? {
        guard !timestampFilterValue.isEmpty,
              let value = Double(timestampFilterValue) else {
            return nil
        }
        
        // If value is greater than a reasonable timestamp in seconds (year 2020+),
        // assume it's in milliseconds and convert to seconds
        if value > 1577836800000 {
            return value / 1000
        } else {
            return value
        }
    }
    
    private var filteredSegments: [ReplaySegment] {
        return segments.map { segment in
            let filteredEvents = segment.sortedEvents.filter { event in
                // Apply event type filter
                if selectedEventTypeFilter != "All" {
                    let baseType = ContentView.baseTypeName(for: event.type)
                    let matches = baseType == selectedEventTypeFilter
                    let typeMatches = invertFilter ? !matches : matches
                    if !typeMatches {
                        return false
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
                
                return true
            }
            
            // Keep segment even if no events match - just show empty event list
            return ReplaySegment(id: segment.id, timestamp: segment.timestamp, events: filteredEvents)
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Sidebar (Segments)
            sidebarContent
                .navigationSplitViewColumnWidth(min: 280, ideal: 380, max: 500)
        } content: {
            // MARK: - Content (Events List)
            eventsListContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
        } detail: {
            // MARK: - Detail (HTML/JSON Viewer)
            detailContent
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { loadFromClipboard() }) {
                    Label("Load JSON", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(isLoading)
                .help("Load replay data from clipboard (⇧⌘V)")

                Button(action: { showInspector.toggle() }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Show filter inspector")
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    TextField("Enter Sentry replay URL...", text: $replayURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)

                    Button(action: { fetchReplayData() }) {
                        Label("Fetch", systemImage: "arrow.down.circle")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(replayURL.isEmpty || isLoading)
                    .help("Fetch replay from Sentry (⌘R)")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 200, ideal: 250, max: 350)
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = errorMessage {
                statusBar(message: errorMessage, isError: true)
            }
        }
        .onAppear {
            loadDebugJSON()
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "f" {
                    showGlobalSearch = true
                    searchFieldFocused = true
                    return nil
                }
                return event
            }
        }
        .onChange(of: segments) {
            // Update event cache when segments change
            updateEventCache()

            if !segments.isEmpty && selectedSegment == nil {
                selectedSegment = filteredSegments.first
                selectedEvent = displayedSegment?.events(useSortedOrder: useSortedOrder).first
            }
        }
        .onChange(of: useSortedOrder) {
            // Update event cache when sort order changes
            updateEventCache()
        }
        .onChange(of: selectedEventTypeFilter) {
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: invertFilter) {
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: timestampFilterValue) {
            updateSelectedSegmentAfterFilter()
        }
        .onChange(of: globalSearchQuery) {
            performGlobalSearch()
        }
        .safeAreaInset(edge: .top) {
            if showGlobalSearch {
                globalSearchBar
            }
        }
        .onChange(of: timestampFilterOperator) {
            updateSelectedSegmentAfterFilter()
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

    private var sidebarContent: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedSegment) {
                ForEach(Array(filteredSegments.enumerated()), id: \.element.id) { index, segment in
                    segmentRowWithDivider(segment: segment, index: index)
                        .id(segment.id)
                }
            }
            .listStyle(.sidebar)
            .environment(\.controlActiveState, .key)
            .onChange(of: selectedSegment) {
                if let segment = selectedSegment {
                    selectedEvent = segment.events(useSortedOrder: useSortedOrder).first
                    withAnimation {
                        proxy.scrollTo(segment.id, anchor: .center)
                    }
                }
            }
            .navigationTitle("Segments")
            .navigationSubtitle(segmentSubtitle)
        }
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
            isSelected: selectedSegment?.id == segment.id,
            originalSegment: segments.first(where: { $0.id == segment.id }),
            previousSegment: index > 0 ? segments[index - 1] : nil,
            onTimestampClick: { timestamp in
                setTimestampFilter(timestamp)
            }
        )
        .tag(segment)
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

        return ScrollViewReader { proxy in
            List(selection: $selectedEvent) {
                ForEach(events) { event in
                    EventRowView(
                        event: event,
                        isSelected: selectedEvent?.id == event.id,
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
                    withAnimation {
                        proxy.scrollTo(event.id, anchor: .center)
                    }
                }
            }
            .navigationTitle("Events")
            .navigationSubtitle("\(events.count) events")
        }
    }

    private var detailContent: some View {
        Group {
            if let selectedEvent = selectedEvent {
                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .center) {
                        Label("Event Details", systemImage: "doc.text")
                            .font(.headline)

                        Spacer()

                        Text(ContentView.displayName(for: selectedEvent))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .padding()

                    // Always show both JSON and HTML in vertical split
                    VSplitView {
                        JSONInspectorView(data: selectedEvent.data)
                            .id(selectedEvent.id)
                            .frame(minHeight: 100)

                        if let eventIndex = selectedEventGlobalIndex {
                            HTMLRenderPanel(
                                events: allEvents,
                                selectedEventIndex: eventIndex,
                                fullSnapshotIndices: fullSnapshotIndices,
                                metaIndices: metaIndices
                            )
                            .frame(minHeight: 100)
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
                }
            } else {
                ContentUnavailableView(
                    "No Event Selected",
                    systemImage: "calendar.badge.clock",
                    description: Text("Select an event to view its details")
                )
            }
        }
    }

    /// Flattened array of all events from all segments (cached for performance)
    private var allEvents: [ReplayEvent] {
        return cachedAllEvents
    }

    /// Update cache and segment boundaries
    private func updateEventCache() {
        cachedAllEvents = segments.flatMap { $0.events(useSortedOrder: useSortedOrder) }
        cachedAllEventsSegmentCount = segments.count
        cachedAllEventsSortOrder = useSortedOrder

        // Also update segment boundaries and event type indices
        var boundaries: [Int] = [0]
        var cumulative = 0
        var fullSnapshots: [Int] = []
        var metas: [Int] = []

        for segment in segments {
            let events = segment.events(useSortedOrder: useSortedOrder)

            // Build indices for FullSnapshot and Meta events
            for (localIndex, event) in events.enumerated() {
                let globalIndex = cumulative + localIndex
                if event.type == 2 { // FullSnapshot
                    fullSnapshots.append(globalIndex)
                } else if event.type == 4 { // Meta
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
    private var selectedEventGlobalIndex: Int? {
        guard let selectedEvent = selectedEvent,
              let selectedSegment = selectedSegment else {
            return nil
        }

        // Find the original segment index by matching segment ID
        guard let originalSegmentIndex = segments.firstIndex(where: { $0.id == selectedSegment.id }) else {
            return nil
        }

        // Find the event's position within the original segment
        let originalSegmentEvents = segments[originalSegmentIndex].events(useSortedOrder: useSortedOrder)
        guard let eventIndexInSegment = originalSegmentEvents.firstIndex(where: { $0.id == selectedEvent.id }) else {
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
        Form {
            Section("Event Filters") {
                Picker("Event Type", selection: $selectedEventTypeFilter) {
                    ForEach(eventTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }

                Toggle("Invert Filter", isOn: $invertFilter)
            }

            Section("Time Filter") {
                HStack {
                    Text("Timestamp")
                    Picker("Operator", selection: $timestampFilterOperator) {
                        Text("After").tag(">")
                        Text("Before").tag("<")
                    }
                    .labelsHidden()
                }

                TextField("Unix timestamp", text: $timestampFilterValue)
                    .textFieldStyle(.roundedBorder)

                if !timestampFilterValue.isEmpty {
                    Button("Clear", action: {
                        timestampFilterValue = ""
                    })
                    .buttonStyle(.borderless)
                }
            }

            Section("Display Options") {
                Toggle("Use Sorted Order", isOn: $useSortedOrder)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Filters")
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
        .background(isError ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
    }

    private func updateSelectedSegmentAfterFilter() {
        guard let currentSegment = selectedSegment else { return }

        if let displayedSegment = displayedSegment {
            selectedEvent = displayedSegment.events(useSortedOrder: useSortedOrder).first
        }
    }

    // MARK: - Global Search Functions

    private func performGlobalSearch() {
        searchMatches = []
        currentSearchIndex = 0

        guard !globalSearchQuery.isEmpty else { return }

        let query = globalSearchQuery.lowercased()

        for segment in segments {
            for event in segment.events(useSortedOrder: useSortedOrder) {
                // Search in event data
                if let jsonData = try? JSONSerialization.data(withJSONObject: event.data, options: []),
                   let jsonString = String(data: jsonData, encoding: .utf8),
                   jsonString.lowercased().contains(query) {
                    searchMatches.append(SearchMatch(
                        segmentId: segment.id,
                        eventId: event.id,
                        matchText: "Event data"
                    ))
                }

                // Search in event ID
                if event.id.lowercased().contains(query) {
                    searchMatches.append(SearchMatch(
                        segmentId: segment.id,
                        eventId: event.id,
                        matchText: "Event ID: \(event.id)"
                    ))
                }

                // Search in event type
                let eventType = ContentView.displayName(for: event)
                if eventType.lowercased().contains(query) {
                    searchMatches.append(SearchMatch(
                        segmentId: segment.id,
                        eventId: event.id,
                        matchText: "Event type: \(eventType)"
                    ))
                }
            }

            // Search in segment ID
            if segment.id.lowercased().contains(query) {
                if let firstEvent = segment.events(useSortedOrder: useSortedOrder).first {
                    searchMatches.append(SearchMatch(
                        segmentId: segment.id,
                        eventId: firstEvent.id,
                        matchText: "Segment ID: \(segment.id)"
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
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchMatches.count - 1
        selectSearchMatch(at: currentSearchIndex)
    }

    private func selectSearchMatch(at index: Int) {
        guard index < searchMatches.count else { return }
        let match = searchMatches[index]

        // Find and select the segment
        if let segment = segments.first(where: { $0.id == match.segmentId }) {
            selectedSegment = segment

            // Find and select the event
            let events = segment.events(useSortedOrder: useSortedOrder)
            if let event = events.first(where: { $0.id == match.eventId }) {
                selectedEvent = event
            }
        }
    }

    private func fetchReplayData() {
        guard let urlComponents = SentryURLParser.parse(url: replayURL) else {
            errorMessage = "Invalid Sentry replay URL format"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedSegments = try await SentryAPIService.shared.fetchReplaySegments(
                    orgSlug: urlComponents.orgSlug,
                    replayId: urlComponents.replayId
                )
                
                await MainActor.run {
                    self.segments = fetchedSegments
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch replay data: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadDebugJSON() {
        let debugFilePath = "billy.json"
        let fileURL = URL(fileURLWithPath: debugFilePath)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: debugFilePath) else {
            NSLog("Debug file not found at: \(debugFilePath)")
            return
        }

        do {
            let jsonData = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)

            if let outerArray = jsonObject as? [Any] {
                // Check if it's an array of arrays of events [[events...], [events...]]
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
                    NSLog("✅ Loaded \(parsedSegments.count) segments from debug file")
                } else if let eventsArray = jsonObject as? [[String: Any]] {
                    // Handle direct array of events
                    segments = [createSegmentFromEvents(eventsArray, id: "segment-0")]
                    errorMessage = nil
                    NSLog("✅ Loaded 1 segment from debug file")
                } else if let segmentsArray = jsonObject as? [[String: Any]] {
                    // Handle array of segment objects
                    segments = parseSegmentsFromClipboard(segmentsArray)
                    errorMessage = nil
                    NSLog("✅ Loaded \(segments.count) segments from debug file")
                }
            } else if let singleSegment = jsonObject as? [String: Any] {
                segments = parseSegmentsFromClipboard([singleSegment])
                errorMessage = nil
                NSLog("✅ Loaded 1 segment from debug file")
            } else {
                NSLog("❌ Invalid JSON format in debug file")
            }
        } catch {
            NSLog("❌ Failed to load debug file: \(error.localizedDescription)")
        }
    }

    private func loadFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let jsonString = pasteboard.string(forType: .string) else {
            errorMessage = "No text found in clipboard"
            return
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            errorMessage = "Invalid text format in clipboard"
            return
        }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            
            if let outerArray = jsonObject as? [Any] {
                // Check if it's an array of arrays of events [[events...], [events...]]
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
                    // Handle direct array of events
                    segments = [createSegmentFromEvents(eventsArray, id: "segment-0")]
                    errorMessage = nil
                } else if let segmentsArray = jsonObject as? [[String: Any]] {
                    // Handle array of segment objects
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
            errorMessage = "Invalid JSON in clipboard: \(error.localizedDescription)"
        }
    }
    
    private func createSegmentFromEvents(_ eventsArray: [[String: Any]], id: String) -> ReplaySegment {
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
            guard let id = segmentData["id"] as? String ?? segmentData["segment_id"] as? String else {
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
        if let timestamp = value as? TimeInterval {
            // Check if timestamp is in milliseconds
            // Use a more reasonable threshold: Jan 1, 2020 in seconds (1577836800)
            if timestamp > 1577836800 {
                // Could be milliseconds - check if it's way too large for seconds
                if timestamp > 1577836800000 {
                    // Definitely milliseconds, convert to seconds
                    return Date(timeIntervalSince1970: timestamp / 1000)
                } else {
                    // Likely seconds (between 2020-2050 range)
                    return Date(timeIntervalSince1970: timestamp)
                }
            } else {
                // Old timestamp, likely seconds
                return Date(timeIntervalSince1970: timestamp)
            }
        } else if let dateString = value as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: dateString)
        }
        return nil
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
        default: return "IncrementalSnapshot"
        }
    }
    
    static func customEventDisplayName(eventData: [String: Any]) -> String {
        // eventData is already the inner "data" object from the event
        guard let tag = eventData["tag"] as? String else {
            return "Custom"
        }
        
        switch tag {
        case "performanceSpan":
            if let payload = eventData["payload"] as? [String: Any],
               let op = payload["op"] as? String {
                return op
            }
        case "breadcrumb":
            if let payload = eventData["payload"] as? [String: Any],
               let category = payload["category"] as? String {
                return category
            }
        default:
            break
        }
        
        return tag
    }
    
    private var displayedSegment: ReplaySegment? {
        guard let selectedSegment = selectedSegment else { return nil }
        return filteredSegments.first(where: { $0.id == selectedSegment.id })
    }
    
    @ViewBuilder
    private var eventsAndDetailsView: some View {
        if let displayedSegment = displayedSegment {
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("Events (\(displayedSegment.events(useSortedOrder: useSortedOrder).count))")
                            .font(.headline)
                        
                        Spacer()
                        
                        if displayedSegment.wasResorted {
                            Button(action: {
                                useSortedOrder.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: useSortedOrder ? "arrow.up.arrow.down" : "list.number")
                                        .font(.caption)
                                    Text(useSortedOrder ? "Sorted" : "Original")
                                        .font(.caption)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if let eventsDuration = eventsDuration(for: displayedSegment) {
                            Text(eventsDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 44)
                    .padding(.trailing, 16)
                    
                    List(displayedSegment.events(useSortedOrder: useSortedOrder)) { event in
                        EventRowView(
                            event: event,
                            isSelected: selectedEvent?.id == event.id,
                            onTimestampClick: { timestamp in
                                setTimestampFilter(timestamp)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEvent = event
                        }
                    }
                }
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 450)
                
                if let selectedEvent = selectedEvent,
                   selectedEvent.type != 5 {
                    // Non-Custom event - show both JSON and HTML
                    HSplitView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .center) {
                                Text("Event Details")
                                    .font(.headline)

                                Spacer()

                                Text(ContentView.displayName(for: selectedEvent))
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            .frame(height: 44)
                            .padding(.horizontal, 16)

                            JSONInspectorView(data: selectedEvent.data)
                                .id(selectedEvent.id)
                                .padding(.horizontal, 16)
                        }
                        .frame(minWidth: 300)

                        if let eventIndex = selectedEventGlobalIndex {
                            HTMLRenderPanel(
                                events: allEvents,
                                selectedEventIndex: eventIndex,
                                fullSnapshotIndices: fullSnapshotIndices,
                                metaIndices: metaIndices
                            )
                            .frame(minWidth: 300)
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
                } else if let selectedEvent = selectedEvent {
                    // Custom event (type 5) - show only JSON
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center) {
                            Text("Event Details")
                                .font(.headline)

                            Spacer()

                            Text(ContentView.displayName(for: selectedEvent))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)

                        JSONInspectorView(data: selectedEvent.data)
                            .id(selectedEvent.id)
                            .padding(.horizontal, 16)
                    }
                    .frame(minWidth: 300, maxWidth: .infinity)
                } else {
                    VStack {
                        Image(systemName: "curlybraces")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Event Selected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Select an event to view its JSON data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No Segment Selected")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Select a segment from the sidebar to view its events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func eventsDuration(for segment: ReplaySegment) -> String? {
        let events = segment.events(useSortedOrder: useSortedOrder)
        guard events.count > 1,
              let firstEvent = events.min(by: { $0.timestamp < $1.timestamp }),
              let lastEvent = events.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }
        
        return formatDuration(lastEvent.timestamp.timeIntervalSince(firstEvent.timestamp))
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
