import Foundation
import Observation

/// One token's live trade tape, kept current from the `/market` socket when it's
/// connected and from 1 s REST polls when it isn't (always, under the UI-test mock,
/// which can't serve a socket). Nothing here invents a price: the tape is the
/// server's trades, deduped and time-sorted; the chart plays it back with a small
/// delay (see `MarketPlayback`) and only eases between two real prices.
@Observable
@MainActor
final class MarketFeed {
    let mint: String

    /// The last ~10 minutes of trades and price observations, oldest first.
    private(set) var tape: [TapePoint] = []
    /// The latest full snapshot's 1 s candles, for the LIVE candle view.
    private(set) var oneSecondCandles: [LiveCandle] = []
    private(set) var status: MarketStatus?
    /// How far behind the server clock the chart plays (server-set, clamped).
    private(set) var displayDelayMs = MarketPlayback.defaultDelayMs
    /// When anything last arrived, socket or poll. Drives the local "Delayed" state
    /// when the network, not the server, is what's behind.
    private(set) var lastUpdate: Date?

    @ObservationIgnored private var ids = Set<String>()
    @ObservationIgnored private var lastSeq: Int?
    /// Server clock minus device clock, so the playhead follows the server's time
    /// even on a phone whose clock is a few seconds off.
    @ObservationIgnored private var clockOffsetMs: Double = 0
    @ObservationIgnored private var hasClockOffset = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// True between a socket `subscribe` ack and the next disconnect: polling pauses.
    @ObservationIgnored private var socketReady = false
    @ObservationIgnored private var isPolling = false
    /// A server without the live-market routes answers 404; the feed then falls back
    /// to the older quote endpoint so the chart still moves.
    @ObservationIgnored private var usesQuoteFallback = false
    @ObservationIgnored private(set) var isRunning = false

    /// Beyond this with nothing arriving, the header says "Delayed" whatever the
    /// server's last status was.
    static let staleAfter: TimeInterval = 8
    static let pollInterval: Duration = .seconds(1)

    init(mint: String) { self.mint = mint }

    // MARK: - Reading

    /// The playhead for a frame drawn at `date`: server time minus the display delay.
    func playheadMs(at date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000 + clockOffsetMs).rounded()) - Int64(displayDelayMs)
    }

    /// The price the chart is showing at `date` — the trade at the playhead — so the
    /// header and the line always agree.
    func displayPrice(at date: Date) -> Decimal? {
        guard let index = MarketPlayback.playheadIndex(tape, at: playheadMs(at: date)) else { return nil }
        return tape[index].priceDecimal
    }

    /// The newest price held (ahead of the playhead), for accessibility.
    var latestPrice: Decimal? { tape.last?.priceDecimal }

    /// The server's state, downgraded to stale when nothing has arrived for a while.
    func effectiveState(at date: Date) -> MarketStatus.State? {
        guard let status else { return nil }
        if let lastUpdate, date.timeIntervalSince(lastUpdate) > Self.staleAfter { return .stale }
        return status.state
    }

    // MARK: - Running

    /// Subscribes (socket) and starts the poll loop, which only polls while the
    /// socket isn't delivering. Safe to call repeatedly.
    func start() {
        guard loop == nil else { return }
        isRunning = true
        MarketSocket.shared.subscribe(mint: mint) { [weak self] event in
            self?.handle(event)
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollIfNeeded()
                try? await Task.sleep(for: MarketFeed.pollInterval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        socketReady = false
        MarketSocket.shared.unsubscribe(mint: mint)
    }

    /// A one-off fetch so a token page opens with its chart already drawn (see
    /// `MarketFeedStore.prefetch`). Skipped when running or recently updated.
    func prefetch() async {
        if isRunning { return }
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 15 { return }
        await poll()
    }

    private func pollIfNeeded() async {
        guard !socketReady else { return }
        await poll()
    }

    /// One REST round: incremental when a seq is held, otherwise a full snapshot.
    /// A full page means the server capped the answer, so it asks again (a few times
    /// at most) until caught up.
    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        if usesQuoteFallback {
            await pollQuote()
            return
        }
        for _ in 0..<4 {
            let sinceSeq = lastSeq
            do {
                let snapshot = try await MarketAPI.live(mint: mint, sinceSeq: sinceSeq)
                apply(snapshot, isFull: sinceSeq == nil || snapshot.reset, receivedAt: Date())
                guard sinceSeq != nil, !snapshot.reset, snapshot.trades.count >= MarketAPI.pageLimit else { return }
            } catch APIError.server(let status, _) where status == 404 {
                usesQuoteFallback = true
                await pollQuote()
                return
            } catch {
                return
            }
        }
    }

    /// The pre-contract quote endpoint: one price per poll, drawn as observations.
    private func pollQuote() async {
        guard let quote = try? await TokenAPI.priceability(mint: mint), let price = quote.priceUsd, price > 0 else { return }
        let now = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        MarketPlayback.merge([TapePoint(id: "quote:\(now)", t: now, price: price, kind: .observation)], into: &tape, ids: &ids)
        if status == nil {
            status = MarketStatus(state: .degraded, source: .jupiter, lagMs: nil, poolAddress: nil, dex: nil)
        }
        lastUpdate = Date()
        trim()
    }

    // MARK: - Applying updates

    private func handle(_ event: MarketSocketEvent) {
        switch event {
        case .snapshot(let snapshot):
            apply(snapshot, isFull: true, receivedAt: Date())
            socketReady = true
        case .trades(let message):
            guard message.mint == mint else { return }
            let points = message.trades.map(TapePoint.init)
            MarketPlayback.merge(points, into: &tape, ids: &ids)
            lastUpdate = Date()
            if MarketPlayback.hasGap(lastSeq: lastSeq, batchSeq: message.seq, batchCount: message.trades.count) {
                // Missed a batch: keep `lastSeq` where it was and let a REST
                // `?sinceSeq=` fetch fill in (it moves `lastSeq` on success).
                Task { [weak self] in await self?.poll() }
            } else {
                lastSeq = max(lastSeq ?? message.seq, message.seq)
            }
            trim()
        case .status(let newStatus):
            if status != newStatus { status = newStatus }
            lastUpdate = Date()
        case .disconnected:
            socketReady = false
        }
    }

    /// Folds in a snapshot or incremental response. Also used for the socket's
    /// subscribe ack, which is the same shape.
    func apply(_ snapshot: LiveMarketSnapshot, isFull: Bool, receivedAt: Date) {
        updateClock(serverTime: snapshot.serverTime, receivedAt: receivedAt)
        displayDelayMs = MarketPlayback.clampDelay(snapshot.displayDelayMs)
        if status != snapshot.status { status = snapshot.status }

        var points = snapshot.trades.map(TapePoint.init)
        // A first response while the chain watcher attaches can carry a fallback
        // price but no trades yet; draw it as an observation so the chart isn't blank.
        if let price = snapshot.price, !points.contains(where: { $0.t >= price.t }), (tape.last?.t ?? .min) < price.t {
            points.append(TapePoint(id: "price:\(price.t)", t: price.t, price: price.value, kind: .observation))
        }

        var newTape = tape
        var newIds = ids
        if snapshot.reset {
            MarketPlayback.dropOverlap(of: points, from: &newTape, ids: &newIds)
        }
        MarketPlayback.merge(points, into: &newTape, ids: &newIds)
        ids = newIds
        if newTape != tape { tape = newTape }

        if isFull {
            oneSecondCandles = snapshot.candles1s.map(LiveCandle.init)
        }
        lastSeq = snapshot.reset || isFull ? snapshot.seq : max(lastSeq ?? snapshot.seq, snapshot.seq)
        lastUpdate = receivedAt
        trim()
    }

    /// Server time runs `offset` ahead of the device. Blended so a slow response
    /// can't jerk the time axis; the first reading is taken as is.
    private func updateClock(serverTime: Int64, receivedAt: Date) {
        let offset = Double(serverTime) - receivedAt.timeIntervalSince1970 * 1000
        if hasClockOffset {
            clockOffsetMs += (offset - clockOffsetMs) * 0.2
        } else {
            clockOffsetMs = offset
            hasClockOffset = true
        }
    }

    private func trim() {
        guard let newest = tape.last?.t else { return }
        let cutoff = newest - MarketPlayback.retentionMs
        guard let oldest = tape.first?.t, oldest < cutoff else { return }
        MarketPlayback.trim(&tape, ids: &ids, before: cutoff)
    }
}

