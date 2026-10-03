import Foundation
import Observation

/// `GET /paper/leverage/config`: which multiples and directions the server offers
/// and the smallest margin it accepts. Fetched once and kept for the session (it's
/// server configuration, not market data); a failed fetch is retried the next time
/// a sheet asks, and until then everything falls back to the long-standing
/// defaults — the server still validates every quote and order.
@Observable
@MainActor
final class LeverageConfigStore {
    static let shared = LeverageConfigStore()

    static let fallbackOptions = [2, 5, 10]

    private(set) var config: PaperLeverageConfigResponse?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    private init() {}

    /// Sorted, de-duplicated multiples above 1x; the defaults when the server's
    /// list is missing or empty.
    var leverageOptions: [Int] {
        let options = Array(Set((config?.leverageOptions ?? []).filter { $0 > 1 })).sorted()
        return options.isEmpty ? Self.fallbackOptions : options
    }

    /// Long and short unless the server says otherwise.
    var directions: [LeverageDirection] {
        let offered = LeverageDirection.allCases.filter { config?.directions.contains($0) ?? true }
        return offered.isEmpty ? LeverageDirection.allCases : offered
    }

    /// Nil (no client-side floor) until the config has loaded.
    var minMarginUsd: Decimal? {
        guard let minimum = config?.minMarginUsd, minimum > 0 else { return nil }
        return minimum
    }

    /// The multiple a sheet starts on: 5x when offered, else the smallest.
    var defaultLeverage: Int {
        leverageOptions.contains(5) ? 5 : leverageOptions[0]
    }

    func loadIfNeeded() async {
        guard config == nil else { return }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let fetched = try? await PaperAPI.leverageConfig() else { return }
            self?.config = fetched
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}
