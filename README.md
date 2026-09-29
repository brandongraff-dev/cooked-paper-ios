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
    Paywall/                StoreKit 2 subscription store + the paywall screen
    Features/               Onboarding, Discover, TokenDetail
                            (chart + trade), Trade, Portfolio, Leaderboard,
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
     Expo app already uses. Enable **Sign in with Apple** on the App ID.
3. **App Store Connect — subscriptions**
   - Create a subscription group ("Cooked Paper Pro") with two auto-renewable
     subscriptions: `app.cooked.paper.monthly` ($7.99/mo) and
     `app.cooked.paper.annual` ($29.99/yr). These product IDs must match
     `Sources/Paywall/SubscriptionStore.swift`'s `ProductID` exactly.
   - `StoreKit/Products.storekit` mirrors this for local testing (Xcode scheme →
     Options → StoreKit Configuration) without needing App Store Connect at all
     during development. Xcode will offer to repair its internal IDs the first time
     you open it — let it.
4. **API base URL** — `Sources/Networking/APIClient.swift`'s `APIConfig.baseURL`
   points at `https://api.cooked.trade`: the backend on the DigitalOcean droplet
   behind Cloudflare (see `docs/deploy-digitalocean.md` in the backend repo). Point it
   at a local API for development.

## Product decisions this was built against

- **Everyone signs in: Apple or Google.** No guest sessions. Sign-in
  happens in onboarding right after the practice round; each provider proves
  identity to `apps/api`, which mints the session (access token + a refresh token
  returned in the body because the app sends `X-Cooked-Client: ios`, stored in the
  Keychain). The portfolio belongs to the account, so it follows the person to any
  device. Settings has Sign out and Delete account (App Store 5.1.1(v)). There is
  no wallet login (Privy was removed; there is no real trading).
  - **Google** needs the iOS OAuth client id: set `GOOGLE_IOS_CLIENT_ID` and
    `GOOGLE_REVERSED_CLIENT_ID` in `project.yml`, and add that client id to the
    API's Google audiences.
  - **Apple** needs the Sign in with Apple capability on the App ID
    (`app.cooked.paper`); the entitlement is already in `project.yml`.
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
- **The live socket implements the server's real resume protocol**, not a
  simplification — it tracks the last seen `seq` per portfolio, resumes with
  `sinceSeq` on reconnect, and treats a `counterReset`/`truncated` gap as a fresh
  baseline rather than trying to replay deltas. A heartbeat watchdog tears down and
  reconnects the socket if `heartbeatIntervalMs` elapses with no tick.
- **`cookedpaper://token/<mint>` opens a token's detail screen** from anywhere in the
  app via `DeepLinkRouter`, presented as a sheet over whichever tab is active.
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
the caller's one "starter" portfolio), no watchlist or price alerts. Leaderboard, onboarding, and deep linking all shipped
despite the original "don't need a ton of features" framing —
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
