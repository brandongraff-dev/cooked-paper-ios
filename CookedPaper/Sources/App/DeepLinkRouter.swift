import Foundation
import Observation

/// `cookedpaper://token/<mint>` is the one deep link this app understands today,
/// handed off from `CookedPaperApp`'s `.onOpenURL` and consumed by `AppShellView`'s
/// sheet. Foundation parses this two-segment form with "token" landing in `.host`
/// and "/<mint>" landing in `.path`, so extraction reads those rather than
/// `.pathComponents[0]`.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    private(set) var pendingTokenMint: String?

    private init() {}

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "cookedpaper",
              url.host?.lowercased() == "token" else { return }

        guard let mint = url.pathComponents.first(where: { $0 != "/" }), !mint.isEmpty else { return }

        pendingTokenMint = mint
    }

    func clear() {
        pendingTokenMint = nil
    }
}
