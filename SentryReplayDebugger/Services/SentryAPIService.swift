import Foundation

struct PaginatedResponse {
    let segments: [ReplaySegment]
    let nextCursor: String?
    let hasMore: Bool
}

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
        return AuthService.shared.loadAccessToken()
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

    // MARK: - CURL Command Support

    func fetchReplaySegmentsFromCURL(_ curlCommand: String) async throws -> [ReplaySegment] {
        // Parse CURL command
        let curlRequest = try CURLParser.parse(curlCommand: curlCommand)

        // Fetch all pages
        var allSegments: [ReplaySegment] = []
        var currentCursor: String? = "0:0:0"
        var segmentOffset = 0

        while let cursor = currentCursor {
            #if DEBUG
            NSLog("📄 Fetching page with cursor: \(cursor)")
            #endif
            let response = try await fetchPagedSegments(curlRequest: curlRequest, cursor: cursor, segmentOffset: segmentOffset)
            allSegments.append(contentsOf: response.segments)
            segmentOffset += response.segments.count

            if response.hasMore {
                currentCursor = response.nextCursor
            } else {
                currentCursor = nil
            }
        }

        #if DEBUG
        NSLog("✅ Fetched total of \(allSegments.count) segments across all pages")
        #endif
        return allSegments
    }

    private func fetchPagedSegments(curlRequest: CURLRequest, cursor: String, segmentOffset: Int) async throws -> PaginatedResponse {
        // Build URL with cursor and per_page params
        var urlComponents = URLComponents(url: curlRequest.url, resolvingAgainstBaseURL: false)!

        // Get existing per_page or default to 100
        var queryItems = urlComponents.queryItems ?? []
        let perPage = queryItems.first(where: { $0.name == "per_page" })?.value ?? "100"

        // Update cursor and ensure per_page is set
        queryItems.removeAll(where: { $0.name == "cursor" || $0.name == "per_page" })
        queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        queryItems.append(URLQueryItem(name: "per_page", value: perPage))
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidResponse
        }

        // Build request with filtered headers and cookies
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add filtered headers
        for (key, value) in curlRequest.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add cookies
        if !curlRequest.cookies.isEmpty {
            let cookieString = curlRequest.cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }

        NSLog("🌐 Fetching: \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        // Parse Link header for pagination
        let linkHeader = httpResponse.value(forHTTPHeaderField: "Link") ?? ""
        let (nextCursor, hasMore) = parseLinkHeader(linkHeader)

        // Parse segments from response
        // The API returns an array of arrays: [segment0_events[], segment1_events[], ...]
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        guard let outerArray = jsonObject as? [Any] else {
            #if DEBUG
            NSLog("❌ Expected array, got: \(type(of: jsonObject))")
            #endif
            throw APIError.decodingError
        }

        #if DEBUG
        NSLog("📦 Response has \(outerArray.count) segments")
        #endif

        // Parse each segment (which is an array of events)
        var segments: [ReplaySegment] = []

        for (index, item) in outerArray.enumerated() {
            guard let eventsArray = item as? [[String: Any]] else {
                #if DEBUG
                NSLog("⚠️ Segment \(index) is not an array of events, skipping")
                #endif
                continue
            }

            let globalSegmentIndex = segmentOffset + index
            #if DEBUG
            NSLog("📦 Segment \(globalSegmentIndex) has \(eventsArray.count) events")
            #endif

            // Parse events for this segment
            let events = eventsArray.enumerated().compactMap { eventIndex, eventData -> ReplayEvent? in
                let id = eventData["id"] as? String ?? "event-\(globalSegmentIndex)-\(eventIndex)"
                let type = parseEventType(eventData["type"])
                let timestamp = parseTimestamp(from: eventData["timestamp"]) ?? Date()
                let data = eventData["data"] as? [String: Any] ?? eventData

                return ReplayEvent(id: id, type: type, timestamp: timestamp, data: data)
            }

            // Use first event timestamp as segment timestamp
            let segmentTimestamp = events.first?.timestamp ?? Date()

            let segment = ReplaySegment(
                id: "segment-\(globalSegmentIndex)",
                timestamp: segmentTimestamp,
                events: events
            )
            segments.append(segment)
        }

        #if DEBUG
        NSLog("✅ Parsed \(segments.count) segments with total of \(segments.reduce(0) { $0 + $1.events(useSortedOrder: false).count }) events")
        #endif

        return PaginatedResponse(segments: segments, nextCursor: nextCursor, hasMore: hasMore)
    }

    private func parseLinkHeader(_ linkHeader: String) -> (nextCursor: String?, hasMore: Bool) {
        // Parse Link header format:
        // <URL>; rel="next"; results="true"; cursor="0:100:0"

        let links = linkHeader.components(separatedBy: ",")

        for link in links {
            let parts = link.components(separatedBy: ";")

            // Check if this is the "next" link
            let isNext = parts.contains(where: { $0.trimmingCharacters(in: .whitespaces).contains("rel=\"next\"") })

            if isNext {
                // Check if results="true" (meaning there are more results)
                let hasResults = parts.contains(where: { $0.trimmingCharacters(in: .whitespaces).contains("results=\"true\"") })

                if !hasResults {
                    // No more results, stop pagination
                    return (nil, false)
                }

                // Extract cursor value
                for part in parts {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("cursor=\"") {
                        let cursorValue = trimmed
                            .replacingOccurrences(of: "cursor=\"", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                        return (cursorValue, true)
                    }
                }
            }
        }

        return (nil, false)
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