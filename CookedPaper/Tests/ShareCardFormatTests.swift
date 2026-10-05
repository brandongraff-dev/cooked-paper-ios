import Foundation
import Testing

@testable import CookedPaper

struct ShareCardFormatTests {
    private let enUS = Locale(identifier: "en_US")

    @Test(arguments: [
        ("42.1", "+42.10%"),
        ("-8.034", "\u{2212}8.03%"),
        ("0", "+0.00%"),
        ("184.24", "+184.2%"),
        ("1204.4", "+1,204%"),
        ("-99.999", "\u{2212}100.00%"),
    ])
    func pnlFormatsSignAndPrecision(input: String, expected: String) {
        #expect(ShareCardFormat.pnl(Decimal(string: input)!, locale: enUS) == expected)
    }

    @Test func pnlTinyLossReadsFlatNotNegativeZero() {
        #expect(ShareCardFormat.pnl(Decimal(string: "-0.001")!, locale: enUS) == "+0.00%")
    }

    @Test func pnlUnmeasuredIsADash() {
        #expect(ShareCardFormat.pnl(nil, locale: enUS) == "—")
    }

    @Test func returnPctFromEntryToExit() {
        let pct = ShareCardFormat.returnPct(entry: Decimal(string: "2")!, exit: Decimal(string: "3")!)
        #expect(pct == Decimal(50))
        let loss = ShareCardFormat.returnPct(entry: Decimal(string: "4")!, exit: Decimal(string: "3")!)
        #expect(loss == Decimal(-25))
    }

    @Test func returnPctNeedsAPositiveEntry() {
        #expect(ShareCardFormat.returnPct(entry: 0, exit: 1) == nil)
    }

    @Test func symbolAddsOneDollarSignAndFallsBackToTheMint() {
        #expect(ShareCardFormat.symbol("WIF", mint: "EKpQGS123") == "$WIF")
        #expect(ShareCardFormat.symbol("$WIF", mint: "EKpQGS123") == "$WIF")
        #expect(ShareCardFormat.symbol(nil, mint: "EKpQGS123") == "EKpQGS")
        #expect(ShareCardFormat.symbol("  ", mint: "EKpQGS123") == "EKpQGS")
    }

    @Test func duelLinkOnlyWithACode() {
        #expect(ShareCardFormat.duelLink(code: "K7QX2M") == "cooked.trade/d/K7QX2M")
        #expect(ShareCardFormat.duelLink(code: nil) == nil)
        #expect(ShareCardFormat.duelLink(code: "") == nil)
    }

    @Test func duelURLIsTheHttpsInviteLink() {
        #expect(ShareCardFormat.duelURL(code: "K7QX2M") == "https://cooked.trade/d/K7QX2M")
        #expect(ShareCardFormat.duelURL(code: " ") == nil)
    }

    @Test func verdictWords() {
        #expect(ShareCardFormat.verdict(.won) == "WIN")
        #expect(ShareCardFormat.verdict(.lost) == "LOSS")
        #expect(ShareCardFormat.verdict(.draw) == "DRAW")
    }
}
