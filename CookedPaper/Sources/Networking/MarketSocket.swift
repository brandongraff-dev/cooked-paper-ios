import Foundation
import SocketIO

/// What the `/market` namespace tells one subscribed mint's feed.
enum MarketSocketEvent {
    /// The `subscribe` ack: a full snapshot, same shape as the REST endpoint.
    case snapshot(LiveMarketSnapshot)
    case trades(MarketTradesMessage)
    case status(MarketStatus)
    /// The connection dropped; the feed falls back to polling until the next ack.
    case disconnected
}

/// The `/market` Socket.IO namespace (live trades per mint) on the same server and
/// base URL as `LiveSocket`'s `/paper`. It has its own manager rather than sharing
/// `LiveSocket`'s: that one exists only while a portfolio is subscribed and is torn
/// down with it, while market data is public and is wanted on a token page even
/// signed out. The bearer token is attached when there is one (the namespace uses
/// the same auth as `/paper` but lets public token data through without it), and is
/// re-read before every reconnect (see `SocketAuth`).
///
/// Nothing here is load-bearing for correctness: `MarketFeed` polls the REST
/// endpoint whenever this isn't connected and subscribed, so a server without the
/// namespace, a flaky network, or the UI-test mock just means 1 s polling.
@MainActor
final class MarketSocket {
    static let shared = MarketSocket()

    private(set) var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var listeners: [String: (MarketSocketEvent) -> Void] = [:]
    /// Leaving one token for another shouldn't cost a reconnect, so the connection
    /// outlives its last subscriber by a few seconds.
    private var idleDisconnect: Task<Void, Never>?
    private var isRecoveringAuth = false

    private init() {}

    /// Starts delivering `mint`'s events to `onEvent` (replacing any earlier
    /// listener for it). Connects on first use; resubscribes after every reconnect.
    func subscribe(mint: String, onEvent: @escaping (MarketSocketEvent) -> Void) {
        #if DEBUG
        // The UI-test mock is a URLProtocol; it can't serve a socket. Feeds poll.
        if MockAPI.isEnabled { return }
        #endif
        idleDisconnect?.cancel()
        idleDisconnect = nil
        listeners[mint] = onEvent
        if socket == nil {
            connect()
        } else if isConnected {
            sendSubscribe(mint)
        }
    }

    func unsubscribe(mint: String) {
        guard listeners.removeValue(forKey: mint) != nil else { return }
        if isConnected {
            socket?.emit("unsubscribe", ["mint": mint] as [String: Any])
        }
        guard listeners.isEmpty else { return }
        idleDisconnect?.cancel()
        idleDisconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.listeners.isEmpty else { return }
            self.disconnect()
        }
    }

    private func connect() {
        // Reconnect quickly: while disconnected the chart is on 1 s polling, which
        // works but costs more than the socket. The token (when signed in) is read
        // now and again before every automatic reconnect, never kept from here.
        let manager = SocketManager(
            socketURL: APIConfig.baseURL,
            config: [.log(false), .compress, .reconnectWait(1), .reconnectWaitMax(5), .extraHeaders(SocketAuth.currentHeaders())]
        )
        self.manager = manager
        let socket = manager.socket(forNamespace: "/market")
        self.socket = socket

        // Fires on the first connect and again after every automatic reconnect —
        // Socket.IO room state lives in server memory, so every connect resubscribes.
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.isConnected = true
            for mint in self.listeners.keys { self.sendSubscribe(mint) }
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.connectionDropped()
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.connectionDropped()
        }
        // A reconnect is a new handshake; give it the access token as of now rather
        // than the one this manager was created with.
        socket.on(clientEvent: .reconnectAttempt) { [weak manager] _, _ in
            guard let manager else { return }
            SocketAuth.refreshHeaders(on: manager)
        }
        // `/market` is public today, so a refused token shouldn't happen; if the
        // namespace ever does check it, refresh and reconnect rather than polling
        // forever.
        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self, SocketAuth.isAuthFailure(data) else { return }
            self.recoverFromAuthFailure()
        }
        socket.on("trades") { [weak self] data, _ in
            guard let self, let message = MarketSocket.decode(MarketTradesMessage.self, from: data) else { return }
            self.listeners[message.mint]?(.trades(message))
        }
        socket.on("status") { [weak self] data, _ in
            guard let self, let message = MarketSocket.decode(MarketStatusMessage.self, from: data) else { return }
            self.listeners[message.mint]?(.status(message.status))
        }
        socket.connect()
    }

    private func recoverFromAuthFailure() {
        guard !isRecoveringAuth else { return }
        isRecoveringAuth = true
        Task { [weak self] in
            let refreshed = await APIClient.shared.refreshSession()
            guard let self else { return }
            self.isRecoveringAuth = false
            guard refreshed, !self.listeners.isEmpty else { return }
            self.disconnect()
            self.connect()
        }
    }

    private func sendSubscribe(_ mint: String) {
        guard let socket else { return }
        socket.emitWithAck("subscribe", ["mint": mint] as [String: Any]).timingOut(after: 5) { [weak self] data in
            // A timeout acks with "NO ACK", which doesn't decode: the feed simply
            // keeps polling until a later reconnect's subscribe succeeds.
            guard let self, let snapshot = MarketSocket.decode(LiveMarketSnapshot.self, from: data) else { return }
            self.listeners[mint]?(.snapshot(snapshot))
        }
    }

    private func connectionDropped() {
        guard isConnected else { return }
        isConnected = false
        for listener in listeners.values { listener(.disconnected) }
    }

    private func disconnect() {
        connectionDropped()
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: [Any]) -> Value? {
        guard let object = data.first,
              JSONSerialization.isValidJSONObject(object),
              let json = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? JSONDecoder().decode(type, from: json)
    }
}
