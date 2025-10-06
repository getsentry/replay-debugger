import Foundation

struct SentryURLComponents {
    let orgSlug: String
    let replayId: String
}

struct SentryURLParser {
    static func parse(url: String) -> SentryURLComponents? {
        guard let url = URL(string: url) else { return nil }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 4,
              pathComponents[0] == "organizations",
              pathComponents[2] == "replays",
              !pathComponents[1].isEmpty,
              !pathComponents[3].isEmpty else {
            return nil
        }
        
        let orgSlug = pathComponents[1]
        let replayId = pathComponents[3].components(separatedBy: "?").first ?? pathComponents[3]
        
        return SentryURLComponents(orgSlug: orgSlug, replayId: replayId)
    }
}