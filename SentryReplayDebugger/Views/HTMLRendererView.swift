import SwiftUI
import WebKit

struct HTMLRenderPanel: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
    let fullSnapshotIndices: [Int]
    let metaIndices: [Int]
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
                panelId: panelId,
                showSource: $showSource
            )
        }
    }
}

struct HTMLRendererView: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
    let fullSnapshotIndices: [Int]
    let metaIndices: [Int]
    let panelId: String
    @Binding var showSource: Bool
    @State private var renderState: RRWebEventProcessor.RenderState = RRWebEventProcessor.RenderState()
    @State private var error: String?
    @State private var lastProcessedIndex: Int? = nil
    @State private var isProcessing: Bool = false

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
            } else if renderState.html == nil {
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
                        viewportHeight: renderState.viewportHeight
                    )
                }
            }
        }
        .task(id: selectedEventIndex) {
            // task(id:) runs once per unique ID, preventing duplicates
            processEvents(targetIndex: selectedEventIndex)
        }
        .onChange(of: events.count) {
            // Events array changed (e.g., data reloaded), reset state
            lastProcessedIndex = nil
            renderState = RRWebEventProcessor.RenderState()
        }
    }

    private func processEvents(targetIndex: Int) {
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
        defer { isProcessing = false }

        error = nil

        // Validate inputs
        guard !events.isEmpty else {
            return // Don't set error, just wait for valid data
        }

        guard targetIndex >= 0 && targetIndex < events.count else {
            error = "Invalid event index"
            return
        }

        let selectedEvent = events[targetIndex]
        NSLog("🎬 [\(panelId.prefix(8))] processEvents - targetIndex: \(targetIndex), event: \(selectedEvent.id), lastProcessedIndex: \(lastProcessedIndex?.description ?? "nil")")

        // Determine if we can do incremental update or need full re-render
        if let lastIndex = lastProcessedIndex, targetIndex > lastIndex, renderState.domTree != nil {
            // Incremental update: only process events from lastIndex+1 to targetIndex
            NSLog("⚡️ [\(panelId.prefix(8))] Incremental render from \(lastIndex + 1) to \(targetIndex)")
            let state = RRWebEventProcessor.processEventsIncremental(
                events,
                from: lastIndex + 1,
                to: targetIndex,
                startingState: renderState
            )

            if state.html == nil {
                error = "Failed to process incremental events"
                NSLog("❌ [\(panelId.prefix(8))] Incremental render failed")
            } else {
                let oldHTML = renderState.html
                NSLog("✅ [\(panelId.prefix(8))] Incremental render success, HTML length: \(state.html?.count ?? 0), HTML changed: \(oldHTML != state.html)")
                renderState = state
                lastProcessedIndex = targetIndex
            }
        } else {
            // Full re-render: Find most recent FullSnapshot before target using pre-computed indices
            let fullSnapshotIndex = findMostRecentIndex(in: fullSnapshotIndices, before: targetIndex)

            // Find most recent Meta before FullSnapshot or target
            let searchUpTo = fullSnapshotIndex ?? targetIndex
            let metaIndex = findMostRecentIndex(in: metaIndices, before: searchUpTo)

            let startIndex = fullSnapshotIndex ?? 0
            let reason = lastProcessedIndex == nil ? "initial" : "backward/reset"

            if let fsIndex = fullSnapshotIndex {
                NSLog("🔄 [\(panelId.prefix(8))] Full render (\(reason)) from FullSnapshot at \(fsIndex) to \(targetIndex) (skipping \(fsIndex) events)")
            } else {
                NSLog("🔄 [\(panelId.prefix(8))] Full render (\(reason)) from 0 to \(targetIndex) (no FullSnapshot found)")
            }

            let state = RRWebEventProcessor.processEvents(events, upToIndex: targetIndex, startFromIndex: startIndex, metaIndex: metaIndex)

            if state.html == nil {
                error = "No HTML generated. Make sure there's a FullSnapshot event before the selected event."
                NSLog("❌ [\(panelId.prefix(8))] Full render failed")
            } else {
                NSLog("✅ [\(panelId.prefix(8))] Full render success, HTML length: \(state.html?.count ?? 0)")
                renderState = state
                lastProcessedIndex = targetIndex
            }
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
}

struct ScaledWebView: View {
    let html: String
    let viewportWidth: CGFloat?
    let viewportHeight: CGFloat?

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
                WebView(html: html)
                    .frame(width: vpWidth, height: vpHeight)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            } else {
                let _ = NSLog("⚠️ No viewport dimensions, rendering without scaling")
                // No viewport dimensions, just show the HTML
                WebView(html: html)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct WebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        NSLog("🌐 WebView makeNSView called")
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
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
