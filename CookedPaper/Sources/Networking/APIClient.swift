import Foundation

enum APIConfig {
    /// The API behind Cloudflare on the DigitalOcean droplet (see
    /// `docs/deploy-digitalocean.md` in the backend repo). Change this one constant
    /// if the domain differs, or to point at a local API during development.
    static let baseURL = URL(string: "https://api.cooked.trade")!
}

struct Endpoint {
    var path: String
    var method: String = "GET"
    var query: [String: String?] = [:]
    var body: Data? = nil
    /// Off only for the sign-in calls themselves, made before a session exists.
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
        // The refresh token travels in the body for this app, but cookies stay on so
        // a server that only sets the cookie still works.
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        #if DEBUG
        // UI screenshot runs only — see `MockAPI`.
        if MockAPI.isEnabled {
            config.protocolClasses = [MockURLProtocol.self as AnyClass] + (config.protocolClasses ?? [])
        }
        #endif
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

        if http.statusCode == 401, retryingOnAuthFailure, let refreshToken = SessionStore.shared.refreshToken {
            // The short-lived access token expired. Trade the refresh token for a new
            // session and retry exactly once — a second 401 after a fresh token is a
            // real failure, not a race to paper over.
            if let refreshed = try? await AuthAPI.refresh(refreshToken: refreshToken) {
                SessionStore.shared.adopt(refreshed)
                return try await send(endpoint, as: type, retryingOnAuthFailure: false)
            }
        }
        if http.statusCode == 401, endpoint.attachToken, SessionStore.shared.isSignedIn {
            // The refresh token is gone or revoked: the session is over. Sending the
            // person back to sign-in beats a screen of silent failures.
            SessionStore.shared.clear()
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

        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty // 204 No Content
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
        // Asks the auth routes for the refresh token in the body (web gets a cookie).
        request.setValue("ios", forHTTPHeaderField: "X-Cooked-Client")
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
