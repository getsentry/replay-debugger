import AppKit
import Foundation

struct SegmentExporter {
    enum ExportError: Error {
        case serializationFailed
        case noSegments
    }

    static func serializeFlattened(_ segments: [ReplaySegment]) throws -> Data {
        guard !segments.isEmpty else {
            throw ExportError.noSegments
        }

        let allEvents = segments.flatMap { segment in
            segment.sortedEvents.map { event -> [String: Any] in
                [
                    "type": event.type,
                    "timestamp": Int(event.timestamp.timeIntervalSince1970 * 1000),
                    "data": event.data
                ]
            }
        }.sorted { first, second in
            (first["timestamp"] as? Int ?? 0) < (second["timestamp"] as? Int ?? 0)
        }

        guard JSONSerialization.isValidJSONObject(allEvents) else {
            throw ExportError.serializationFailed
        }

        return try JSONSerialization.data(withJSONObject: allEvents, options: [.prettyPrinted, .sortedKeys])
    }

    static func serializeWithSegments(_ segments: [ReplaySegment]) throws -> Data {
        guard !segments.isEmpty else {
            throw ExportError.noSegments
        }

        let segmentData = segments.map { segment -> [String: Any] in
            let events = segment.sortedEvents.map { event -> [String: Any] in
                [
                    "type": event.type,
                    "timestamp": Int(event.timestamp.timeIntervalSince1970 * 1000),
                    "data": event.data
                ]
            }

            return [
                "id": segment.id,
                "timestamp": Int(segment.timestamp.timeIntervalSince1970 * 1000),
                "events": events
            ]
        }

        guard JSONSerialization.isValidJSONObject(segmentData) else {
            throw ExportError.serializationFailed
        }

        return try JSONSerialization.data(withJSONObject: segmentData, options: [.prettyPrinted, .sortedKeys])
    }

    static func exportToFile(_ segments: [ReplaySegment], preserveSegments: Bool) {
        guard !segments.isEmpty else { return }

        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = preserveSegments ? "replay-segments.json" : "replay-events.json"
            panel.canCreateDirectories = true

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = preserveSegments
                    ? try serializeWithSegments(segments)
                    : try serializeFlattened(segments)
                try data.write(to: url)
            } catch {
                NSLog("Failed to export segments: \(error)")
            }
        }
    }

    static func copyToClipboard(_ segments: [ReplaySegment], preserveSegments: Bool) {
        guard !segments.isEmpty else { return }

        do {
            let data = preserveSegments
                ? try serializeWithSegments(segments)
                : try serializeFlattened(segments)

            guard let jsonString = String(data: data, encoding: .utf8) else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(jsonString, forType: .string)
        } catch {
            NSLog("Failed to copy segments to clipboard: \(error)")
        }
    }
}
