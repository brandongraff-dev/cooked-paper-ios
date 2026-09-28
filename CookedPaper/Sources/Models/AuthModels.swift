import Foundation

struct PublicUser: Decodable {
    let id: String
    let username: String
    let displayName: String?
    let walletAddress: String
    let foundingMember: Bool
}

/// The session shape `/auth/refresh` returns.
struct SessionResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let user: PublicUser
}
