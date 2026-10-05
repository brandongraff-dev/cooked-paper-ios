import Foundation
import SocketIO

/// How both sockets (`LiveSocket`'s `/paper`, `MarketSocket`'s `/market`) carry the
/// bearer token. The server reads it from the handshake — `auth.token` first, then
/// the `Authorization` header (apps/api `extractToken`) — and only at the handshake.
///
/// The header is used, not the `auth` payload: Socket.IO-Client-Swift resends the
/// payload it was first given on every automatic reconnect, and the payload wins
/// over the header server-side, so a payload would pin the socket to whatever token
/// was current when it first connected. The header, by contrast, is reread from the
/// manager's config on each new engine handshake, so `refreshHeaders(on:)` (called
/// on every `.reconnectAttempt`) is enough for a reconnect ~15 minutes later to
/// present the access token `APIClient` has refreshed since.
enum SocketAuth {
    /// The Engine.IO path both sockets connect on. The API mounts Socket.IO at
    /// `/trading/ws` (apps/api `REALTIME_PATH`), not the library default
    /// `/socket.io/`, which 404s.
    static let realtimePath = "/trading/ws/"

    /// The headers for a handshake made right now: the current access token, or the
    /// guest paper token before sign-in (`/paper` accepts both), if any.
    static func currentHeaders() -> [String: String] {
        guard let token = SessionStore.shared.bearerToken else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    /// Swaps the manager's `Authorization` header for the current token. Safe on a
    /// live manager: Socket.IO applies it to the engine's next handshake.
    static func refreshHeaders(on manager: SocketManager) {
        var config = manager.config
        config.insert(.extraHeaders(currentHeaders()), replacing: true)
        manager.config = config
    }

    /// True when a namespace refused the handshake's token — the server's
    /// middleware rejects with `new Error('unauthenticated')`, which arrives as a
    /// connect-error packet surfaced on the client's `.error` event.
    static func isAuthFailure(_ data: [Any]) -> Bool {
        data.contains { item in
            if let dict = item as? [String: Any], let message = dict["message"] as? String {
                return message == "unauthenticated"
            }
            if let message = item as? String {
                return message == "unauthenticated"
            }
            return false
        }
    }
}
