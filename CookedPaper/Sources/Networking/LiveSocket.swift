import Foundation
import Observation
import SocketIO

/// The `/paper` Socket.IO namespace: live equity/PnL pushes for one subscribed
/// portfolio (apps/api/src/paper/live). This is additive to `PaperAPI.snapshot` —
/// the REST call is still what loads the screen; this only keeps it current without
/// polling. If the socket is unreachable the portfolio screen simply falls back to
/// whatever it last fetched, which is why nothing here is load-bearing for
/// correctness, only for "feels live."
@Observable
@MainActor
final class LiveSocket {
    static let shared = LiveSocket()

    private(set) var latestTick: PaperLiveTick?
    private(set) var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var subscribedPortfolioId: String?

    // The resume half of the protocol: a client that reconnects with the last seq it
    // saw gets a `gap` block back describing what it missed, instead of silently
    // skipping updates. Keyed by portfolio id, not held as a single value, so
    // switching portfolios never resumes into the wrong one's sequence.
    private var lastSeenSeq: [String: Int] = [:]

    // A dead socket looks identical to a quiet market unless something times it out —
    // `heartbeatIntervalMs` (published on every tick) is that timeout. Rearmed on
    // every tick; if it ever fires, silence has outlasted the server's own heartbeat,
    // so the connection is presumed dead and torn down and rebuilt from scratch.
    private var heartbeatWatchdog: Task<Void, Never>?

    private init() {}

    func connectAndSubscribe(portfolioId: String) {
        #if DEBUG
        // Demo data has no live feed behind it; the REST snapshot is the whole picture.
        if MockAPI.isEnabled { return }
        #endif
        guard let token = SessionStore.shared.token else { return }

        if subscribedPortfolioId == portfolioId, isConnected {
            return
        }

        disconnect()
        subscribedPortfolioId = portfolioId

        let manager = SocketManager(
            socketURL: APIConfig.baseURL,
            config: [
                .log(false),
                .compress,
                .extraHeaders(["Authorization": "Bearer \(token)"]),
            ]
        )
        self.manager = manager
        let socket = manager.socket(forNamespace: "/paper")
        self.socket = socket

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.isConnected = true
            socket.emit("paper:subscribe", self.subscribePayload(portfolioId: portfolioId))
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.isConnected = false
        }
        // A liveness beat on any connected-but-unsubscribed socket (e.g. right after
        // a server restart, since Socket.IO room state is in-memory) — resubscribe.
        // Passing sinceSeq here is what turns that resubscribe into a resume; if the
        // restart also reset the server's seq counter, the resulting tick's
        // `gap.counterReset` says so.
        socket.on("paper:error") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any], dict["code"] as? String == "not_subscribed" else { return }
            socket.emit("paper:subscribe", self.subscribePayload(portfolioId: portfolioId))
        }
        socket.on("paper:tick") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let tick = try? JSONDecoder().decode(PaperLiveTick.self, from: json)
            else { return }
            self.latestTick = tick
            self.lastSeenSeq[tick.portfolioId] = tick.seq
            self.armHeartbeatWatchdog(portfolioId: tick.portfolioId, intervalMs: tick.heartbeatIntervalMs)
        }

        socket.connect()
    }

    func disconnect() {
        heartbeatWatchdog?.cancel()
        heartbeatWatchdog = nil
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        subscribedPortfolioId = nil
        isConnected = false
        latestTick = nil
    }

    private func subscribePayload(portfolioId: String) -> [String: Any] {
        guard let sinceSeq = lastSeenSeq[portfolioId] else {
            return ["portfolioId": portfolioId]
        }
        return ["portfolioId": portfolioId, "sinceSeq": sinceSeq]
    }

    private func armHeartbeatWatchdog(portfolioId: String, intervalMs: Int) {
        heartbeatWatchdog?.cancel()
        heartbeatWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(intervalMs))
            guard !Task.isCancelled, let self, self.subscribedPortfolioId == portfolioId else { return }
            // `disconnect()` cancels this same task, but cancelling from inside your
            // own already-running body is a no-op — this still runs to completion and
            // reconnects. `lastSeenSeq` survives `disconnect()`, so the reconnect
            // below resumes rather than starting the portfolio over.
            self.disconnect()
            self.connectAndSubscribe(portfolioId: portfolioId)
        }
    }
}
