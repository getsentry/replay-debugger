import SwiftUI

struct SegmentListView: View {
    let segments: [ReplaySegment]
    @State private var selectedSegment: ReplaySegment?
    @State private var selectedEvent: ReplayEvent?
    @State private var useSortedOrder = true
    @State private var segmentColumnWidth: CGFloat?
    @State private var eventColumnWidth: CGFloat?
    
    private var totalSegmentsDuration: String? {
        guard !segments.isEmpty else { return nil }
        
        // Get all timestamps from all events across all segments
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
        let absDuration = abs(duration)
        if absDuration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if absDuration < 60 {
            return String(format: "%.1fs", duration)
        } else if absDuration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.1fs", minutes, abs(seconds))
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, abs(minutes))
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        
        let timeString = formatter.string(from: date)
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return "\(timeString).\(String(format: "%03d", milliseconds))"
    }
    
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Segments (\(segments.count))")
                        .font(.headline)
                    
                    Spacer()
                    
                    if let totalDuration = totalSegmentsDuration {
                        Text(totalDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 44)
                .padding(.leading, 8)
                .padding(.trailing, 16)
                
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            SegmentRowView(
                                segment: segment,
                                isSelected: selectedSegment?.id == segment.id,
                                originalSegment: nil,
                                previousSegment: index > 0 ? segments[index - 1] : nil
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSegment = segment
                                selectedEvent = segment.events(useSortedOrder: useSortedOrder).first
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 8)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(width: segmentColumnWidth ?? 200)
            
            VStack(alignment: .leading, spacing: 0) {
                if let selectedSegment = selectedSegment {
                    HStack(alignment: .center) {
                        Text("Events (\(selectedSegment.events(useSortedOrder: useSortedOrder).count))")
                            .font(.headline)
                        
                        Spacer()
                        
                        // Sort toggle button
                        if selectedSegment.wasResorted {
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
                        
                        if let eventsDuration = eventsDuration(for: selectedSegment) {
                            Text(eventsDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 16)
                    
                    // OPTIMIZATION: Cache enumerated array to avoid recreating on every render
                    let events = selectedSegment.events(useSortedOrder: useSortedOrder)
                    let eventsArray = Array(events.enumerated())

                    List(eventsArray, id: \.element.id) { index, event in
                        let previousEvent = index > 0 ? events[index - 1] : nil
                        EventRowView(event: event, isSelected: selectedEvent?.id == event.id, previousEvent: previousEvent)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEvent = event
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
                        Text("Select a segment from the list to view its events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: eventColumnWidth ?? 200)
            
            VStack(alignment: .leading, spacing: 0) {
                if let selectedEvent = selectedEvent {
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
                    
                    JSONInspectorView(data: selectedEvent.data, onHighlightElement: nil, onFindInSource: nil)
                        .padding(.horizontal, 16)
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
            .frame(minWidth: 300, maxWidth: .infinity)
        }
        .onAppear {
            calculateColumnWidths()
            selectFirstSegmentAndEvent()
        }
        .onChange(of: segments.count) { _ in
            calculateColumnWidths()
            selectFirstSegmentAndEvent()
        }
    }
    
    private func selectFirstSegmentAndEvent() {
        guard let firstSegment = segments.first else { return }
        selectedSegment = firstSegment
        selectedEvent = firstSegment.events(useSortedOrder: useSortedOrder).first
    }
    
    private func calculateColumnWidths() {
        // OPTIMIZATION: Sample first 50 segments instead of all for performance
        let sampleSize = min(50, segments.count)
        let sampledSegments = Array(segments.prefix(sampleSize))

        // Calculate segment column width based on sampled segments
        var maxSegmentWidth: CGFloat = 300

        let monospacedFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let captionFont = NSFont.systemFont(ofSize: 11)
        let caption2Font = NSFont.systemFont(ofSize: 10)

        for (index, segment) in sampledSegments.enumerated() {
            let segmentNumber = segment.id.replacingOccurrences(of: "segment-", with: "")

            // Calculate first line width: Segment X + duration + timestamp
            let segmentText = "Segment \(segmentNumber)"
            let segmentTextWidth = segmentText.widthOfString(usingFont: .systemFont(ofSize: 13, weight: .medium))
            let timestampWidth = formatTimestamp(segment.timestamp).widthOfString(usingFont: monospacedFont)

            // Calculate duration width for first line
            var durationWidth: CGFloat = 0
            let events = segment.sortedEvents  // OPTIMIZATION: Store in local variable
            if events.count > 1,
               let firstEvent = events.min(by: { $0.timestamp < $1.timestamp }),
               let lastEvent = events.max(by: { $0.timestamp < $1.timestamp }) {
                let duration = formatDuration(lastEvent.timestamp.timeIntervalSince(firstEvent.timestamp))
                // Icon width (approx 10pt) + spacing + text width
                durationWidth = 10 + 2 + duration.widthOfString(usingFont: captionFont) + 8 // extra spacing
            }

            let firstLineWidth = segmentTextWidth + durationWidth + timestampWidth + 32 // Spacers

            // Calculate second line width: size • event count + time diff
            let bytes = segment.approximateSize  // OPTIMIZATION: Now cached in model
            let sizeText: String
            if bytes < 1024 {
                sizeText = "\(bytes) B"
            } else if bytes < 1024 * 1024 {
                sizeText = String(format: "%.1f KB", Double(bytes) / 1024.0)
            } else {
                sizeText = String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
            }

            let eventCountText = "\(events.count) events"  // OPTIMIZATION: Use local variable
            let sizeAndCountText = "\(sizeText) • \(eventCountText)"
            let sizeAndCountWidth = sizeAndCountText.widthOfString(usingFont: caption2Font)

            // Calculate time difference width
            var timeDiffWidth: CGFloat = 0
            if index > 0 {
                let prevSegment = sampledSegments[index - 1]
                let timeDiff = segment.timestamp.timeIntervalSince(prevSegment.timestamp)
                let sign = timeDiff >= 0 ? "+" : ""
                let timeDiffText = "\(sign)\(formatDuration(timeDiff))"
                timeDiffWidth = timeDiffText.widthOfString(usingFont: caption2Font)
            }

            let secondLineWidth = sizeAndCountWidth + timeDiffWidth + 32 // Spacers

            let totalWidth = max(firstLineWidth, secondLineWidth) + 32 // Additional padding
            maxSegmentWidth = max(maxSegmentWidth, totalWidth)
        }
        segmentColumnWidth = min(maxSegmentWidth, 500)

        // OPTIMIZATION: Use fixed width for events column to avoid iterating all events
        eventColumnWidth = 350
    }
}

extension String {
    func widthOfString(usingFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: attributes)
        return size.width
    }
}

struct SegmentRowView: View {
    let segment: ReplaySegment
    let isSelected: Bool
    let originalSegment: ReplaySegment?
    let previousSegment: ReplaySegment?
    var onTimestampClick: ((Date) -> Void)? = nil

    private var segmentDuration: String? {
        // OPTIMIZATION: Store sortedEvents in local variable to avoid repeated property access
        let events = (originalSegment ?? segment).sortedEvents
        guard events.count > 1,
              let firstEvent = events.min(by: { $0.timestamp < $1.timestamp }),
              let lastEvent = events.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        let duration = lastEvent.timestamp.timeIntervalSince(firstEvent.timestamp)
        return formatDuration(duration)
    }

    private var segmentNumber: String {
        return segment.id.replacingOccurrences(of: "segment-", with: "")
    }

    private var formattedSize: String {
        let bytes = (originalSegment ?? segment).approximateSize
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    private var timeDifferenceFromPrevious: String? {
        guard let previous = previousSegment else { return nil }
        let timeDiff = (originalSegment ?? segment).timestamp.timeIntervalSince(previous.timestamp)
        return formatTimeDiff(timeDiff)
    }

    private func formatTimeDiff(_ duration: TimeInterval) -> String {
        let sign = duration >= 0 ? "+" : ""
        let absDuration = abs(duration)

        if absDuration < 60 {
            // Less than 1 minute: show seconds with 3 decimal places
            return String(format: "%@%0.3fs", sign, duration)
        } else if absDuration < 3600 {
            // Less than 1 hour: show minutes and seconds
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%@%dm %0.1fs", sign, abs(minutes), abs(seconds))
        } else {
            // 1 hour or more: show hours and minutes
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%@%dh %dm", sign, abs(hours), abs(minutes))
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none

        let timeString = formatter.string(from: date)
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)

        return "\(timeString).\(String(format: "%03d", milliseconds))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let absDuration = abs(duration)
        if absDuration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if absDuration < 60 {
            return String(format: "%.1fs", duration)
        } else if absDuration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.1fs", minutes, abs(seconds))
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %dm", hours, abs(minutes))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // First line: Segment 0 ⏱ duration                    timestamp
            HStack {
                HStack(alignment: .center, spacing: 4) {
                    Text("Segment \(segmentNumber)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    if let duration = segmentDuration {
                        HStack(spacing: 2) {
                            Image(systemName: "timer")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                    }
                }

                Spacer()

                Button(action: {
                    onTimestampClick?((originalSegment ?? segment).timestamp)
                }) {
                    Text(formatTimestamp((originalSegment ?? segment).timestamp))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }

            // Second line: size • event count                     +time diff
            HStack {
                HStack(spacing: 4) {
                    Text(formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("\(segment.sortedEvents.count) events")  // Note: count is O(1) so no optimization needed
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let timeDiff = timeDifferenceFromPrevious {
                    Text(timeDiff)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

struct EventRowView: View {
    let event: ReplayEvent
    let isSelected: Bool
    let previousEvent: ReplayEvent?
    var onTimestampClick: ((Date) -> Void)? = nil

    private var timeDifferenceFromPrevious: String? {
        guard let previous = previousEvent else { return nil }
        let timeDiff = event.timestamp.timeIntervalSince(previous.timestamp)
        return formatTimeDiff(timeDiff)
    }

    private func formatTimeDiff(_ duration: TimeInterval) -> String {
        let sign = duration >= 0 ? "+" : ""
        let absDuration = abs(duration)

        if absDuration < 60 {
            // Less than 1 minute: show seconds with 3 decimal places
            return String(format: "%@%0.3fs", sign, duration)
        } else if absDuration < 3600 {
            // Less than 1 hour: show minutes and seconds
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%@%dm %0.1fs", sign, abs(minutes), abs(seconds))
        } else {
            // 1 hour or more: show hours and minutes
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%@%dh %dm", sign, abs(hours), abs(minutes))
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none

        let timeString = formatter.string(from: date)
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)

        return "\(timeString).\(String(format: "%03d", milliseconds))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ContentView.displayName(for: event))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)

                    if let subheading = eventSubheading {
                        Text(subheading)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Button(action: {
                        onTimestampClick?(event.timestamp)
                    }) {
                        Text(formatTimestamp(event.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                    if let timeDiff = timeDifferenceFromPrevious {
                        Text(timeDiff)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var eventSubheading: String? {
        // Check if this is a custom event (type 5) with a tag
        if event.type == 5, event.data["tag"] != nil {
            return "Custom"
        }
        
        // Check if this is an incremental snapshot (type 3) with a source
        if event.type == 3, event.data["source"] != nil {
            return "IncrementalSnapshot"
        }
        
        return nil
    }
}

#Preview {
    let mockEvents = [
        ReplayEvent(
            id: "event-1",
            type: 2,  // FullSnapshot
            timestamp: Date(),
            data: [
                "selector": ".button-primary",
                "mutation_type": "attributes",
                "attribute": "class"
            ]
        ),
        ReplayEvent(
            id: "event-2",
            type: 3,  // IncrementalSnapshot
            timestamp: Date().addingTimeInterval(1000),
            data: [
                "x": 150,
                "y": 200,
                "target": "button#submit"
            ]
        )
    ]
    
    let mockSegments = [
        ReplaySegment(
            id: "segment-0",
            timestamp: Date(),
            events: mockEvents
        )
    ]
    
    return SegmentListView(segments: mockSegments)
        .frame(width: 1000, height: 600)
}