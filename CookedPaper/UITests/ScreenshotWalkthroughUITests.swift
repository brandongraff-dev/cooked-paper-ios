import XCTest

/// UI tests run on XCTest, not Swift Testing — Apple has not shipped Swift Testing
/// support for UI automation, so this is the one place in the app that correctly uses
/// `XCTestCase` instead of `Testing`/`@Test`.
///
/// `nonisolated` on the class itself, not just its methods: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` globally, which would otherwise make
/// this class (and its inherited initializers) implicitly @MainActor — but
/// `XCTestCase`'s required initializers are `nonisolated`, and a subclass cannot
/// override a nonisolated declaration with an isolated one. Every method that
/// actually touches the UI is still explicitly `@MainActor` below.
///
/// Split into two test methods rather than one long walkthrough, because of a
/// confirmed Xcode/xcodebuild limitation: `xcodebuild test` run from the command
/// line (the only way this project is ever built, there being no Mac in its
/// authoring environment) does not push a StoreKit Configuration to the simulator
/// the way launching from the Xcode IDE does — neither the scheme's "StoreKit
/// Configuration" setting nor `StoreKitTest`'s `SKTestSession` actually reach the
/// launched process under the CLI, so `Product.products(for:)` is reliably empty
/// in CI no matter what this project configures. That's a real, externally-verified
/// tooling gap, not a bug in this app — see the comment on
/// `SubscriptionStore.refreshEntitlement()` for the corresponding app-side escape
/// hatch. Given that, one test walks onboarding through the paywall and stops
/// there (its screenshot of an empty product catalog is the honest CI-environment
/// result, not a failure to hide), and a second test uses that escape hatch to
/// start already "subscribed" and screenshot everything past the paywall instead.
nonisolated final class ScreenshotWalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testOnboardingAndPaywall() throws {
        let app = XCUIApplication()

        // `RootView` gates onboarding on `@AppStorage("hasSeenOnboarding")`, which
        // reads straight from UserDefaults. There is no supported way to set an
        // @AppStorage-backed value from the test side before the app reads it —
        // `launchArguments`/`launchEnvironment` are both invisible to the property
        // wrapper, which only observes UserDefaults itself. A fresh simulator
        // install has no UserDefaults for this bundle at all, so the flag defaults
        // to `false` and onboarding shows on its own — relying on that clean-
        // install state is the reliable path here, not fighting UserDefaults from
        // the test side.
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreachedSteps: [String] = []

        let nextButton = app.buttons["onboarding.next"]
        if nextButton.waitForExistence(timeout: 15) {
            attach(app, name: "01-onboarding")
            nextButton.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "02-onboarding-chart")
            nextButton.tap()
            Thread.sleep(forTimeInterval: 1)
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

        // No StoreKit Configuration reaches the process under `xcodebuild test`
        // (see the class doc comment), so `store.products` is reliably empty here
        // and this screenshot will show the paywall's hero/features but no plan
        // cards and a disabled Subscribe button — that is the accurate, expected
        // CI result, not a bug to chase. This test stops here on purpose.
        let subscribeButton = app.buttons["paywall.subscribeButton"]
        if subscribeButton.waitForExistence(timeout: 15) {
            attach(app, name: "03-paywall")
        } else {
            unreachedSteps.append("paywall.subscribeButton never appeared")
        }

        if !unreachedSteps.isEmpty {
            XCTFail("Onboarding/paywall walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    @MainActor
    func testMainAppScreenshots() throws {
        let app = XCUIApplication()
        // The DEBUG-only escape hatch in SubscriptionStore.refreshEntitlement() --
        // only this test process ever sets this, so it can't reach a Release build.
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        // Serve every API call from the in-app demo fixtures (see MockAPI.swift):
        // the production backend isn't reachable from CI, and without this every
        // data-backed screen screenshots as an empty/error state.
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        // Freezes ambient loops (see AmbientMotion) so the app can go idle between
        // steps and every screenshot is deterministic.
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreachedSteps: [String] = []

        let discoverTab = app.buttons["tab.discover"]
        if discoverTab.waitForExistence(timeout: 20) {
            _ = app.buttons["discover.row.0"].waitForExistence(timeout: 10)
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "04-discover")
        } else {
            XCTFail("Main tab bar never appeared within 20s of a bypassed launch.")
            unreachedSteps.append("main tab bar never appeared")
        }

        // From here on, a missing element is treated as a flaky wait rather than a
        // reason to abort: each step screenshots whatever is on screen and moves on
        // to the next one, so one slow call doesn't cost every screenshot after it.
        // Failures are collected and reported together at the end instead, so the
        // test's pass/fail status still reflects what happened.
        let moversChip = app.buttons["Movers"]
        if moversChip.waitForExistence(timeout: 5) {
            moversChip.tap()
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "05-discover-movers")
            app.buttons["Active"].firstMatch.tap()
        } else {
            unreachedSteps.append("Movers feed chip never appeared")
        }

        visitSearch(app, unreachedSteps: &unreachedSteps)
        visitFirstDiscoverRow(app, unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Portfolio", screenshotName: "09-portfolio", unreachedSteps: &unreachedSteps)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, name: "10-portfolio-scrolled")
        visitTab(app, label: "Leaderboard", screenshotName: "11-leaderboard", unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Settings", screenshotName: "12-settings", unreachedSteps: &unreachedSteps)

        // Last on purpose: this sheet initializes the Privy SDK, which still has a
        // placeholder app id in this repo. If that ever takes the app down, only this
        // one screenshot is lost.
        let saveProgress = app.buttons["settings.saveProgress"].firstMatch
        if saveProgress.waitForExistence(timeout: 5) {
            saveProgress.tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "13-save-progress-sheet")
        } else {
            unreachedSteps.append("Save Progress button never appeared in Settings")
        }

        if !unreachedSteps.isEmpty {
            XCTFail("Main-app walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    /// Same demo data, but starting as a signed-in account — the only way to reach
    /// the bearer-only screens (Price Alerts and its create sheet).
    @MainActor
    func testSignedInScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_BYPASS_PAYWALL"] = "1"
        app.launchEnvironment["UITEST_MOCK_API"] = "1"
        app.launchEnvironment["UITEST_MOCK_SIGNED_IN"] = "1"
        app.launchEnvironment["UITEST_STILL_FRAMES"] = "1"
        app.launch()

        var unreachedSteps: [String] = []

        visitTab(app, label: "Settings", screenshotName: "14-settings-signed-in", unreachedSteps: &unreachedSteps)

        let alertsLink = app.buttons["settings.priceAlerts"].firstMatch
        if alertsLink.waitForExistence(timeout: 5) {
            alertsLink.tap()
            _ = app.cells.firstMatch.waitForExistence(timeout: 5)
            Thread.sleep(forTimeInterval: 0.8)
            attach(app, name: "15-price-alerts")

            let addButton = app.navigationBars.buttons["Add"]
            if addButton.waitForExistence(timeout: 3) {
                addButton.tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "16-create-alert")
            } else {
                unreachedSteps.append("no Add button on Price Alerts")
            }
        } else {
            unreachedSteps.append("Price Alerts link never appeared in Settings")
        }

        if !unreachedSteps.isEmpty {
            XCTFail("Signed-in walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
        }
    }

    @MainActor
    private func visitSearch(_ app: XCUIApplication, unreachedSteps: inout [String]) {
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 3) else {
            unreachedSteps.append("no search field on Discover")
            return
        }
        searchField.tap()
        searchField.typeText("o")
        Thread.sleep(forTimeInterval: 1.2)
        attach(app, name: "06-discover-search")

        // Back to the feed: clear the query, dismiss the keyboard, leave search mode.
        // iOS versions differ on which of these controls exist, so try each.
        // Delete the query, then press the keyboard's Search/return key (typing a
        // newline does that), which submits and dismisses the keyboard.
        searchField.typeText(XCUIKeyboardKey.delete.rawValue)
        searchField.typeText("\n")
        for label in ["Cancel", "Close"] {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.8)
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
        // Discover's feed is a glass panel in a ScrollView, not a List, so its rows
        // are found by their `discover.row.N` identifiers rather than as cells.
        let firstRow = app.buttons["discover.row.0"]
        guard firstRow.waitForExistence(timeout: 10) else {
            unreachedSteps.append("no row in the Discover list to open")
            attach(app, name: "07-token-detail")
            return
        }
        if !firstRow.isHittable { app.swipeUp() }
        firstRow.tap()

        // The nav bar lands before the chart/network calls it triggers finish, so wait
        // a beat past its appearance rather than screenshotting a bare spinner.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "07-token-detail")

        let buyButton = app.buttons["tokenDetail.buy"].firstMatch
        if buyButton.waitForExistence(timeout: 5) {
            buyButton.tap()
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: "08-trade-sheet")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 3) {
                cancel.tap()
            } else {
                app.swipeDown()
            }
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            unreachedSteps.append("no Buy button on the token detail screen")
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
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
        // The app draws its own floating tab bar; its buttons carry `tab.<name>` ids.
        let tabButton = app.buttons["tab.\(label.lowercased())"]
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
