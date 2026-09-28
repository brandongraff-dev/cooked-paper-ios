# Cooked Paper (iOS)

A native SwiftUI, paper-trading-only companion to Cooked, hard-paywalled at **$7.99/mo**
or **$29.99/yr**. Built against the same `apps/api` backend as `apps/web` and
`apps/mobile` — no new backend code, no billing tables (paper trading is free/
unlimited server-side by design; the subscription is enforced entirely on-device via
StoreKit 2).

This was scaffolded from a Windows machine with no Xcode, so nothing here has been
compiled. Read this whole file before opening the project — there are placeholder
values that must be filled in before it will run.

**Requires Xcode 26+ to build**, even though the app's own deployment target stays
iOS 17 — the UI adopts Liquid Glass (`glassEffect`, `.glassProminent`,
`GlassEffectContainer`, all iOS 26+ only) as a progressive enhancement, and every use
is gated behind `if #available(iOS 26.0, *)` with a pre-26 fallback. That gating still
needs the iOS 26 SDK to be *present* to compile at all — an older Xcode without that
SDK will fail on the `Glass`/`glassEffect` symbols regardless of the availability
check, since the check only decides which code *runs*, not which code *compiles
against a known symbol*. See `Sources/DesignSystem/Glass.swift` for the one shared
`.cookedGlass()`/`CookedGlassContainer` pair every glass surface in the app goes
through — extend that file rather than adding a new bare `.glassEffect()` call site
if this needs to grow.

## What's here

```
CookedPaper/
  project.yml              XcodeGen spec — the source of truth. The .xcodeproj is
                            generated from this and gitignored.
  Sources/
    App/                    Entry point, paywall/onboarding gate, deep-link routing,
                            the shared portfolio store
    DesignSystem/           Colors/type/motion ported from packages/config/design-tokens.ts,
                            plus skeleton-loading components
    Networking/             APIClient, Keychain session storage, the /paper Socket.IO
                            client (with the real resume/gap/heartbeat protocol)
    Models/                 Codable models, incl. the DecimalString wrappers every
                            money field on this API needs (see Models/DecimalCodable.swift)
    Auth/                   Privy embedded-wallet login (email OTP / Apple / Google),
                            plus a vendored Base58 codec
    Paywall/                StoreKit 2 subscription store + the paywall screen
    Features/               Onboarding, Discover (+ watchlist stars), TokenDetail
                            (chart + trade), Trade, Portfolio, Leaderboard, Alerts,
                            Settings
  Resources/                Info.plist, entitlements, Assets.xcassets
  Scripts/                  GenerateIcon.swift — renders the real app icon PNG
  StoreKit/Products.storekit  Local StoreKit Configuration for the two subscriptions
  Tests/                    Swift Testing unit tests (decimal codec, Base58, trade
                            math, model decoding)
```

## First-time setup

1. **Install XcodeGen** (`brew install xcodegen`), then from `CookedPaper` (this
   repo's own `apps/ios/CookedPaper` if you're reading this inside the monorepo it
   was extracted from):
   ```
   xcodegen generate
   open CookedPaper.xcodeproj
   ```
2. **Apple Developer / signing**
   - Set `DEVELOPMENT_TEAM` in `project.yml`'s `settings.base` to your Team ID, or set it in
     Xcode's Signing & Capabilities tab.
   - Bundle id is `app.cooked.paper`, matching the `app.cooked.mobile` convention the
     Expo app already uses. Register it in your Apple Developer account with the
     **Sign In with Apple** capability enabled (the entitlement is already in
     `Resources/CookedPaper.entitlements`).
