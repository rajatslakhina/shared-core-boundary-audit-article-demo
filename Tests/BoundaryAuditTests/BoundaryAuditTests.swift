import XCTest
@testable import BoundaryAudit

final class PortabilityLensTests: XCTestCase {

    func testExactPlatformNameIsFlagged() {
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["Color"])
        let leaks = lens.platformBoundTypes(in: decl)
        XCTAssertEqual(leaks.count, 1)
        XCTAssertEqual(leaks.first?.type, "Color")
        XCTAssertEqual(leaks.first?.framework, "SwiftUI")
    }

    func testUnknownTypesArePortable() {
        // The catalog is a denylist. Anything the team owns must pass.
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["Cart", "Money", "PricingRule"])
        XCTAssertTrue(lens.isDescribableWithoutPlatformTypes(decl))
    }

    func testCorelibsFoundationTypesArePortable() {
        // Date/Locale/URL/UUID compile off-Apple. Flagging them is a false positive.
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["Date", "Locale", "URL", "UUID", "Data"])
        XCTAssertTrue(lens.isDescribableWithoutPlatformTypes(decl))
    }

    // Edge case: the prefix rule must not fire on ordinary domain names that
    // merely begin with a hot prefix. This is the difference between a tool
    // that gets adopted and one that gets muted.
    func testPrefixRuleRequiresAnUppercaseBoundary() {
        let lens = PortabilityLens()
        let decl = Declaration(
            name: "f",
            referencedTypes: ["UpdatePolicy", "Nsight", "Cargo", "Uid", "Cathedral"]
        )
        XCTAssertTrue(
            lens.isDescribableWithoutPlatformTypes(decl),
            "lowercase-boundary names must not match UI/NS/CG/CA prefixes"
        )
    }

    func testPrefixRuleFiresOnGenuinePlatformNames() {
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["UIScrollView", "CGRect", "NSAttributedString"])
        XCTAssertEqual(lens.platformBoundTypes(in: decl).count, 3)
    }

    // Edge case: a bare prefix with nothing after it is not a type match.
    func testBarePrefixIsNotAMatch() {
        XCTAssertFalse(PlatformCatalog.hasPlatformPrefix("UI", "UI"))
        XCTAssertFalse(PlatformCatalog.hasPlatformPrefix("", "UI"))
        XCTAssertTrue(PlatformCatalog.hasPlatformPrefix("UIView", "UI"))
    }

    // Regression: the first run of this auditor over its own sample flagged
    // SKU as StoreKit, because SK + uppercase U looks exactly like SKProduct.
    func testDomainAcronymsSurviveThePrefixTable() {
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["SKU", "UID"])
        XCTAssertTrue(lens.isDescribableWithoutPlatformTypes(decl))
    }

    func testCarveOutBeatsAnExactPlatformMatch() {
        // Precedence has to be carve-out first, or the escape hatch is unusable
        // for a name that is also in the exact table.
        let catalog = PlatformCatalog(
            exactNames: ["Color": "SwiftUI"],
            prefixes: [],
            knownPortableNames: ["Color"]
        )
        XCTAssertEqual(catalog.classify("Color"), .portable)
    }

    func testDuplicateLeaksAreReportedOnce() {
        let lens = PortabilityLens()
        let decl = Declaration(name: "f", referencedTypes: ["Color", "Color", "Image"])
        XCTAssertEqual(lens.platformBoundTypes(in: decl).map(\.type), ["Color", "Image"])
    }
}

final class BoundaryAuditorRuleTests: XCTestCase {

    private let auditor = BoundaryAuditor()

    func testPresentationLayerIsExempt() {
        // Every rule would fire on this declaration if the layer were .core.
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(
                name: "Screen.body",
                layer: .presentation,
                referencedTypes: ["AnyView", "UIViewController"],
                isolation: .mainActor,
                thrownErrors: .untyped,
                constructedDependencies: ["Logger"]
            )
        ])
        let report = auditor.audit(inventory)
        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.declarationsAudited, 0)
    }

    func testMainActorInCoreIsAnIOSTeamFinding() {
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(name: "S.begin()", isolation: .mainActor)
        ])
        let findings = auditor.audit(inventory).findings(ofKind: .concurrencyModel)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.nominalOwner, .iOSTeam)
    }

    func testCustomGlobalActorRoutesToTheConsumer() {
        // Portable Swift, so it is not the core's defect — but the schedule is
        // inherited rather than chosen, and that adaptation is consumer work.
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(name: "P.authorize()", isolation: .globalActor("PaymentActor"))
        ])
        let findings = auditor.audit(inventory).findings(ofKind: .concurrencyModel)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.nominalOwner, .androidConsumer)
    }

    func testActorInstanceAndNonisolatedAreClean() {
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(name: "a", isolation: .actorInstance),
            Declaration(name: "b", isolation: .nonisolated),
        ])
        XCTAssertTrue(auditor.audit(inventory).findings(ofKind: .concurrencyModel).isEmpty)
    }

    func testTypedThrowsIsClean_untypedIsNot() {
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(name: "typed", thrownErrors: .typed("PricingError")),
            Declaration(name: "untyped", thrownErrors: .untyped),
            Declaration(name: "none", thrownErrors: .nonThrowing),
        ])
        let findings = auditor.audit(inventory).findings(ofKind: .errorTaxonomy)
        XCTAssertEqual(findings.map(\.declaration), ["untyped"])
        XCTAssertEqual(findings.first?.nominalOwner, .sharedCoreOwner)
    }

    func testConstructedDependencyDetailDistinguishesPlatformFromPortable() {
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(name: "R.record()", constructedDependencies: ["Logger", "URLSession"])
        ])
        let findings = auditor.audit(inventory).findings(ofKind: .dependencyInjection)
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings[0].detail.contains("OSLog"))
        XCTAssertTrue(findings[1].detail.contains("no consumer can substitute it"))
        XCTAssertTrue(findings.allSatisfy { $0.nominalOwner == .sharedCoreOwner })
    }

    func testOneDeclarationCanProduceMultipleDistinctBreaks() {
        let inventory = ModuleInventory(moduleName: "M", declarations: [
            Declaration(
                name: "OrderRepository.save(_:)",
                referencedTypes: ["Order", "NSManagedObjectContext"],
                isolation: .actorInstance,
                thrownErrors: .untyped,
                constructedDependencies: ["NSManagedObjectContext"]
            )
        ])
        let report = auditor.audit(inventory)
        XCTAssertEqual(report.findings.count, 3)
        XCTAssertEqual(
            Set(report.findings.map(\.breakKind)),
            [.platformType, .errorTaxonomy, .dependencyInjection]
        )
    }
}

