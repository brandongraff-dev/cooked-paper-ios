import Foundation
import Testing

@testable import CookedPaper

/// `DeepLink.parse`: the custom scheme and the web invite links (universal links)
/// land on the same destinations.
struct DeepLinkTests {
    private func parse(_ string: String) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink.parse(url)
    }

    @Test(arguments: [
        "https://cooked.trade/d/k3J9xQ2a",
        "https://www.cooked.trade/d/k3J9xQ2a",
        "https://WWW.Cooked.Trade/d/k3J9xQ2a",
        "https://cooked.trade/d/k3J9xQ2a/",
        "https://cooked.trade/d/k3J9xQ2a?utm_source=share",
        "cookedpaper://duel/k3J9xQ2a",
    ])
    func duelInviteLinks(link: String) {
        #expect(parse(link) == .duelInvite(code: "k3J9xQ2a"))
    }

    @Test(arguments: [
        "https://cooked.trade/l/Q7m2Lx9a",
        "https://www.cooked.trade/l/Q7m2Lx9a",
        "https://www.cooked.trade/l/Q7m2Lx9a#join",
        "cookedpaper://league/Q7m2Lx9a",
    ])
    func leagueInviteLinks(link: String) {
        #expect(parse(link) == .leagueInvite(code: "Q7m2Lx9a"))
    }

    @Test func webAndSchemeInvitesMatch() {
        #expect(parse("https://cooked.trade/d/ABC") == parse("cookedpaper://duel/ABC"))
        #expect(parse("https://www.cooked.trade/l/XYZ") == parse("cookedpaper://league/XYZ"))
    }

    @Test(arguments: [
        "https://cooked.trade/",
        "https://cooked.trade/d",
        "https://cooked.trade/d/",
        "https://cooked.trade/l/abc/extra",
        "https://cooked.trade/s/abc",
        "https://cooked.trade/discover",
        "https://app.cooked.trade/d/abc",
        "https://evil.example/d/abc",
        "https://cooked.trade.evil.example/d/abc",
        "http://cooked.trade/d/abc",
        "cookedpaper://duel",
        "cookedpaper://unknown/abc",
        "otherscheme://duel/abc",
    ])
    func ignoresEverythingElse(link: String) {
        #expect(parse(link) == nil)
    }

    @Test func customSchemeKinds() {
        #expect(parse("cookedpaper://token/So11111111111111111111111111111111111111112")
            == .token(mint: "So11111111111111111111111111111111111111112"))
        #expect(parse("cookedpaper://duel-id/d_123") == .duel(id: "d_123"))
        #expect(parse("cookedpaper://league-id/l_456") == .league(id: "l_456"))
        #expect(parse("cookedpaper://achievements") == .achievements)
    }
}