/// Keeps recently seen tokens' feeds (LRU, ~20) so reopening a token — or opening
/// one whose Discover row prefetched it — shows a drawn chart immediately instead of
/// an empty one waiting on its first poll.
@MainActor
final class MarketFeedStore {
    static let shared = MarketFeedStore()

    static let capacity = 20
    static let maxInFlight = 6
    /// Rows flicking past during a fast scroll shouldn't each cost a request.
    static let prefetchDebounce: Duration = .milliseconds(300)

    private var feeds: [String: MarketFeed] = [:]
    /// Least recently used first.
    private var order: [String] = []
    private var scheduled: [String: Task<Void, Never>] = [:]
    private var queue: [String] = []
    private var inFlight = 0

    private init() {}

    func feed(for mint: String) -> MarketFeed {
        order.removeAll { $0 == mint }
        order.append(mint)
        if let feed = feeds[mint] { return feed }
        let feed = MarketFeed(mint: mint)
        feeds[mint] = feed
        evictIfNeeded()
        return feed
    }

    /// Call when a row appears. Debounced; at most `maxInFlight` fetches at once.
    func prefetch(_ mint: String) {
        guard scheduled[mint] == nil, !queue.contains(mint) else { return }
        scheduled[mint] = Task { [weak self] in
            try? await Task.sleep(for: MarketFeedStore.prefetchDebounce)
            guard !Task.isCancelled, let self else { return }
            self.scheduled[mint] = nil
            self.queue.append(mint)
            self.drain()
        }
    }

    /// Call when a row disappears: drops a prefetch that hasn't started yet.
    func cancelPrefetch(_ mint: String) {
        scheduled.removeValue(forKey: mint)?.cancel()
        queue.removeAll { $0 == mint }
    }

    private func drain() {
        while inFlight < Self.maxInFlight, !queue.isEmpty {
            let mint = queue.removeFirst()
            let feed = feed(for: mint)
            inFlight += 1
            Task { [weak self] in
                await feed.prefetch()
                guard let self else { return }
                self.inFlight -= 1
                self.drain()
            }
        }
    }

    private func evictIfNeeded() {
        var index = 0
        while feeds.count > Self.capacity, index < order.count {
            let mint = order[index]
            // Never evict a feed a screen is showing.
            if let feed = feeds[mint], !feed.isRunning {
                feeds[mint] = nil
                order.remove(at: index)
            } else {
                index += 1
            }
        }
    }
}