final class OwnershipMathTests: XCTestCase {

    private let report = BoundaryAuditor().audit(SampleInventory.checkoutCore)

    func testSampleModuleShape() {
        XCTAssertEqual(report.declarationsAudited, 10)
        XCTAssertEqual(report.findings.count, 11)
        XCTAssertEqual(report.findings(ofKind: .platformType).count, 3)
        XCTAssertEqual(report.findings(ofKind: .concurrencyModel).count, 2)
        XCTAssertEqual(report.findings(ofKind: .errorTaxonomy).count, 3)
        XCTAssertEqual(report.findings(ofKind: .dependencyInjection).count, 3)
    }

    // This number gets quoted in prose, so it gets a test like every other one.
    // An earlier draft claimed four; the code has always produced five.
    func testFiveOfTenCoreDeclarationsAreClean() {
        let auditor = BoundaryAuditor()
        let flagged = Set(report.findings.map(\.declaration))
        let clean = SampleInventory.core.filter { !flagged.contains($0.name) }
        XCTAssertEqual(clean.count, 5)
        XCTAssertTrue(clean.allSatisfy { declaration in
            auditor.audit(
                ModuleInventory(moduleName: "one", declarations: [declaration])
            ).isClean
        })
    }

    func testStaffedOwnershipDistribution() {
        let load = report.ticketLoad(under: .staffedCoreTeam)
        XCTAssertEqual(load.total, 11)
        XCTAssertEqual(load.count(for: .iOSTeam), 4)
        XCTAssertEqual(load.count(for: .sharedCoreOwner), 6)
        XCTAssertEqual(load.count(for: .androidConsumer), 1)
    }

    func testImpliedOwnershipCollapsesCoreWorkOntoIOS() {
        let load = report.ticketLoad(under: .impliedOwnership)
        XCTAssertEqual(load.total, 11)
        XCTAssertEqual(load.count(for: .iOSTeam), 10)
        XCTAssertEqual(load.count(for: .sharedCoreOwner), 0)
        // The consumer's share is untouched by the collapse.
        XCTAssertEqual(load.count(for: .androidConsumer), 1)
    }

    func testIOSShareMovesFrom36To91Percent() {
        let staffed = report.ticketLoad(under: .staffedCoreTeam).share(for: .iOSTeam)
        let implied = report.ticketLoad(under: .impliedOwnership).share(for: .iOSTeam)
        XCTAssertEqual(staffed, 4.0 / 11.0, accuracy: 1e-9)
        XCTAssertEqual(implied, 10.0 / 11.0, accuracy: 1e-9)
    }

    func testSurchargeEqualsTheUnstaffedCoreQueue() {
        XCTAssertEqual(report.implicitIOSTeamSurcharge, 6)
    }

    // Edge case: an empty audit must report 0, not NaN. A dashboard that says
    // "NaN% of this work is yours" on a clean repo is worse than no dashboard.
    func testEmptyAuditProducesZeroSharesNotNaN() {
        let empty = BoundaryAuditor().audit(ModuleInventory(moduleName: "Empty", declarations: []))
        let load = empty.ticketLoad(under: .impliedOwnership)
        XCTAssertTrue(empty.isClean)
        XCTAssertEqual(load.total, 0)
        XCTAssertEqual(load.share(for: .iOSTeam), 0)
        XCTAssertFalse(load.share(for: .iOSTeam).isNaN)
        XCTAssertEqual(empty.implicitIOSTeamSurcharge, 0)
    }

    // Edge case: a module with no core declarations at all is clean, not a
    // divide-by-zero, even though it has declarations.
    func testAllPresentationModuleIsClean() {
        let inventory = ModuleInventory(moduleName: "UI", declarations: [
            Declaration(name: "v", layer: .presentation, referencedTypes: ["Color"], isolation: .mainActor)
        ])
        let report = BoundaryAuditor().audit(inventory)
        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.ticketLoad(under: .staffedCoreTeam).share(for: .iOSTeam), 0)
    }

    func testEveryFindingCarriesActionableText() {
        for finding in report.findings {
            XCTAssertFalse(finding.detail.isEmpty, "\(finding.declaration) has no detail")
            XCTAssertFalse(finding.remediation.isEmpty, "\(finding.declaration) has no remediation")
        }
    }
}
