import XCTest

/// UI tests run on XCTest, not Swift Testing — Apple has not shipped Swift Testing
/// support for UI automation, so this is the one place in the app that correctly uses
/// `XCTestCase` instead of `Testing`/`@Test`.
final class ScreenshotWalkthroughUITests: XCTestCase {
    @MainActor
    func testWalkthroughAndScreenshots() throws {
        let app = XCUIApplication()

        // `RootView` gates onboarding on `@AppStorage("hasSeenOnboarding")`, which
        // reads straight from UserDefaults. There is no supported way to set an
        // @AppStorage-backed value from the test side before the app reads it —
        // `launchArguments = ["-hasSeenOnboarding", "false"]` and
        // `launchEnvironment["hasSeenOnboarding"]` are both invisible to the property
        // wrapper, which only observes UserDefaults itself. A fresh simulator install
        // has no UserDefaults for this bundle at all, so the flag defaults to `false`
        // and onboarding shows on its own — relying on that clean-install state is the
        // reliable path here, not fighting UserDefaults from the test side.
        app.launch()

        var unreachedSteps: [String] = []

        let nextButton = app.buttons["onboarding.next"]
        if nextButton.waitForExistence(timeout: 15) {
            attach(app, name: "01-onboarding")
            nextButton.tap()
            nextButton.tap()
            attach(app, name: "02-onboarding-final")

            let getStartedButton = app.buttons["onboarding.getStarted"]
            if getStartedButton.waitForExistence(timeout: 5) {
                getStartedButton.tap()
            } else {
                unreachedSteps.append("onboarding.getStarted never appeared")
            }
        } else {
            unreachedSteps.append("onboarding.next never appeared")
        }

        let subscribeButton = app.buttons["paywall.subscribeButton"]
        // StoreKit product loading is async even against the local .storekit file.
        if subscribeButton.waitForExistence(timeout: 15) {
            attach(app, name: "03-paywall")

            let annualPlan = app.buttons["paywall.planAnnual"]
            if annualPlan.waitForExistence(timeout: 3) {
                annualPlan.tap()
            }
            attach(app, name: "04-paywall-annual-selected")
            subscribeButton.tap()
        } else {
            unreachedSteps.append("paywall.subscribeButton never appeared")
            attach(app, name: "03-paywall")
        }

        // The local StoreKit purchase itself should resolve near-instantly, but the
        // tab bar only appears once the app has also bootstrapped a guest paper
        // portfolio over the network (PortfolioStore.bootstrapIfNeeded) — that part is
        // slower and genuinely uncertain in a CI sandbox, hence the generous timeout
        // and a loud, specific failure rather than silently falling through with no
        // screenshot if it never shows up.
        let discoverTab = app.tabBars.buttons["Discover"]
        if discoverTab.waitForExistence(timeout: 15) {
            attach(app, name: "05-discover")
        } else {
            XCTFail("Main tab bar never appeared: expected the \"Discover\" tab within 15s of tapping Subscribe.")
            unreachedSteps.append("main tab bar never appeared")
        }

        // From here on, a missing element is treated as a flaky wait rather than a
        // reason to abort: each step screenshots whatever is on screen and moves on to
        // the next one, so one slow network call doesn't cost every screenshot after
        // it. Failures are collected and reported together at the end instead, so the
        // test's pass/fail status still reflects what actually happened.
        visitFirstDiscoverRow(app, unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Portfolio", screenshotName: "07-portfolio", unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Leaderboard", screenshotName: "08-leaderboard", unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Settings", screenshotName: "09-settings", unreachedSteps: &unreachedSteps)

        if !unreachedSteps.isEmpty {
            XCTFail("Walkthrough did not fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }

    @MainActor
    private func visitFirstDiscoverRow(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        // `app.tables.cells` would miss this if DiscoverView's List ever renders as a
        // plain container instead of a table-backed accessibility tree; `app.cells`
        // matches a cell regardless of the underlying container type.
        let firstRow = app.cells.firstMatch
        guard firstRow.waitForExistence(timeout: 10) else {
            unreachedSteps.append("no row in the Discover list to open")
            attach(app, name: "06-token-detail")
            return
        }
        firstRow.tap()

        // The nav bar lands before the chart/network calls it triggers finish, so wait
        // a beat past its appearance rather than screenshotting a bare spinner.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "06-token-detail")

        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else {
            unreachedSteps.append("no back button found on the token detail screen")
        }
    }

    @MainActor
    private func visitTab(
        _ app: XCUIApplication,
        label: String,
        screenshotName: String,
        unreachedSteps: inout [String]
    ) {
        let tabButton = app.tabBars.buttons[label]
        guard tabButton.waitForExistence(timeout: 5) else {
            unreachedSteps.append("\(label) tab button never appeared")
            attach(app, name: screenshotName)
            return
        }
        tabButton.tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: screenshotName)
    }
}
