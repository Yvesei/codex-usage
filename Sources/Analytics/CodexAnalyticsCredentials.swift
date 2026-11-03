import Foundation

struct CodexAnalyticsCredentials {
    let identity: ModelAnalyticsIdentity
    let accessToken: String

    private struct AuthFile: Decodable {
        let authMode: String?
        let tokens: Tokens?

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
        }
    }

    private struct Tokens: Decodable {
        let accountID: String?
        let accessToken: String
        let idToken: String

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
            case accessToken = "access_token"
            case idToken = "id_token"
        }
    }

    private struct Claims: Decodable {
        let email: String?
        let profile: Profile?
        let auth: AuthClaims?

        enum CodingKeys: String, CodingKey {
            case email
            case profile = "https://api.openai.com/profile"
            case auth = "https://api.openai.com/auth"
        }
    }

    private struct Profile: Decodable {
        let email: String?
    }

    private struct AuthClaims: Decodable {
        let accountID: String?
        let userID: String?
        let legacyUserID: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "chatgpt_account_id"
            case userID = "chatgpt_user_id"
            case legacyUserID = "user_id"
        }
    }

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexAnalyticsCredentials {
        let codexHome: URL
        if let value = environment["CODEX_HOME"], !value.isEmpty {
            codexHome = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath, isDirectory: true)
        } else {
            codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }

        let file = codexHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: file),
              data.count <= 1024 * 1024,
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              auth.authMode == nil || auth.authMode == "chatgpt" || auth.authMode == "chatgpt_auth_tokens",
              let tokens = auth.tokens,
              let claims = decodeClaims(tokens.idToken),
              let accountID = nonempty(tokens.accountID ?? claims.auth?.accountID),
              let userID = nonempty(claims.auth?.userID ?? claims.auth?.legacyUserID),
              let token = nonempty(tokens.accessToken) else {
            throw ModelAnalyticsError.signInRequired
        }

        let identity = ModelAnalyticsIdentity(
            accountID: accountID,
            userID: userID,
            email: nonempty(claims.email ?? claims.profile?.email)
        )
        return CodexAnalyticsCredentials(identity: identity, accessToken: token)
    }

    private static func decodeClaims(_ token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+")
        payload = payload.replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        return try? JSONDecoder().decode(Claims.self, from: data)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return value
    }
}
