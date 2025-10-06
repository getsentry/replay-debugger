import SwiftUI
import WebKit

struct HTMLRenderPanel: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
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

            HTMLRendererView(events: events, selectedEventIndex: selectedEventIndex, showSource: $showSource)
        }
    }
}

struct HTMLRendererView: View {
    let events: [ReplayEvent]
    let selectedEventIndex: Int
    @Binding var showSource: Bool
    @State private var renderState: RRWebEventProcessor.RenderState = RRWebEventProcessor.RenderState()
    @State private var error: String?
    @State private var lastProcessedIndex: Int? = nil

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
        .onAppear {
            processEvents(targetIndex: selectedEventIndex)
        }
        .onChange(of: selectedEventIndex) { newIndex in
            processEvents(targetIndex: newIndex)
        }
        .onChange(of: events.count) { newCount in
            // Events array changed (e.g., data reloaded), reset state
            lastProcessedIndex = nil
            renderState = RRWebEventProcessor.RenderState()
            processEvents(targetIndex: selectedEventIndex)
        }
    }

    private func processEvents(targetIndex: Int) {
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
        NSLog("🎬 processEvents - targetIndex: \(targetIndex), event: \(selectedEvent.id), lastProcessedIndex: \(lastProcessedIndex?.description ?? "nil")")

        // Determine if we can do incremental update or need full re-render
        if let lastIndex = lastProcessedIndex, targetIndex > lastIndex, renderState.domTree != nil {
            // Incremental update: only process events from lastIndex+1 to targetIndex
            NSLog("⚡️ Incremental render from \(lastIndex + 1) to \(targetIndex)")
            let state = RRWebEventProcessor.processEventsIncremental(
                events,
                from: lastIndex + 1,
                to: targetIndex,
                startingState: renderState
            )

            if state.html == nil {
                error = "Failed to process incremental events"
                NSLog("❌ Incremental render failed")
            } else {
                let oldHTML = renderState.html
                NSLog("✅ Incremental render success, HTML length: \(state.html?.count ?? 0), HTML changed: \(oldHTML != state.html)")
                renderState = state
                lastProcessedIndex = targetIndex
            }
        } else {
            // Full re-render: process from beginning
            let reason = lastProcessedIndex == nil ? "initial" : "backward/reset"
            NSLog("🔄 Full render (\(reason)) from 0 to \(targetIndex)")
            let state = RRWebEventProcessor.processEvents(events, upToIndex: targetIndex)

            if state.html == nil {
                error = "No HTML generated. Make sure there's a FullSnapshot event before the selected event."
                NSLog("❌ Full render failed")
            } else {
                NSLog("✅ Full render success, HTML length: \(state.html?.count ?? 0)")
                renderState = state
                lastProcessedIndex = targetIndex
            }
        }
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
