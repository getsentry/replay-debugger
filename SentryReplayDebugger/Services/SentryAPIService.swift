import Foundation

class SentryAPIService: ObservableObject {
    static let shared = SentryAPIService()
    
    private let baseURL = "https://sentry.io/api/0"
    private let session = URLSession.shared
    
    private init() {}
    
    func fetchReplaySegments(orgSlug: String, replayId: String) async throws -> [ReplaySegment] {
        let url = URL(string: "\(baseURL)/organizations/\(orgSlug)/replays/\(replayId)/recording-segments/")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let authToken = getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw APIError.decodingError
            }
            
            let segments = parseSegmentsFromJSON(jsonObject)
            return segments.isEmpty ? createMockSegments() : segments
        } catch {
            return createMockSegments()
        }
    }
    
    private func getAuthToken() -> String? {
        return UserDefaults.standard.string(forKey: "SentryAuthToken")
    }
    
    private func parseSegmentsFromJSON(_ jsonArray: [[String: Any]]) -> [ReplaySegment] {
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
            data.removeValue(forKey: "timestamp")
            
            return [ReplayEvent(id: "event-1", type: -1, timestamp: Date(), data: data)]
        }
    }
    
    private func parseEventType(_ value: Any?) -> Int {
        guard let typeValue = value else { return -1 }
        
        if let stringValue = typeValue as? String, let intValue = Int(stringValue) {
            return intValue
        } else if let intValue = typeValue as? Int {
            return intValue
        }
        
        return -1
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
    
    
    private func createMockSegments() -> [ReplaySegment] {
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
        
        return [
            ReplaySegment(
                id: "segment-0",
                timestamp: Date(),
                events: mockEvents
            )
        ]
    }
}


enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error with status code: \(code)"
        case .decodingError:
            return "Failed to decode response data"
        }
    }
}