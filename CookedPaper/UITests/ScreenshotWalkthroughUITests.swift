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
        app.launch()

        var unreachedSteps: [String] = []

        // With the bypass active, RootView goes straight to AppShellView on first
        // render -- no onboarding, no paywall -- but the app still has to
        // bootstrap a guest paper portfolio over the real network
        // (PortfolioStore.bootstrapIfNeeded), which is slower and genuinely
        // uncertain in a CI sandbox, hence the generous timeout and a loud,
        // specific failure rather than silently falling through with no
        // screenshot if it never shows up.
        let discoverTab = app.tabBars.buttons["Discover"]
        if discoverTab.waitForExistence(timeout: 20) {
            attach(app, name: "04-discover")
        } else {
            XCTFail("Main tab bar never appeared within 20s of a bypassed launch.")
            unreachedSteps.append("main tab bar never appeared")
        }

        // From here on, a missing element is treated as a flaky wait rather than a
        // reason to abort: each step screenshots whatever is on screen and moves on
        // to the next one, so one slow network call doesn't cost every screenshot
        // after it. Failures are collected and reported together at the end
        // instead, so the test's pass/fail status still reflects what happened.
        visitFirstDiscoverRow(app, unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Portfolio", screenshotName: "06-portfolio", unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Leaderboard", screenshotName: "07-leaderboard", unreachedSteps: &unreachedSteps)
        visitTab(app, label: "Settings", screenshotName: "08-settings", unreachedSteps: &unreachedSteps)

        if !unreachedSteps.isEmpty {
            XCTFail("Main-app walkthrough didn't fully complete: \(unreachedSteps.joined(separator: "; "))")
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
            attach(app, name: "05-token-detail")
            return
        }
        firstRow.tap()

        // The nav bar lands before the chart/network calls it triggers finish, so wait
        // a beat past its appearance rather than screenshotting a bare spinner.
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 8)
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "05-token-detail")

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
