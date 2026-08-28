# BoundaryAudit

A static audit for the boundary between a shared Swift core and the platforms that consume it — and, more to the point, for **who gets the ticket** when that boundary breaks.

Swift 6.3 shipped the first official Swift SDK for Android, and there is deliberately no SwiftUI on the other side. So the SDK does not let you ship one app. It forces you to say out loud where your app stops being a UI and starts being a domain — and most iOS codebases cannot answer that, because the honest boundary is not the one on the architecture diagram.

`BoundaryAudit` takes a description of a module's declarations and reports the four ways that boundary reliably breaks. Then it does the part a linter never does: it routes each finding to a team, twice — once assuming the shared core has a named owner, and once assuming it does not.

![The same 11 findings, routed twice. With a named core owner: 4 findings to the iOS team, 6 to the shared-core owner, 1 to the Android consumer — a 36% iOS share. With no named owner: 10 to the iOS team, 0 to the core, 1 to Android — a 91% iOS share. Six findings move teams.](article-assets/ownership-collapse.png)

Nothing about the code changes between those two columns. Only the org chart does.

---

## The four rules

![Four boundary rules over one module: platform type in a core signature, isolation only one platform has, isolation the consumer inherits, untyped throw across the boundary, and collaborator constructed rather than injected.](article-assets/four-breaks.png)

Every rule is scoped to `.core`. A `@MainActor` view model is not a portability defect — it is a view model, and a tool that flags it is a tool nobody runs twice.

```swift
let report = BoundaryAuditor().audit(SampleInventory.checkoutCore)

report.declarationsAudited                       // 10
report.findings.count                            // 11
report.ticketLoad(under: .staffedCoreTeam)
      .count(for: .iOSTeam)                      // 4
report.ticketLoad(under: .impliedOwnership)
      .count(for: .iOSTeam)                      // 10
report.implicitIOSTeamSurcharge                  // 6
```

The whole argument compresses into one ternary:

```swift
public func effectiveOwner(under model: OwnershipModel) -> Owner {
    switch model {
    case .staffedCoreTeam:
        return nominalOwner
    case .impliedOwnership:
        return nominalOwner == .sharedCoreOwner ? .iOSTeam : nominalOwner
    }
}
```

There is no such thing as unowned work — only work whose owner has not been named.

---

## The test that made the tool honest

The first run of this auditor over its own sample module reported `SKU` as a StoreKit type, because `SK` followed by an uppercase letter is indistinguishable from `SKProduct` by shape alone. Any prefix heuristic shipped without an escape hatch will do this to somebody's glossary, so `PlatformCatalog` grew a `knownPortableNames` carve-out that is checked *before* both the exact table and the prefix table.

`Date`, `Locale`, `URL` and `UUID` are deliberately absent from the platform catalog — they are swift-corelibs-foundation types that genuinely compile off-Apple, and flagging them would be a false positive.

---

## How to run it

```
git clone https://github.com/rajatslakhina/shared-core-boundary-audit-article-demo.git
cd shared-core-boundary-audit-article-demo
open Demo.xcodeproj
```

Pick any iOS Simulator, then Build & Run. No other setup — `Demo.xcodeproj` consumes the library through a local Swift package reference to the repo root, so there is no second repo to fetch and no package to resolve over the network.

The demo screen shows all eleven findings and a segmented control that switches the ownership model. Flipping it redistributes the same findings across teams, which is the entire point.

To run the library on its own:

```
swift build
swift test
```

---

## Verification status

Honest accounting of what was and was not verified:

| Check | Status |
|---|---|
| `swift build` | Clean — Swift 6.0.3, `aarch64-unknown-linux-gnu` |
| `swift test` | **24/24 passing** |
| `BoundaryAudit` compiles with zero platform imports | Yes — this is the article's own claim, so the library has to survive it |
| `Demo.xcodeproj` structural validation | Brace/paren balance checked; all 24 object IDs defined and referenced; scheme `BlueprintIdentifier` matches the target |
| **Launched on an iOS Simulator** | **No.** The build that produced this repo ran in a headless Linux sandbox with no `xcodebuild` or `simctl`, and desktop control could not be authorised during an unattended scheduled run. There is no Simulator screenshot in this repo because no Simulator run happened. |
| `BoundaryAuditUI` compiled against real SwiftUI | **No** — it is `#if canImport(SwiftUI)`-guarded and compiles to an empty module on Linux |

The two images above are generated diagrams, not screenshots of the app. The numbers in them are asserted against the Swift test suite's own expectations before the figures are drawn, so a stale figure cannot survive a code change.

---

## Layout

```
Sources/BoundaryAudit/       Inventory, PortabilityLens, Ownership, BoundaryAuditor, SampleInventory
Sources/BoundaryAuditUI/     SwiftUI demo screen (guarded)
Tests/BoundaryAuditTests/    24 tests
Demo.xcodeproj/              Runnable app, local package reference to "."
Demo/DemoApp.swift           @main entry point
```

Article: (added after publish)

MIT licensed.
