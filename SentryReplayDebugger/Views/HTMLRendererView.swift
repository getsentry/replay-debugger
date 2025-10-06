import SwiftUI
import WebKit

struct HTMLRenderPanel: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
    let fullSnapshotIndices: [Int]
    let metaIndices: [Int]
    @Binding var renderStateCache: [Int: RRWebEventProcessor.RenderState]
    let cacheInterval: Int
    @Binding var highlightedNodeId: Int?
    let onHighlightError: (String) -> Void
    let panelId: String = UUID().uuidString
    @State private var showSource: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("HTML Render")
                    .font(.headline)

                Spacer()

                Picker("", selection: $showSource) {
                    Text("Rendered").tag(false)
                    Text("Source").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .frame(height: 44)
            .padding(.horizontal, 16)

            HTMLRendererView(
                events: events,
                selectedEventIndex: selectedEventIndex,
                fullSnapshotIndices: fullSnapshotIndices,
                metaIndices: metaIndices,
                renderStateCache: $renderStateCache,
                cacheInterval: cacheInterval,
                panelId: panelId,
                showSource: $showSource,
                highlightedNodeId: $highlightedNodeId,
                onHighlightError: onHighlightError
            )
        }
    }
}

struct HTMLRendererView: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
    let fullSnapshotIndices: [Int]
    let metaIndices: [Int]
    @Binding var renderStateCache: [Int: RRWebEventProcessor.RenderState]
    let cacheInterval: Int
    let panelId: String
    @Binding var showSource: Bool
    @Binding var highlightedNodeId: Int?
    let onHighlightError: (String) -> Void
    @State private var renderState: RRWebEventProcessor.RenderState = RRWebEventProcessor.RenderState()
    @State private var error: String?
    @State private var lastProcessedIndex: Int? = nil
    @State private var isProcessing: Bool = false
    @State private var isLoadingNewRender: Bool = false
    @State private var webView: WKWebView? = nil
    @State private var highlightFrame: CGRect? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Cannot Render HTML")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if renderState.html == nil || isLoadingNewRender {
                VStack {
                    ProgressView()
                    Text("Processing events...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let html = renderState.html {
                if showSource {
                    HTMLSourceView(html: html)
                } else {
                    ScaledWebView(
                        html: html,
                        viewportWidth: renderState.viewportWidth,
                        viewportHeight: renderState.viewportHeight,
                        webView: $webView,
                        highlightFrame: highlightFrame
                    )
                }
            }
        }
        .task(id: selectedEventIndex) {
            // task(id:) runs once per unique ID, preventing duplicates
            await processEvents(targetIndex: selectedEventIndex)
        }
        .onChange(of: events.count) {
            // Events array changed (e.g., data reloaded), reset state
            lastProcessedIndex = nil
            renderState = RRWebEventProcessor.RenderState()
        }
        .onChange(of: highlightedNodeId) { newId in
            if let nodeId = newId {
                highlightElement(nodeId)
            }
        }
        .onChange(of: selectedEventIndex) {
            // Clear highlight when navigating to a different event
            clearHighlight()
            highlightedNodeId = nil
        }
    }

    private func processEvents(targetIndex: Int) async {
        // Prevent duplicate processing
        guard !isProcessing else {
            NSLog("⏭️ [\(panelId.prefix(8))] Skipping duplicate processEvents call for targetIndex: \(targetIndex)")
            return
        }

        // Skip if we're already at the correct state
        if lastProcessedIndex == targetIndex, renderState.html != nil, error == nil {
            NSLog("✓ [\(panelId.prefix(8))] Already processed targetIndex: \(targetIndex), skipping")
            return
        }

        isProcessing = true
        isLoadingNewRender = true
        defer {
            isProcessing = false
            isLoadingNewRender = false
        }

        error = nil

        // Yield to let the UI update and show the loading spinner
        await Task.yield()

        // Validate inputs
        guard !events.isEmpty else {
            return // Don't set error, just wait for valid data
        }

        guard targetIndex >= 0 && targetIndex < events.count else {
            error = "Invalid event index"
            return
        }

        let selectedEvent = events[targetIndex]

        // First, find the FullSnapshot we'll be using (checkpoint must be after this)
        let fullSnapshotIndex = findMostRecentIndex(in: fullSnapshotIndices, before: targetIndex)
        let fsIndex = fullSnapshotIndex ?? 0

        NSLog("🎬 [\(panelId.prefix(8))] processEvents - targetIndex: \(targetIndex), event: \(selectedEvent.id), FS: \(fsIndex), cache size: \(renderStateCache.count)")

        // STRATEGY 1: Try cache checkpoint (fastest)
        // Only use checkpoints that are AFTER the FullSnapshot we'll be using
        if let (checkpointIndex, cachedState) = findNearestCheckpoint(after: fsIndex, before: targetIndex) {
            if checkpointIndex == targetIndex {
                // Exact cache hit - must copy to avoid mutating cache
                NSLog("🎯 [\(panelId.prefix(8))] Cache hit at \(targetIndex)")
                renderState = cachedState.copy()
                lastProcessedIndex = targetIndex
                return
            } else {
                // Incremental from checkpoint
                // Note: No need to copy here - processIncrementalWithCheckpoints will handle copying
                let distance = targetIndex - checkpointIndex
                NSLog("📦 [\(panelId.prefix(8))] Loading checkpoint \(checkpointIndex), +\(distance) events to \(targetIndex)")

                let state = processIncrementalWithCheckpoints(
                    from: checkpointIndex,
                    to: targetIndex,
                    startingState: cachedState,
                    fsIndex: fsIndex
                )

                if state.html != nil {
                    NSLog("✅ [\(panelId.prefix(8))] Incremental from checkpoint success")
                    renderState = state
                    lastProcessedIndex = targetIndex
                    return
                }
                // Fall through to next strategy if failed
                NSLog("⚠️ [\(panelId.prefix(8))] Incremental from checkpoint failed, trying FullSnapshot")
            }
        }

        // STRATEGY 2: Try incremental from current state
        if let lastIndex = lastProcessedIndex, targetIndex > lastIndex, renderState.domTree != nil {
            let distance = targetIndex - lastIndex
            NSLog("⚡️ [\(panelId.prefix(8))] Incremental render from \(lastIndex + 1) to \(targetIndex) (\(distance) events)")
            let state = processIncrementalWithCheckpoints(
                from: lastIndex,
                to: targetIndex,
                startingState: renderState,
                fsIndex: fsIndex
            )

            if state.html != nil {
                NSLog("✅ [\(panelId.prefix(8))] Incremental render success")
                renderState = state
                lastProcessedIndex = targetIndex
                return
            }
            // Fall through to FullSnapshot if failed
            NSLog("⚠️ [\(panelId.prefix(8))] Incremental render failed, trying FullSnapshot")
        }

        // STRATEGY 3: Full render from FullSnapshot (fallback)
        let searchUpTo = fullSnapshotIndex ?? targetIndex
        let metaIndex = findMostRecentIndex(in: metaIndices, before: searchUpTo)
        let startIndex = fullSnapshotIndex ?? 0
        let reason = lastProcessedIndex == nil ? "initial" : "backward/reset"

        if let fsIndex = fullSnapshotIndex {
            NSLog("🔄 [\(panelId.prefix(8))] Full render (\(reason)) from FullSnapshot at \(fsIndex) to \(targetIndex) (skipping \(fsIndex) events)")
        } else {
            NSLog("🔄 [\(panelId.prefix(8))] Full render (\(reason)) from 0 to \(targetIndex) (no FullSnapshot found)")
        }

        // Process with checkpoint saving at interval boundaries
        let state = processWithCheckpoints(upToIndex: targetIndex, startFromIndex: startIndex, metaIndex: metaIndex)

        if state.html == nil {
            error = "No HTML generated. Make sure there's a FullSnapshot event before the selected event."
            NSLog("❌ [\(panelId.prefix(8))] Full render failed")
        } else {
            NSLog("✅ [\(panelId.prefix(8))] Full render success, HTML length: \(state.html?.count ?? 0)")
            renderState = state
            lastProcessedIndex = targetIndex
        }
    }

    /// Finds the most recent index in a sorted array that is less than or equal to the target
    /// Uses binary search for O(log n) performance
    private func findMostRecentIndex(in indices: [Int], before target: Int) -> Int? {
        guard !indices.isEmpty else { return nil }

        // Binary search to find the rightmost index <= target
        var left = 0
        var right = indices.count - 1
        var result: Int? = nil

        while left <= right {
            let mid = (left + right) / 2
            let value = indices[mid]

            if value <= target {
                result = value
                left = mid + 1  // Try to find a more recent one
            } else {
                right = mid - 1
            }
        }

        return result
    }

    /// Find nearest cached checkpoint after FullSnapshot and before target index
    private func findNearestCheckpoint(after fsIndex: Int, before targetIndex: Int) -> (Int, RRWebEventProcessor.RenderState)? {
        let validCheckpoints = renderStateCache.keys
            .filter { $0 > fsIndex && $0 <= targetIndex }
            .sorted()

        guard let nearestIndex = validCheckpoints.last,
              let state = renderStateCache[nearestIndex] else {
            return nil
        }

        let eventsFromFS = nearestIndex - fsIndex
        NSLog("📍 [\(panelId.prefix(8))] Found checkpoint at \(nearestIndex) (\(eventsFromFS) events from FS at \(fsIndex))")

        return (nearestIndex, state)
    }

    /// Process events and save checkpoints at FS-relative interval boundaries
    private func processWithCheckpoints(upToIndex targetIndex: Int, startFromIndex startIndex: Int, metaIndex: Int?) -> RRWebEventProcessor.RenderState {
        let eventsFromFS = targetIndex - startIndex

        // Calculate how many complete boundaries we'll cross
        let numBoundaries = eventsFromFS / cacheInterval

        // If we won't cross any boundaries, just process to target
        if numBoundaries == 0 {
            return RRWebEventProcessor.processEvents(events, upToIndex: targetIndex, startFromIndex: startIndex, metaIndex: metaIndex)
        }

        // Process to first checkpoint boundary (FS + cacheInterval)
        let firstBoundaryIndex = startIndex + cacheInterval
        var currentState = RRWebEventProcessor.processEvents(events, upToIndex: firstBoundaryIndex, startFromIndex: startIndex, metaIndex: metaIndex)
        var currentIndex = firstBoundaryIndex

        if currentState.html != nil && renderStateCache[firstBoundaryIndex] == nil {
            NSLog("💾 [\(panelId.prefix(8))] Saving checkpoint at \(firstBoundaryIndex) (\(cacheInterval) events from FS at \(startIndex))")
            renderStateCache[firstBoundaryIndex] = currentState.copy()
        }

        // Process incrementally to each subsequent boundary
        for boundaryNum in 2...numBoundaries {
            let boundaryIndex = startIndex + (cacheInterval * boundaryNum)
            let eventsAtBoundary = cacheInterval * boundaryNum

            // Incremental from current state
            currentState = RRWebEventProcessor.processEventsIncremental(
                events,
                from: currentIndex + 1,
                to: boundaryIndex,
                startingState: currentState
            )

            if currentState.html != nil && renderStateCache[boundaryIndex] == nil {
                NSLog("💾 [\(panelId.prefix(8))] Saving checkpoint at \(boundaryIndex) (\(eventsAtBoundary) events from FS at \(startIndex))")
                renderStateCache[boundaryIndex] = currentState.copy()
            }

            currentIndex = boundaryIndex
        }

        // Process from last checkpoint to target if needed
        if currentIndex < targetIndex {
            currentState = RRWebEventProcessor.processEventsIncremental(
                events,
                from: currentIndex + 1,
                to: targetIndex,
                startingState: currentState
            )
        }

        evictOldCheckpoints()
        return currentState
    }

    /// Process incrementally from startIndex to targetIndex, saving checkpoints at boundaries
    private func processIncrementalWithCheckpoints(
        from startIndex: Int,
        to targetIndex: Int,
        startingState: RRWebEventProcessor.RenderState,
        fsIndex: Int
    ) -> RRWebEventProcessor.RenderState {
        let totalEvents = targetIndex - startIndex

        // If the jump is small (less than one interval), just process directly
        if totalEvents < cacheInterval {
            return RRWebEventProcessor.processEventsIncremental(
                events,
                from: startIndex + 1,
                to: targetIndex,
                startingState: startingState
            )
        }

        // Large jump: process in chunks and save checkpoints at each boundary
        var currentState = startingState
        var currentIndex = startIndex

        // Find the next FS-relative boundary after startIndex
        let eventsFromFSAtStart = startIndex - fsIndex
        let nextBoundaryOffset = ((eventsFromFSAtStart / cacheInterval) + 1) * cacheInterval
        var nextBoundaryIndex = fsIndex + nextBoundaryOffset

        // Process to each boundary
        while nextBoundaryIndex <= targetIndex {
            currentState = RRWebEventProcessor.processEventsIncremental(
                events,
                from: currentIndex + 1,
                to: nextBoundaryIndex,
                startingState: currentState
            )

            // Save checkpoint at this boundary
            if currentState.html != nil && renderStateCache[nextBoundaryIndex] == nil {
                let eventsFromFS = nextBoundaryIndex - fsIndex
                NSLog("💾 [\(panelId.prefix(8))] Saving checkpoint at \(nextBoundaryIndex) (\(eventsFromFS) events from FS at \(fsIndex))")
                renderStateCache[nextBoundaryIndex] = currentState.copy()
            }

            currentIndex = nextBoundaryIndex
            nextBoundaryIndex += cacheInterval
        }

        // Process remaining events to target
        if currentIndex < targetIndex {
            currentState = RRWebEventProcessor.processEventsIncremental(
                events,
                from: currentIndex + 1,
                to: targetIndex,
                startingState: currentState
            )
        }

        evictOldCheckpoints()
        return currentState
    }

    private func evictOldCheckpoints() {
        guard renderStateCache.count > 30 else { return }

        // Find the two most recent FullSnapshots
        let recentFSIndices = fullSnapshotIndices.suffix(2)

        // Keep checkpoints that come after the second-to-last FullSnapshot
        // This ensures we keep checkpoints from the last 2 FullSnapshots
        let cutoffIndex = recentFSIndices.first ?? 0

        let keysToRemove = renderStateCache.keys.filter { $0 < cutoffIndex }

        for key in keysToRemove {
            renderStateCache.removeValue(forKey: key)
        }

        if keysToRemove.count > 0 {
            NSLog("🗑️ [\(panelId.prefix(8))] Evicted \(keysToRemove.count) checkpoints before FS at \(cutoffIndex)")
        }

        // If still too many, evict oldest ones
        if renderStateCache.count > 30 {
            let sortedKeys = renderStateCache.keys.sorted()
            let additionalKeysToRemove = sortedKeys.dropLast(30)
            for key in additionalKeysToRemove {
                renderStateCache.removeValue(forKey: key)
            }
            if additionalKeysToRemove.count > 0 {
                NSLog("🗑️ [\(panelId.prefix(8))] Evicted \(additionalKeysToRemove.count) additional old checkpoints")
            }
        }
    }

    private func highlightElement(_ nodeId: Int) {
        // Verify node exists in DOM tree
        guard let domTree = renderState.domTree else {
            onHighlightError("No DOM tree available")
            highlightedNodeId = nil
            return
        }

        guard domTree.findNode(byId: nodeId) != nil else {
            onHighlightError("Element with ID \(nodeId) not found in rendered DOM")
            highlightedNodeId = nil
            return
        }

        NSLog("✨ Highlighting element \(nodeId)")

        // Query element bounds using JavaScript
        guard let webView = webView else {
            NSLog("⚠️ WebView not available for highlighting")
            return
        }

        let script = """
        (function() {
            var element = document.querySelector('[data-rr-id="\(nodeId)"]');
            if (!element) return null;
            var rect = element.getBoundingClientRect();
            return {
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            };
        })();
        """

        webView.evaluateJavaScript(script) { [self] result, error in
            if let error = error {
                NSLog("❌ Failed to get element bounds: \(error.localizedDescription)")
                self.onHighlightError("Failed to get element bounds")
                self.highlightedNodeId = nil
                return
            }

            guard let dict = result as? [String: CGFloat],
                  let x = dict["x"],
                  let y = dict["y"],
                  let width = dict["width"],
                  let height = dict["height"] else {
                NSLog("❌ Element not found in rendered HTML")
                self.onHighlightError("Element with ID \(nodeId) not found in rendered HTML")
                self.highlightedNodeId = nil
                return
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            NSLog("📍 Element bounds: \(frame)")
            self.highlightFrame = frame
        }
    }

    private func clearHighlight() {
        NSLog("🧹 Clearing highlight")
        highlightFrame = nil
    }
}

