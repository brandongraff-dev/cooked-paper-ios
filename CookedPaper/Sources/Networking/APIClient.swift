import Foundation

enum APIConfig {
    /// Same production Railway deployment `apps/mobile/lib/api.ts` falls back to.
    /// Override by editing this constant for local-worktree development — there is
    /// no other indirection on the client side (CORS/WEB_URL are server-side,
    /// browser-only concerns that don't apply to a native `URLSession`).
    static let baseURL = URL(string: "https://totem-api-production-0323.up.railway.app")!
}

struct Endpoint {
    var path: String
    var method: String = "GET"
    var query: [String: String?] = [:]
    var body: Data? = nil
    /// Every route this app calls is `auth: 'public'` or `auth: 'paper'`
    /// (real-or-guest) — there is no endpoint here that requires withholding a
    /// present token, so this only ever turns off for calls made *before* any
    /// session exists (`POST /auth/nonce` for a not-yet-linked wallet, etc.).
    var attachToken: Bool = true
}

/// A success body this app deliberately never reads past "it was 2xx".
struct EmptyResponse: Decodable {}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    private init(baseURL: URL = APIConfig.baseURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // Persistent, non-ephemeral: a real account's httpOnly refresh cookie (set by
        // /auth/verify, /auth/google, /auth/embedded/verify) must survive an app
        // relaunch exactly the way it would in a browser tab. httpOnly only blocks
        // JavaScript — native networking reads and resends it like any other cookie.
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    @discardableResult
    func send<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type,
        retryingOnAuthFailure: Bool = true
    ) async throws -> Response {
        let (data, response) = try await raw(endpoint)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(underlying: URLError(.badServerResponse))
        }

        if http.statusCode == 401, retryingOnAuthFailure, !SessionStore.shared.isGuest {
            // A real account's short-lived access token expired. Trade the httpOnly
            // refresh cookie (already in the shared jar above) for a new one and
            // retry exactly once — a second 401 after a fresh token is a real
            // failure, not a race to paper over.
            if let refreshed = try? await AuthAPI.refresh() {
                SessionStore.shared.updateAccessToken(refreshed.accessToken)
                return try await send(endpoint, as: type, retryingOnAuthFailure: false)
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            if let body = try? decoder.decode(APIErrorBody.self, from: data) {
                throw APIError.server(status: http.statusCode, body: body)
            }
            throw APIError.server(
                status: http.statusCode,
                body: APIErrorBody(error: "request_failed", message: "The request failed.")
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    func sendIgnoringResponse(_ endpoint: Endpoint) async throws {
        _ = try await send(endpoint, as: EmptyResponse.self)
    }

    private func raw(_ endpoint: Endpoint) async throws -> (Data, URLResponse) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )!
        let items = endpoint.query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components.queryItems = items }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = endpoint.body
        if endpoint.attachToken, let token = SessionStore.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }
    }
}

extension APIClient {
    /// JSON-encodes an `Encodable` body with this client's encoder, for call sites
    /// that build an `Endpoint` inline.
    func encode(_ value: some Encodable) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }
}
