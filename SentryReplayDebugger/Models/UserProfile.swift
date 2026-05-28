import Foundation

struct UserProfile: Codable {
    let name: String
    let email: String
    let avatarURL: URL?

    private static let sentryBase = "https://sentry.io"

    init(from json: [String: Any]) {
        self.name = json["name"] as? String ?? ""
        self.email = json["email"] as? String ?? ""

        // OAuth userinfo format: top-level avatar_url
        if let avatarUrl = json["avatar_url"] as? String, !avatarUrl.isEmpty {
            if avatarUrl.hasPrefix("http") {
                self.avatarURL = URL(string: avatarUrl)
            } else {
                self.avatarURL = URL(string: Self.sentryBase + avatarUrl)
            }
        }
        // Legacy format: nested avatar object
        else if let avatar = json["avatar"] as? [String: Any],
            let avatarUrl = avatar["avatarUrl"] as? String,
            !avatarUrl.isEmpty
        {
            if avatarUrl.hasPrefix("http") {
                self.avatarURL = URL(string: avatarUrl)
            } else {
                self.avatarURL = URL(string: Self.sentryBase + avatarUrl)
            }
        } else {
            self.avatarURL = nil
        }
    }

    init(name: String, email: String, avatarURL: URL?) {
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
    }
}
