import Foundation

struct PublicUser: Decodable {
    let id: String
    let username: String
    let displayName: String?
    let walletAddress: String
    let foundingMember: Bool
}

/// The one session shape every login door returns — `/auth/verify`,
/// `/auth/google`, `/auth/embedded/verify`, `/auth/refresh` all produce this.
struct SessionResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let user: PublicUser
}

struct NonceResponse: Decodable {
    let message: String
    let nonce: String
    let expiresAt: String
}

struct ClaimGuestPortfoliosResponse: Decodable {
    let claimed: [PaperPortfolio]
    let skipped: [PaperPortfolio]
}
