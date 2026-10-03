import Foundation
import Observation

/// The account's alert rules (`GET /social/alerts`), cached for the session and
/// kept in step with every create, toggle and delete made from this app. Shared by
/// the token screen (its bell, its sheet, the chart's alert lines) and Settings'
/// alert list.
@Observable
@MainActor
final class PriceAlertStore {
    static let shared = PriceAlertStore()

    private(set) var alerts: [PriceAlert] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadError: String?

    private init() {}

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func load() async {
        guard SessionStore.shared.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            alerts = try await SocialAPI.alerts()
            hasLoaded = true
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// This token's price alerts, active ones first.
    func priceAlerts(for mint: String) -> [PriceAlert] {
        alerts
            .filter { $0.isPriceAlert && $0.rule.mint == mint }
            .sorted { $0.isActive && !$1.isActive }
    }

    /// Active price levels for `CandleChartView(alertLevels:)`.
    func chartLevels(for mint: String) -> [ChartAlertLevel] {
        priceAlerts(for: mint).compactMap { alert in
            guard alert.isActive, let price = alert.rule.priceUsd, let direction = alert.rule.priceDirection else { return nil }
            return ChartAlertLevel(id: alert.id, price: price, direction: direction == .above ? .above : .below)
        }
    }

    func hasActiveAlert(for mint: String) -> Bool {
        priceAlerts(for: mint).contains { $0.isActive }
    }

    @discardableResult
    func createPriceAlert(mint: String, symbol: String, direction: PriceAlertDirection, price: Decimal) async throws -> PriceAlert {
        let name = String("\(symbol) \(direction.title.lowercased()) \(PriceFormat.price(price))".prefix(64))
        let body = CreatePriceAlertBody(
            name: name,
            rule: PriceCrossedRuleBody(mint: mint, direction: direction, priceUsd: PriceAlertMath.plain(price, significantDigits: 12))
        )
        let created = try await SocialAPI.createAlert(body)
        alerts.removeAll { $0.id == created.id }
        alerts.insert(created, at: 0)
        return created
    }

    func setActive(_ alert: PriceAlert, isActive: Bool) async throws {
        let updated = try await SocialAPI.setAlertActive(id: alert.id, isActive: isActive)
        if let index = alerts.firstIndex(where: { $0.id == updated.id }) {
            alerts[index] = updated
        }
    }

    func delete(_ alert: PriceAlert) async throws {
        try await SocialAPI.deleteAlert(id: alert.id)
        alerts.removeAll { $0.id == alert.id }
    }

    /// After sign-out: the next account starts from its own list.
    func reset() {
        alerts = []
        hasLoaded = false
        loadError = nil
    }

    static func message(for error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
