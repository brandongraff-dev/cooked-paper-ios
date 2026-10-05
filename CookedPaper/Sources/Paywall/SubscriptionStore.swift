import Foundation
import Observation
import StoreKit

enum ProductID {
    static let monthly = "app.cooked.paper.monthly"
    static let annual = "app.cooked.paper.annual"
    static let weekly = "app.cooked.paper.weekly"
    /// Founding Member: a one-time (non-consumable) purchase that unlocks Pro with
    /// no renewals. Not Family Shareable, so it can't be passed around either.
    static let founding = "app.cooked.paper.founding"
    static let subscriptions = [weekly, monthly, annual]
    static let all = subscriptions + [founding]
}

/// The entire paywall: auto-renewing subscriptions in one group, StoreKit 2 first.
/// `Transaction.currentEntitlements` is checked at launch and on every
/// `Transaction.updates` event, which is what StoreKit calls a "hard" paywall.
///
/// The server is told too: every verified transaction's signed JWS goes to `POST
/// /billing/apple/transactions` (after a purchase or renewal, and for current
/// entitlements on launch/sign-in via `syncWithServer`), and `GET
/// /billing/apple/entitlement` is read back. The person is subscribed if StoreKit
/// says so OR the server says active. A server that's unreachable, returns 404
/// (not deployed yet) or says inactive never takes away what StoreKit grants — a
/// network error must not lock out someone who paid.
@Observable
@MainActor
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var isLoadingProducts = true
    private(set) var purchaseError: String?
    /// The server's last answer this session; nil until one arrives (and after
    /// sign-out), which means "StoreKit decides alone".
    private(set) var serverEntitlement: AppleEntitlement?
    private var storeKitEntitled = false

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
    var foundingProduct: Product? { products.first { $0.id == ProductID.founding } }

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
            // Ties the purchase to the account server-side (App Store Server
            // Notifications carry it), when the account id is a UUID.
            var options: Set<Product.PurchaseOption> = []
            if let userId = SessionStore.shared.userId, let accountToken = UUID(uuidString: userId) {
                options.insert(.appAccountToken(accountToken))
            }
            let result = try await product.purchase(options: options)
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
            await syncWithServer()
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
        let signedTransaction = verification.jwsRepresentation
        await transaction.finish()
        await refreshEntitlement()
        // The server reconciles subscriptions only; Founding Member is a one-time
        // purchase StoreKit alone vouches for.
        if ProductID.subscriptions.contains(transaction.productID) {
            await submitToServer([signedTransaction])
        }
    }

    // MARK: - Server validation

    /// On launch with a session and after every sign-in: sends each current
    /// entitlement to the server, then reads its verdict.
    func syncWithServer() async {
        await submitToServer(await currentEntitlementJWS())
    }

    /// After sign-out: the next account's server entitlement is its own.
    func clearServerEntitlement() {
        serverEntitlement = nil
        updateSubscribed()
    }

    private func submitToServer(_ signedTransactions: [String]) async {
        guard SessionStore.shared.isSignedIn else { return }
        var latest: AppleEntitlement?
        for signedTransaction in signedTransactions {
            if let entitlement = try? await BillingAPI.submitAppleTransaction(signedTransaction) {
                latest = entitlement
            }
        }
        if let entitlement = try? await BillingAPI.appleEntitlement() {
            latest = entitlement
        }
        // No answer (offline, 404, 5xx): keep what we had and let StoreKit decide.
        guard let latest else { return }
        serverEntitlement = latest
        updateSubscribed()
    }

    private func currentEntitlementJWS() async -> [String] {
        var signed: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  ProductID.subscriptions.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            signed.append(entitlement.jwsRepresentation)
        }
        return signed
    }

    private func updateSubscribed() {
        isSubscribed = storeKitEntitled || serverEntitlement?.active == true
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
            storeKitEntitled = true
            updateSubscribed()
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
        storeKitEntitled = subscribed
        updateSubscribed()
    }
}
