import XCTest

/// Opens a token's LIVE chart and holds on it while CI screen-records the
/// simulator (`xcrun simctl io … recordVideo`, see the workflow). Run on its own
/// with `-only-testing`; the screenshot walkthrough skips it.
nonisolated final class LiveChartRecordingUITests: XCTestCase {
    @MainActor
    func testLiveChartRecording() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        app.launch()

        let row = app.buttons["discover.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "Discover never loaded")
        Thread.sleep(forTimeInterval: 1)
        row.tap()

        // Let the chart fill in and keep moving for the recording.
        Thread.sleep(forTimeInterval: 18)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "live-chart"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
