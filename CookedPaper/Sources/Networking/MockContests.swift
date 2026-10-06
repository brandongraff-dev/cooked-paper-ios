#if DEBUG
import Foundation

/// Demo data for contests (challenges, rooms, squads) for UI tests and screenshots,
/// in the shape the API sends. Off unless `MockAPI` is enabled (DEBUG only).
nonisolated enum MockContests {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var challengeActive = true

    static func route(method: String, parts: [String], body: Data?) -> (Int, Any)? {
        guard parts.first == "paper", parts.count >= 2 else { return nil }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        switch (method, Array(parts.dropFirst())) {
        case ("GET", ["challenges"]):
            return (200, challengeList())
        case ("POST", ["challenges"]):
            lock.lock(); challengeActive = true; lock.unlock()
            return (201, ["challenge": challenge(tier: json["tier"] as? String ?? "50k", status: "active", returnPct: "0.00")])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "challenges" && rest[2] == "abandon":
            lock.lock(); challengeActive = false; lock.unlock()
            return (200, ["challenge": challenge(tier: "50k", status: "abandoned", returnPct: "2.48")])
        default:
            return nil
        }
    }

    private static func challenge(tier: String, status: String, returnPct: String, daysAgo: Double = 6) -> [String: Any] {
        let balance: Double = ["10k": 10_000, "50k": 50_000, "100k": 100_000][tier] ?? 50_000
        let equity = balance * (1 + (Double(returnPct) ?? 0) / 100)
        return [
            "id": "challenge-\(tier)-\(status)", "tier": tier, "status": status,
            "rules": ["profitTargetPct": "8", "maxLossPct": "5", "days": 30] as [String: Any],
            "startingBalanceUsd": String(format: "%.2f", balance),
            "targetEquityUsd": String(format: "%.2f", balance * 1.08),
            "floorEquityUsd": String(format: "%.2f", balance * 0.95),
            "equityUsd": String(format: "%.2f", equity), "returnPct": returnPct,
            "portfolioId": "challenge-portfolio",
            "startedAt": MockAPI.iso(daysFromNow: -daysAgo),
            "endsAt": MockAPI.iso(daysFromNow: 30 - daysAgo),
            "finishedAt": status == "active" ? NSNull() : MockAPI.iso(daysFromNow: -1),
        ]
    }

    private static func challengeList() -> [String: Any] {
        lock.lock(); let active = challengeActive; lock.unlock()
        return [
            "active": active ? challenge(tier: "50k", status: "active", returnPct: "2.48") : NSNull(),
            "history": [
                challenge(tier: "10k", status: "passed", returnPct: "8.31", daysAgo: 40),
                challenge(tier: "50k", status: "failed", returnPct: "-5.02", daysAgo: 75),
            ],
            "tiers": ["10k", "50k", "100k"].map { tier -> [String: Any] in
                let balance: Double = ["10k": 10_000, "50k": 50_000, "100k": 100_000][tier]!
                return [
                    "tier": tier, "startingBalanceUsd": String(format: "%.2f", balance),
                    "rules": ["profitTargetPct": "8", "maxLossPct": "5", "days": 30] as [String: Any],
                ]
            },
            "passed": 1, "attempts": 3,
            "disclaimer": "Paper challenge: simulated prices, no real money, no funding and no prizes.",
        ]
    }
}
#endif