struct ScaledWebView: View {
    let html: String
    let viewportWidth: CGFloat?
    let viewportHeight: CGFloat?
    @Binding var webView: WKWebView?
    let highlightFrame: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let _ = NSLog("📐 ScaledWebView geometry: \(geometry.size), viewport: \(viewportWidth ?? 0)x\(viewportHeight ?? 0)")

            if let vpWidth = viewportWidth, let vpHeight = viewportHeight {
                let _ = NSLog("✓ Rendering with viewport dimensions")
                // Calculate scale to fit viewport into available space
                let scaleX = geometry.size.width / vpWidth
                let scaleY = geometry.size.height / vpHeight
                let scale = min(scaleX, scaleY, 1.0) // Don't scale up, only down

                // Create WebView at actual viewport size
                WebView(html: html, webView: $webView)
                    .frame(width: vpWidth, height: vpHeight)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .overlay(
                        Group {
                            if let frame = highlightFrame {
                                // Transform coordinates from WebView space to scaled space
                                let scaledX = frame.origin.x * scale
                                let scaledY = frame.origin.y * scale
                                let scaledWidth = frame.width * scale
                                let scaledHeight = frame.height * scale

                                Rectangle()
                                    .fill(Color.orange.opacity(0.1))
                                    .border(Color.orange, width: 3)
                                    .frame(width: scaledWidth, height: scaledHeight)
                                    .position(x: scaledX + scaledWidth / 2, y: scaledY + scaledHeight / 2)
                                    .animation(.easeInOut(duration: 0.2), value: frame)
                            }
                        }
                    )
            } else {
                let _ = NSLog("⚠️ No viewport dimensions, rendering without scaling")
                // No viewport dimensions, just show the HTML
                WebView(html: html, webView: $webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Group {
                            if let frame = highlightFrame {
                                // No scaling, use coordinates as-is
                                Rectangle()
                                    .fill(Color.orange.opacity(0.1))
                                    .border(Color.orange, width: 3)
                                    .frame(width: frame.width, height: frame.height)
                                    .position(x: frame.origin.x + frame.width / 2, y: frame.origin.y + frame.height / 2)
                                    .animation(.easeInOut(duration: 0.2), value: frame)
                            }
                        }
                    )
            }
        }
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    @Binding var webView: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        NSLog("🌐 WebView makeNSView called")
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        // Store reference for JavaScript injection
        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        NSLog("🔄 WebView updateNSView called with HTML length: \(html.count)")

        // Write HTML to debug file
        writeDebugHTML(html)

        webView.loadHTMLString(html, baseURL: nil)
    }

    private func writeDebugHTML(_ html: String) {
        // Use /tmp which is always writable
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "sentry-replay-debug.html"
        let filePath = tempDir.appendingPathComponent(filename)

        // Check if file already exists
        let fileExists = FileManager.default.fileExists(atPath: filePath.path)

        // Write HTML to file
        do {
            try html.write(to: filePath, atomically: true, encoding: .utf8)
            NSLog("✅ Debug HTML written to: \(filePath.path)")

            // Only open in browser if this is a new file
            if !fileExists {
                NSWorkspace.shared.open(filePath)
                NSLog("🌐 Opened debug HTML in browser")
            }
        } catch {
            NSLog("❌ Failed to write debug HTML: \(error.localizedDescription)")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only allow loading the initial HTML, block all other navigation
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
