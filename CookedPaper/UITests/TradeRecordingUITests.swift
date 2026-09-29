import XCTest

/// A paced walkthrough of trading, screen-recorded by CI: buy WIF with $250,
/// open a 5x long with $500 of margin, then find it in Portfolio and close it.
/// Pauses are deliberate so a viewer can follow each step. Run on its own with
/// `-only-testing`; the screenshot walkthrough skips it.
nonisolated final class TradeRecordingUITests: XCTestCase {
    @MainActor
    func testTradeAndLeverageRecording() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        app.launch()

        func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
        func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 8) {
            XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(what) never appeared")
            if element.exists { element.tap() }
        }
        func type(_ digits: String) {
            for key in digits.map(String.init) {
                app.buttons[key].firstMatch.tap()
                pause(0.25)
            }
        }

        // Discover → WIF.
        let wif = app.buttons["discover.row.0"]
        XCTAssertTrue(wif.waitForExistence(timeout: 20), "Discover never loaded")
        pause(1.5)
        wif.tap()
        pause(4) // let the live chart run

        // Spot buy: $250 of WIF.
        tap(app.buttons["tokenDetail.buy"], "Buy button")
        pause(1.2)
        type("250")
        pause(1.5)
        tap(app.buttons["Review"], "Review button")
        pause(3) // fill confirmation
        tap(app.buttons["Done"], "Done after buy")
        pause(1.5)

        // Leverage: 5x long, $500 margin.
        tap(app.buttons["tokenDetail.leverage"], "Leverage button")
        pause(1.2)
        tap(app.buttons["leverage.multiple.5"], "5x")
        pause(0.6)
        type("500")
        pause(2.5) // quote: size, entry, liquidation
        tap(app.buttons["leverage.open"], "Open position")
        pause(3) // opened confirmation
        tap(app.buttons["leverage.done"], "Done after open")
        pause(1.5)

        // Portfolio → the new leveraged position → close it.
        tap(app.buttons["tab.portfolio"], "Portfolio tab")
        pause(2)
        let row = app.buttons["portfolio.leveraged.0"]
        if row.waitForExistence(timeout: 5), !row.isHittable {
            app.swipeUp()
            pause(1)
        }
        if !row.isHittable {
            app.swipeUp()
            pause(1)
        }
        tap(row, "Leveraged position row")
        pause(3)
        tap(app.buttons["leverage.close"], "Close position")
        pause(3.5) // result
        tap(app.buttons["Done"], "Done after close")
        pause(2.5)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "trade-recording-end"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
