import Foundation

struct UserProfile: Codable {
    let name: String
    let email: String
    let avatarURL: URL?
    let isSuperuser: Bool

    private static let sentryBase = "https://bv.ngrok.io"

    init(from json: [String: Any]) {
        self.name = json["name"] as? String ?? ""
        self.email = json["email"] as? String ?? ""
        self.isSuperuser = json["isSuperuser"] as? Bool
            ?? (json["is_superuser"] as? Bool ?? false)

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
                !avatarUrl.isEmpty {
            if avatarUrl.hasPrefix("http") {
                self.avatarURL = URL(string: avatarUrl)
            } else {
                self.avatarURL = URL(string: Self.sentryBase + avatarUrl)
            }
        } else {
            self.avatarURL = nil
        }
    }

    init(name: String, email: String, avatarURL: URL?, isSuperuser: Bool = false) {
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
        self.isSuperuser = isSuperuser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.email = try container.decode(String.self, forKey: .email)
        self.avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        self.isSuperuser = try container.decodeIfPresent(Bool.self, forKey: .isSuperuser) ?? false
    }
}
