import Foundation

struct PaginatedResponse {
    let segments: [ReplaySegment]
    let nextCursor: String?
    let hasMore: Bool
}

class SentryAPIService: ObservableObject {
    static let shared = SentryAPIService()

    private let baseURL = "https://us.sentry.io/api/0"
    private let session = URLSession.shared

    private init() {}

    func fetchUserProfile() async throws -> UserProfile {
        let url = URL(string: "https://sentry.io/oauth/userinfo/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addStandardHeaders(to: &request)

        if let authToken = await getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performRequest(request)

        if let body = String(data: data, encoding: .utf8) {
            NSLog("📋 oauth/userinfo response: \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError
        }

        return UserProfile(from: json)
    }

    func fetchIsSuperuser() async -> Bool {
        let url = URL(string: "https://sentry.io/api/0/users/me/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addStandardHeaders(to: &request)

        if let authToken = await getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            if let body = String(data: data, encoding: .utf8) {
                NSLog("📋 users/me response: \(body)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return json["isSuperuser"] as? Bool
                ?? (json["is_superuser"] as? Bool ?? false)
        } catch {
            NSLog("⚠️ Failed to fetch superuser status: \(error.localizedDescription)")
            return false
        }
    }

    func fetchReplaySegments(orgSlug: String, projectId: String, replayId: String) async throws -> [ReplaySegment] {
        let url = URL(string: "\(baseURL)/projects/\(orgSlug)/\(projectId)/replays/\(replayId)/recording-segments/?download=true&per_page=100")!
        NSLog("🌐 Fetching replay segments: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addStandardHeaders(to: &request)
        
        if let authToken = await getAuthToken() {
            #if DEBUG
            NSLog("🔑 Using auth token: \(authToken.prefix(8))...")
            #endif
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else {
            NSLog("⚠️ No auth token available")
        }
        
        let (data, _) = try await performRequest(request)

        let jsonObject = try JSONSerialization.jsonObject(with: data)

        // Response with download=true is [[event, ...], [event, ...], ...]
        // Each inner array is one segment's rrweb events
        guard let outerArray = jsonObject as? [Any] else {
            throw APIError.decodingError
        }

        var segments: [ReplaySegment] = []
        for (index, item) in outerArray.enumerated() {
            if let eventsArray = item as? [[String: Any]] {
                let events = eventsArray.enumerated().map { eventIndex, eventData in
                    let id = eventData["id"] as? String ?? "event-\(eventIndex)"
                    let type = parseEventType(eventData["type"])
                    let timestamp = parseTimestamp(from: eventData["timestamp"]) ?? Date()
                    let data = eventData["data"] as? [String: Any] ?? eventData
                    return ReplayEvent(id: id, type: type, timestamp: timestamp, data: data)
                }
                let timestamp = events.first?.timestamp ?? Date()
                segments.append(ReplaySegment(id: "segment-\(index)", timestamp: timestamp, events: events))
            }
        }

        NSLog("✅ Parsed \(segments.count) segments from API")
        guard !segments.isEmpty else { throw APIError.decodingError }
        return segments
    }
    
    private func getAuthToken() async -> String? {
        return await AuthService.shared.validAccessToken()
    }

    private func addStandardHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
    }

    /// Perform a request with reactive 401 retry: on 401, refresh the token and retry once.
    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            // Reactive refresh: try to get a new token and retry once
            if let newToken = await AuthService.shared.handleUnauthorizedAndRetry() {
                var retryRequest = request
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

                let (retryData, retryResponse) = try await session.data(for: retryRequest)
                guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                guard retryHttpResponse.statusCode == 200 else {
                    if retryHttpResponse.statusCode == 401 {
                        await AuthService.shared.logout()
                    }
                    throw APIError.httpError(retryHttpResponse.statusCode)
                }

                return (retryData, retryHttpResponse)
            }

            throw APIError.httpError(401)
        }

        if httpResponse.statusCode == 403 {
            throw APIError.superuserRequired(originalRequest: request)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            NSLog("❌ HTTP \(httpResponse.statusCode): \(body)")
            throw APIError.httpError(httpResponse.statusCode)
        }

        return (data, httpResponse)
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

        if httpResponse.statusCode == 403 {
            throw APIError.superuserRequired(originalRequest: request)
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
    case superuserRequired(originalRequest: URLRequest)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error with status code: \(code)"
        case .decodingError:
            return "Failed to decode response data"
        case .superuserRequired:
            return "Superuser access required"
        }
    }
}