# BoundaryAudit

A static audit for the boundary between a shared Swift core and the platforms that consume it — and, more to the point, for **who gets the ticket** when that boundary breaks.

Swift 6.3 shipped the first official Swift SDK for Android, and there is deliberately no SwiftUI on the other side. So the SDK does not let you ship one app. It forces you to say out loud where your app stops being a UI and starts being a domain — and most iOS codebases cannot answer that, because the honest boundary is not the one on the architecture diagram.

`BoundaryAudit` takes a description of a module's declarations and reports the four ways that boundary reliably breaks. Then it does the part a linter never does: it routes each finding to a team, twice — once assuming the shared core has a named owner, and once assuming it does not.

On the sample module that ships with this repo, that produces two very different numbers from **the same eleven findings**:

| Shared core is… | iOS team | Shared-core owner | Android consumer | iOS share |
|---|---|---|---|---|
| owned by a named team | 4 | 6 | 1 | **36%** |
| owned by nobody | 10 | 0 | 1 | **91%** |

Nothing about the code changes between those two rows. Only the org chart does.

---

## The four rules

| # | Rule | Example from the sample | Routes to |
|---|---|---|---|
| 1 | Platform type in a core signature | `PromoBannerCopy.render(for:)` names `Color`, `Image` | iOS team |
| 2 | Isolation only one platform has | `@MainActor CheckoutSession.begin(with:)` | iOS team |
| 2b | Isolation the consumer inherits | `@PaymentActor PaymentCoordinator.authorize(_:)` | Android consumer |
| 3 | Untyped throw across the boundary | `OrderRepository.save(_:) throws` → `any Error` | Shared-core owner |
| 4 | Collaborator constructed, not injected | `AnalyticsRecorder` builds `Logger` + `URLSession` itself | Shared-core owner |

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

## Two things that went wrong building this

**The auditor flagged its own sample.** The first run reported `SKU` as a StoreKit type, because `SK` followed by an uppercase letter is indistinguishable from `SKProduct` by shape alone. Any prefix heuristic shipped without an escape hatch will do this to somebody's glossary, so `PlatformCatalog` grew a `knownPortableNames` carve-out checked *before* both the exact table and the prefix table.

**The sample module broke the type checker.** `SampleInventory` started life as one twelve-element array literal. It compiled locally and then failed a clean build with *"the compiler is unable to type-check this expression in reasonable time."* Every element has six parameters, five of them defaulted, so the solver's work scales with the literal. Splitting it into two explicitly-typed `[Declaration]` arrays took the clean build from a hard failure to 1.7 seconds.

`Date`, `Data`, `URL` and `UUID` are deliberately absent from the platform catalog — they are swift-corelibs-foundation types that genuinely compile off-Apple, and flagging them would be a false positive.

---

## How to run it

```
git clone https://github.com/rajatslakhina/shared-core-boundary-audit-article-demo.git
cd shared-core-boundary-audit-article-demo
open Demo.xcodeproj
```

Pick any iOS Simulator, then Build & Run. No other setup — `Demo.xcodeproj` consumes the library through a local Swift package reference to the repo root, so there is no second repo to fetch and no package to resolve over the network.

The demo screen is written to render all eleven findings with a segmented control that switches the ownership model, so flipping it redistributes the same findings across teams. Be aware of the caveat below before you trust that sentence: `BoundaryAuditUI` is `#if canImport(SwiftUI)`-guarded, and the machine that produced this repo has no SwiftUI — so not one line of that screen has ever been compiled, let alone run. You will see it before I do.

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
| `swift build` | Clean — Swift 6.0.3, `aarch64-unknown-linux-gnu`. Verified from a **fresh clone of this repo**, not just locally |
| `swift test` | **25/25 passing** |
| `BoundaryAudit` compiles with zero platform imports | Yes — this is the article's own claim, so the library has to survive it |
| `Demo.xcodeproj` structural validation | Brace/paren balance checked; all 24 object IDs defined and referenced; scheme `BlueprintIdentifier` matches the target |
| **Launched on an iOS Simulator** | **No.** The build that produced this repo ran in a headless Linux sandbox with no `xcodebuild` or `simctl`, and desktop control could not be authorised during an unattended scheduled run. There is no Simulator screenshot in this repo because no Simulator run happened. |
| `BoundaryAuditUI` compiled against real SwiftUI | **No** — it is `#if canImport(SwiftUI)`-guarded and compiles to an empty module on Linux |

Every number in this README comes from the test suite, which asserts all of them (`OwnershipMathTests`). The article linked below carries the diagrams.

---

## Layout

```
Sources/BoundaryAudit/       Inventory, PortabilityLens, Ownership, BoundaryAuditor, SampleInventory
Sources/BoundaryAuditUI/     SwiftUI demo screen (guarded)
Tests/BoundaryAuditTests/    25 tests
Demo.xcodeproj/              Runnable app, local package reference to "."
Demo/DemoApp.swift           @main entry point
```

Article: **[Swift on Android Isn't a Port. It's a Re-Org — and I Put a Number on It.](https://medium.com/@er.rajatlakhina/swift-on-android-isnt-a-port-it-s-a-re-org-and-i-put-a-number-on-it-15a97c0d61bd)**

MIT licensed.
