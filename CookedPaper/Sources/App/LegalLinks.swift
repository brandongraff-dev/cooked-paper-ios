import Foundation

/// Apple Guideline 3.1.2 requires the paywall to carry a functional link to both
/// documents. `/terms` and `/privacy` are the app-store-listing-stable redirects
/// `apps/web` itself keeps for this exact purpose (see `apps/web/app/terms/page.tsx`).
///
/// IMPORTANT — as of this writing `apps/web/app/legal/terms/page.tsx` sets its own
/// page title to "Draft: not reviewed by counsel and not in force." Submitting this
/// app for review while that is true is a real compliance gap, not a placeholder to
/// silently ignore — confirm the document's `status` has flipped to in-force before
/// shipping a build with real billing enabled.
enum LegalLinks {
    static let terms = URL(string: "https://app.cooked.trade/terms")!
    static let privacy = URL(string: "https://app.cooked.trade/privacy")!
}