3. **Privy** (`Sources/Auth/PrivyClient.swift`) — create an app at
   [dashboard.privy.io](https://dashboard.privy.io), enable Email, Apple, and Google
   login methods, then fill in:
   - `PrivyConfiguration.appId` / `.appClientId`
   - Register `cookedpaper://` as an allowed redirect URI in the dashboard (it's
     already declared as a URL scheme in `project.yml`).
   - No GoogleSignIn-iOS SDK is needed — Google goes through Privy's own OAuth
     redirect using that same URL scheme.
4. **App Store Connect — subscriptions**
   - Create a subscription group ("Cooked Paper Pro") with two auto-renewable
     subscriptions: `app.cooked.paper.monthly` ($7.99/mo) and
     `app.cooked.paper.annual` ($29.99/yr). These product IDs must match
     `Sources/Paywall/SubscriptionStore.swift`'s `ProductID` exactly.
   - `StoreKit/Products.storekit` mirrors this for local testing (Xcode scheme →
     Options → StoreKit Configuration) without needing App Store Connect at all
     during development. Xcode will offer to repair its internal IDs the first time
     you open it — let it.
5. **API base URL** — `Sources/Networking/APIClient.swift`'s `APIConfig.baseURL`
   points at the same production Railway API `apps/mobile` falls back to. Point it at
   a local worktree API for development the same way you would for any other client.

## Product decisions this was built against

- **Guest trading first, real accounts optional.** `POST /paper/portfolios/starter`
  works with no login at all (a 7-day, self-expiring guest token) — that's what
  fires immediately after a successful purchase, so "pay → trade" is one screen.
  Settings offers "Save Progress" (email OTP / Apple / Google via Privy), which
  silently claims the guest portfolio onto the new account.
- **No dark patterns**, on purpose, matching `apps/api/src/paper/onboarding.ts`'s own
  stated design: no streaks, no countdowns, no fake urgency, no score. The backend
  structurally can't produce that data; the client doesn't invent it either.
- **Money is `Decimal`, never `Double`**, decoded from the API's decimal-STRING
  fields via `@DecimalString`/`@OptionalDecimalString` property wrappers. Every
  numeric UI value should trace back to one of these — never hand-parse a price
  string with `Double(string:)`.
- **Null means "unmeasured," never zero** — `PnLText` and the position/round-trip
  rows render `nil` as "—", matching the API's own convention. Don't "fix" a `nil`
  by coalescing it to `0`.
- **Watchlist and price alerts are account-only.** `/watchlist/*` and `/social/alerts/*`
  are `auth: 'bearer'` and reject a guest token (unlike every `/paper/*` route) — both
  features check `SessionStore.shared.isGuest` client-side and prompt "Save Progress"
  instead of letting a guest request 401 against the backend.
- **Price alerts only build one rule kind.** The backend's `AlertRule` is a five-kind
  union (wallet-based rules need a real wallet address this paper-only app doesn't
  have); `Sources/Models/AlertModels.swift` only constructs and edits `price_crossed`,
  decoding every other kind to `.unsupported` so an alert made elsewhere (e.g. the web
  app) doesn't break the list. Channel is always `in_app` — there's no APNs
  entitlement or push-token registration wired up, so an alert firing has nothing to
  display yet (no notification-center screen exists); that's the next piece to build
  if push delivery matters.
- **The live socket implements the server's real resume protocol**, not a
  simplification — it tracks the last seen `seq` per portfolio, resumes with
  `sinceSeq` on reconnect, and treats a `counterReset`/`truncated` gap as a fresh
  baseline rather than trying to replay deltas. A heartbeat watchdog tears down and
  reconnects the socket if `heartbeatIntervalMs` elapses with no tick.
- **`cookedpaper://token/<mint>` opens a token's detail screen** from anywhere in the
  app via `DeepLinkRouter`, presented as a sheet over whichever tab is active.
- **Active price alerts are drawn on the chart itself** as horizontal lines — a
  pattern that converged independently across FOMO, Photon, and BullX in the UX
  research behind this pass, so it's treated as a genre expectation, not a nice-to-have.
- **The chart's crosshair requires a brief press before it engages** (`LongPressGesture`
  sequenced before the drag, in `CandleChartView.crosshairGesture`), not a bare drag.
  The chart lives inside a `ScrollView`; a bare `DragGesture` there would capture every
  page-scroll attempt that happens to start over the chart. A quick swipe scrolls the
  page; a deliberate press-and-hold-then-drag scrubs the chart.

## Known gaps / what to do before shipping

- **The app icon PNG doesn't exist on disk yet** — `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  points at `icon-1024.png`, but it has to be rendered on a Mac first; see
  "Generating the app icon" below. Nothing to design by hand, just one command to run.
- **Numerals use SF Mono, not IBM Plex Mono.** The web/Expo apps both set prices in
  IBM Plex Mono; this port uses the system monospaced design instead of bundling the
  font files (see `Sources/DesignSystem/Typography.swift`). Swap in the real TTFs
  under a new `Resources/Fonts` if exact brand parity matters more than the
  dependency.
- **`Sources/Auth/PrivyClient.swift` is written from Privy's current documented iOS
  API, not compiled against it.** In particular `EmbeddedSolanaWallet.provider
  .signMessage(message:)`'s exact return type (`String` vs. a small result struct)
  wasn't confirmed at the type-signature level — check Xcode's Quick Help on first
  build and adjust `PrivyClient.sign(_:with:)` if it doesn't match.
- **The Terms of Use this app links to are marked "Draft: not reviewed by counsel
  and not in force"** as of this writing
  (`apps/web/app/legal/terms/page.tsx`). Apple Guideline 3.1.2 requires a functional
  link to real terms before a paid subscription can ship — confirm that document's
  status has flipped before submitting for review.
- **No server-side receipt validation.** `Transaction.currentEntitlements` (checked
  at launch and on every `Transaction.updates` event) is standard StoreKit 2 practice
  and syncs automatically across a user's devices via their Apple ID, but there's no
  App Store Server Notifications webhook on the backend to reconcile entitlement
  independently of the device. Reasonable for v1 given apps/api carries no billing
  tables by design; worth revisiting if this needs to resist a jailbroken/tampered
  client.
- **Nothing here has been built.** This was authored on Windows, with no Xcode
  available to compile against. Do a full build on a Mac before treating any of it
  as done — expect a small number of mechanical fixes (an import, a label) rather
  than structural rework, but budget the time.

## What was deliberately left out of v1

No social/community feed, no multiple-portfolio management UI (the app always trades
the caller's one "starter" portfolio), no push-notification delivery (alerts can be
created but nothing displays one firing yet — see the Alerts note above), no
non-`price_crossed` alert kinds. Leaderboard, Watchlist, price Alerts, onboarding, and
deep linking all shipped despite the original "don't need a ton of features" framing —
each was cheap given how much the backend already provides, and none of them touch
the paper-trading-only, no-real-money scope.

## Generating the app icon

`Resources/Assets.xcassets/AppIcon.appiconset` now points at `icon-1024.png`, but
that file doesn't exist until you render it — this was written on a machine with no
Xcode, so there was nothing to rasterize it with. On a Mac, from `CookedPaper`, run:

```
swift Scripts/GenerateIcon.swift
```

This renders `Scripts/GenerateIcon.swift`'s SwiftUI view (a candlestick pair in the
app's brand colors) via `ImageRenderer` and writes a real, opaque, alpha-free
1024×1024 PNG straight to
`Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Re-run it any time to
regenerate the icon after changing the design in that script.
