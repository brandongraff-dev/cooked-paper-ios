import Foundation

/// Share cards (`auth: 'public'` — the share URL is the capability).
enum CardsAPI {
    static func meta(subjectPath: String) async throws -> ShareCardMeta {
        try await APIClient.shared.send(
            Endpoint(path: "/cards/meta/\(subjectPath)", attachToken: false),
            as: ShareCardMeta.self
        )
    }
}
