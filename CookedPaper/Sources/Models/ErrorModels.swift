import Foundation

/// Mirrors `ErrorBody` in `packages/api-types/src/errors.ts` — every error response
/// shares this one shape. `code` is left as a raw `String` rather than an enum: the
/// server's error-code list is long, changes independently of this app, and every
/// call site that matters (insufficient cash, stale quote) checks the specific string
/// it cares about rather than exhaustively switching over all of them.
struct APIErrorBody: Decodable {
    let error: String
    let message: String
    /// Detail the server spreads next to `error`, e.g. `reason: "insufficient_cash"`.
    var reason: String? = nil
    var status: String? = nil
}

enum APIError: Error, LocalizedError {
    case server(status: Int, body: APIErrorBody)
    case decoding(underlying: Error)
    case transport(underlying: Error)
    case unauthenticated

    var errorDescription: String? {
        switch self {
        case .server(_, let body): body.message
        case .decoding: "The app couldn't understand that response."
        case .transport(let underlying): underlying.localizedDescription
        case .unauthenticated: "Sign in again to continue."
        }
    }

    /// The specific, well-known codes a call site branches on. Every other code
    /// (`bad_request`, `not_found`, …) is handled generically via `errorDescription`.
    var code: String? {
        if case .server(_, let body) = self { return body.error }
        return nil
    }

    /// The server's machine-readable `reason`, when it sent one.
    var reason: String? {
        if case .server(_, let body) = self { return body.reason }
        return nil
    }
}
