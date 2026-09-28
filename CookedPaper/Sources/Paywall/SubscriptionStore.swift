import Foundation
import Observation
import StoreKit

enum ProductID {
    static let monthly = "app.cooked.paper.monthly"
    static let annual = "app.cooked.paper.annual"
    static let weekly = "app.cooked.paper.weekly"
    static let all = [weekly, monthly, annual]
}

/// The entire paywall: two auto-renewing subscriptions in one group, StoreKit 2 only
/// (no server receipt validation for v1 — apps/api has no billing tables at all by
/// design, per docs/decisions-legal.md, and paper trading itself is free/unlimited
/// server-side; the subscription exists purely to gate this client). `Transaction
/// .currentEntitlements` is checked at launch and on every `Transaction.updates`
/// event, which is what StoreKit calls a "hard" paywall: there is no other door in.
@Observable
@MainActor
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var isLoadingProducts = true
    private(set) var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlement()
        }
    }

    // No deinit: this is a `static let shared` singleton that lives for the entire
    // process, so cancelling `updatesTask` on deallocation is code for a state that
    // never occurs — and under Swift 6 strict concurrency, `deinit` runs nonisolated
    // by default, so touching this @MainActor-isolated property from it doesn't even
    // compile without one.

    var monthlyProduct: Product? { products.first { $0.id == ProductID.monthly } }
    var annualProduct: Product? { products.first { $0.id == ProductID.annual } }
    var weeklyProduct: Product? { products.first { $0.id == ProductID.weekly } }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Your purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isSubscribed {
                purchaseError = "No active subscription found for this Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            purchaseError = "Couldn't verify that purchase with the App Store."
            return
        }
        await transaction.finish()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        #if DEBUG
        // `xcodebuild test` run from the command line — which is how this app is
        // built at all, there being no Mac in its authoring environment — has a
        // documented Xcode limitation: it does not push a StoreKit Configuration
        // to the simulator the way launching from the Xcode IDE does, for either
        // a scheme's "StoreKit Configuration" setting or `SKTestSession`. So
        // `Product.products(for:)` and `Transaction.currentEntitlements` are both
        // reliably empty under CI regardless of local StoreKit setup, and no
        // amount of project configuration fixes that from this side. This is the
        // one, narrow, DEBUG-only escape hatch: only the UI test process ever sets
        // this specific environment variable, so it cannot reach a Release build.
        if ProcessInfo.processInfo.environment["UITEST_BYPASS_PAYWALL"] == "1" {
            isSubscribed = true
            return
        }
        #endif

        var subscribed = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if ProductID.all.contains(transaction.productID), transaction.revocationDate == nil {
                subscribed = true
            }
        }
        isSubscribed = subscribed
    }
}
