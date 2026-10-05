import Foundation

/// The two documents every account agrees to. Apple Guideline 3.1.2 also requires the
/// paywall to carry a functional link to each.
///
/// These point straight at the canonical pages on the website (`apps/web`,
/// `/legal/terms` and `/legal/privacy`) rather than at the `/terms` and `/privacy`
/// redirects, so there is no hop to fail and the address a reviewer sees is the one
/// the document lives at. Use the same two URLs in App Store Connect (Privacy Policy
/// URL, and the Terms of Use link in the app description if a custom EULA is used).
enum LegalLinks {
    static let terms = URL(string: "https://cooked.trade/legal/terms")!
    static let privacy = URL(string: "https://cooked.trade/legal/privacy")!
}
