import Foundation

struct SentryURLComponents {
    let orgSlug: String
    let projectId: String
    let replayId: String
}

enum SentryURLParseError: LocalizedError {
    case invalidURL
    case missingProjectId
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Not a valid URL"
        case .missingProjectId:
            return "URL is missing the ?project= parameter"
        case .unrecognizedFormat:
            return "URL doesn't match a known Sentry replay URL format"
        }
    }
}

struct SentryURLParser {
    static func parse(url: String) throws -> SentryURLComponents {
        guard let url = URL(string: url), url.scheme != nil else {
            throw SentryURLParseError.invalidURL
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let projectId = queryItems?.first(where: { $0.name == "project" })?.value

        // Format 1: /organizations/{org}/replays/{id}
        if pathComponents.count >= 4,
           pathComponents[0] == "organizations",
           pathComponents[2] == "replays",
           !pathComponents[1].isEmpty,
           !pathComponents[3].isEmpty {
            guard let projectId else { throw SentryURLParseError.missingProjectId }
            let orgSlug = pathComponents[1]
            let replayId = pathComponents[3].components(separatedBy: "?").first ?? pathComponents[3]
            return SentryURLComponents(orgSlug: orgSlug, projectId: projectId, replayId: replayId)
        }

        // Format 2: https://{org}.sentry.io/explore/replays/{id}?project={projectId}
        if let host = url.host,
           pathComponents.count >= 3,
           pathComponents[0] == "explore",
           pathComponents[1] == "replays",
           !pathComponents[2].isEmpty,
           let orgSlug = extractOrgFromHost(host),
           !orgSlug.isEmpty {
            guard let projectId else { throw SentryURLParseError.missingProjectId }
            let replayId = pathComponents[2].components(separatedBy: "?").first ?? pathComponents[2]
            return SentryURLComponents(orgSlug: orgSlug, projectId: projectId, replayId: replayId)
        }

        throw SentryURLParseError.unrecognizedFormat
    }

    /// Returns nil instead of throwing — for use in detection checks (e.g. clipboard routing).
    static func canParse(url: String) -> Bool {
        return (try? parse(url: url)) != nil
    }

    private static func extractOrgFromHost(_ host: String) -> String? {
        let parts = host.split(separator: ".")
        // e.g. "sentry.sentry.io" → ["sentry", "sentry", "io"] → org = "sentry"
        guard parts.count >= 3,
              parts[parts.count - 1] == "io",
              parts[parts.count - 2] == "sentry" else {
            return nil
        }
        let orgParts = parts.dropLast(2)
        return orgParts.joined(separator: ".")
    }
}
