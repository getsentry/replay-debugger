import Foundation

struct CURLRequest {
    let url: URL
    let headers: [String: String]
    let cookies: [String: String]
}

class CURLParser {

    // Standard headers to include
    private static let allowedHeaders = [
        "accept",
        "accept-language",
        "cache-control",
        "content-type",
        "origin",
        "pragma",
        "referer",
        "user-agent",
    ]

    static func parse(curlCommand: String) throws -> CURLRequest {
        // Remove newlines and extra spaces
        let normalized =
            curlCommand
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\n", with: " ")

        // Extract URL (first argument after 'curl')
        guard let url = extractURL(from: normalized) else {
            throw CURLParserError.invalidURL
        }

        // Extract headers
        let allHeaders = extractHeaders(from: normalized)
        let filteredHeaders = filterHeaders(allHeaders)

        // Extract cookies
        let allCookies = extractCookies(from: normalized)
        let filteredCookies = filterCookies(allCookies)

        return CURLRequest(url: url, headers: filteredHeaders, cookies: filteredCookies)
    }

    private static func extractURL(from command: String) -> URL? {
        // Match URL after 'curl' - handles both quoted and unquoted URLs
        let patterns = [
            "curl\\s+'([^']+)'",  // Single quoted
            "curl\\s+\"([^\"]+)\"",  // Double quoted
            "curl\\s+([^\\s-][^\\s]+)",  // Unquoted (stops at space or dash)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                let urlRange = Range(match.range(at: 1), in: command)
            {
                let urlString = String(command[urlRange])
                if let url = URL(string: urlString) {
                    return url
                }
            }
        }

        return nil
    }

    private static func extractHeaders(from command: String) -> [String: String] {
        var headers: [String: String] = [:]

        // Match -H 'header: value' or -H "header: value"
        let patterns = [
            "-H\\s+'([^:]+):\\s*([^']+)'",  // Single quoted
            "-H\\s+\"([^:]+):\\s*([^\"]+)\"",  // Double quoted
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: command),
                    let valueRange = Range(match.range(at: 2), in: command)
                {
                    let name = String(command[nameRange]).trimmingCharacters(in: .whitespaces)
                    let value = String(command[valueRange]).trimmingCharacters(in: .whitespaces)
                    headers[name.lowercased()] = value
                }
            }
        }

        return headers
    }

    private static func extractCookies(from command: String) -> [String: String] {
        var cookies: [String: String] = [:]

        // Match -b 'cookie1=value1; cookie2=value2' or --cookie
        let patterns = [
            "-b\\s+'([^']+)'",
            "-b\\s+\"([^\"]+)\"",
            "--cookie\\s+'([^']+)'",
            "--cookie\\s+\"([^\"]+)\"",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            if let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                let cookieRange = Range(match.range(at: 1), in: command)
            {
                let cookieString = String(command[cookieRange])

                // Parse cookie string: "name1=value1; name2=value2"
                let cookiePairs = cookieString.split(separator: ";")
                for pair in cookiePairs {
                    let components = pair.split(separator: "=", maxSplits: 1)
                    if components.count == 2 {
                        let name = components[0].trimmingCharacters(in: .whitespaces)
                        let value = components[1].trimmingCharacters(in: .whitespaces)
                        cookies[name] = value
                    }
                }
            }
        }

        return cookies
    }

    private static func filterHeaders(_ headers: [String: String]) -> [String: String] {
        return headers.filter { key, _ in
            allowedHeaders.contains(key.lowercased())
        }
    }

    private static func filterCookies(_ cookies: [String: String]) -> [String: String] {
        return cookies.filter { name, _ in
            name.lowercased().hasPrefix("sentry-") || name.lowercased() == "session"
        }
    }
}

enum CURLParserError: LocalizedError {
    case invalidURL
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not extract valid URL from CURL command"
        case .invalidFormat:
            return "Invalid CURL command format"
        }
    }
}
