import Foundation

enum APIConfig {
    /// Production: the API behind Cloudflare (see `docs/deploy-oracle.md` in the
    /// backend repo). Also the fallback whenever the build doesn't name a usable URL.
    static let productionURL = URL(string: "https://api.cooked.trade")!

    /// The API every REST call and both sockets (`/paper`, `/market`) talk to. Read
    /// from the `COOKED_API_BASE_URL` Info.plist key, which `project.yml` fills from
    /// the build setting of the same name per configuration (Debug and Release both
    /// default to production). Point Debug at a local or staging API by changing that
    /// setting — see the README's "API base URL" section.
    static let baseURL: URL = resolveBaseURL(Bundle.main.object(forInfoDictionaryKey: "COOKED_API_BASE_URL") as? String)

    /// Anything unusable — missing, empty, an unexpanded `$(…)`, or not an
    /// http(s) URL with a host — falls back to production rather than leaving every
    /// request pointed at nothing.
    static func resolveBaseURL(_ raw: String?) -> URL {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("$("),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return productionURL }
        return url
    }
}

struct Endpoint {
    var path: String
    var method: String = "GET"
    var query: [String: String?] = [:]
    var body: Data? = nil
    /// Off only for the sign-in calls themselves, made before a session exists.
    var attachToken: Bool = true
    /// Off for calls whose 401 can be about something other than the account's
    /// session (claiming a guest token that has expired), so they never sign out.
    var signsOutOnUnauthorized: Bool = true
}

/// A success body this app deliberately never reads past "it was 2xx".
struct EmptyResponse: Decodable {}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    /// The refresh in flight, if any (see `refreshSession()`).
    private var refreshTask: Task<Bool, Never>?
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

        if http.statusCode == 401, retryingOnAuthFailure, SessionStore.shared.refreshToken != nil {
            // The short-lived access token expired. Trade the refresh token for a new
            // session and retry exactly once — a second 401 after a fresh token is a
            // real failure, not a race to paper over.
            if await refreshSession() {
                return try await send(endpoint, as: type, retryingOnAuthFailure: false)
            }
        }
        if http.statusCode == 401, endpoint.attachToken, endpoint.signsOutOnUnauthorized, SessionStore.shared.isSignedIn {
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

    /// Trades the stored refresh token for a new session and adopts it. The one
    /// refresh path in the app: a 401 here and a socket refused at its handshake
    /// both come through this. Concurrent callers share a single request, so a
    /// burst of 401s (or a 401 racing a socket rejection) can't spend the refresh
    /// token twice. False when there's no refresh token or the server refused it.
    @discardableResult
    func refreshSession() async -> Bool {
        if let inFlight = refreshTask {
            return await inFlight.value
        }
        guard let refreshToken = SessionStore.shared.refreshToken else { return false }
        let task = Task<Bool, Never> {
            guard let refreshed = try? await AuthAPI.refresh(refreshToken: refreshToken) else { return false }
            SessionStore.shared.adopt(refreshed)
            return true
        }
        refreshTask = task
        let refreshed = await task.value
        refreshTask = nil
        return refreshed
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
        // The account's token, or the guest paper session's before sign-in.
        if endpoint.attachToken, let token = SessionStore.shared.bearerToken {
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
