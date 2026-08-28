// BoundaryAuditor.swift
//
// Four rules, one report, and the number the report exists to produce:
// how much of the shared core's maintenance lands on the iOS team when
// nobody has been given the core to own.

/// The result of auditing one module.
public struct AuditReport: Sendable {
    public let moduleName: String
    public let declarationsAudited: Int
    public let findings: [Finding]

    public init(moduleName: String, declarationsAudited: Int, findings: [Finding]) {
        self.moduleName = moduleName
        self.declarationsAudited = declarationsAudited
        self.findings = findings
    }

    public var isClean: Bool { findings.isEmpty }

    public func findings(ofKind kind: BoundaryBreak) -> [Finding] {
        findings.filter { $0.breakKind == kind }
    }

    /// Ticket distribution under a given ownership model.
    public func ticketLoad(under model: OwnershipModel) -> TicketLoad {
        var counts: [Owner: Int] = [:]
        for finding in findings {
            counts[finding.effectiveOwner(under: model), default: 0] += 1
        }
        return TicketLoad(model: model, countsByOwner: counts, total: findings.count)
    }

    /// The gap, in findings, between having a named core owner and not having
    /// one — measured as extra work landing on the iOS team.
    ///
    /// This is the headcount argument as an integer. It is exactly the count of
    /// `.sharedCoreOwner` findings, but computing it through both models keeps
    /// the two numbers honest against each other rather than asserting the
    /// identity in prose.
    public var implicitIOSTeamSurcharge: Int {
        let staffed = ticketLoad(under: .staffedCoreTeam).count(for: .iOSTeam)
        let implied = ticketLoad(under: .impliedOwnership).count(for: .iOSTeam)
        return implied - staffed
    }
}

/// Applies the four boundary rules to a module inventory.
public struct BoundaryAuditor: Sendable {
    public let lens: PortabilityLens

    public init(lens: PortabilityLens = PortabilityLens()) {
        self.lens = lens
    }

    public func audit(_ inventory: ModuleInventory) -> AuditReport {
        let core = inventory.coreDeclarations
        var findings: [Finding] = []
        for declaration in core {
            findings.append(contentsOf: platformTypeFindings(declaration))
            findings.append(contentsOf: concurrencyFindings(declaration))
            findings.append(contentsOf: errorTaxonomyFindings(declaration))
            findings.append(contentsOf: dependencyFindings(declaration))
        }
        return AuditReport(
            moduleName: inventory.moduleName,
            declarationsAudited: core.count,
            findings: findings
        )
    }

    // MARK: - Rule 1: platform types in core signatures

    private func platformTypeFindings(_ declaration: Declaration) -> [Finding] {
        lens.platformBoundTypes(in: declaration).map { leak in
            Finding(
                declaration: declaration.name,
                breakKind: .platformType,
                // The iOS team wrote it and is the only side that knows what
                // the type was standing in for.
                nominalOwner: .iOSTeam,
                detail: "Signature names \(leak.type), owned by \(leak.framework).",
                remediation: "Replace \(leak.type) with a core-owned value type; map to \(leak.framework) in the iOS presentation layer."
            )
        }
    }

    // MARK: - Rule 2: isolation the second platform does not have

    private func concurrencyFindings(_ declaration: Declaration) -> [Finding] {
        switch declaration.isolation {
        case .nonisolated, .actorInstance:
            return []
        case .mainActor:
            return [Finding(
                declaration: declaration.name,
                breakKind: .concurrencyModel,
                nominalOwner: .iOSTeam,
                detail: "@MainActor on core code. The main actor is a UI-thread guarantee, and a second consumer has a different main thread.",
                remediation: "Make the declaration nonisolated or move it onto an actor; hop to @MainActor at the view boundary instead."
            )]
        case .globalActor(let name):
            return [Finding(
                declaration: declaration.name,
                breakKind: .concurrencyModel,
                // A custom global actor is ordinary Swift and compiles
                // everywhere, so this is not the core's defect to fix. The cost
                // is real but it lands on the consumer, which has to arrange its
                // own threading around a schedule it did not choose.
                nominalOwner: .androidConsumer,
                detail: "Global actor @\(name) is portable Swift, but it exports a serialisation schedule the second consumer inherits rather than chooses.",
                remediation: "Document @\(name) as part of the boundary contract and adapt the consumer's threading to it; do not re-serialise on top of it."
            )]
        }
    }

    // MARK: - Rule 3: errors a second consumer cannot enumerate

    private func errorTaxonomyFindings(_ declaration: Declaration) -> [Finding] {
        guard declaration.thrownErrors == .untyped else { return [] }
        return [Finding(
            declaration: declaration.name,
            breakKind: .errorTaxonomy,
            nominalOwner: .sharedCoreOwner,
            detail: "Bare throws. A second consumer receives any Error and cannot switch exhaustively, so it cannot render, retry, or test the failure paths.",
            remediation: "Declare a typed throw over a core-owned error enum; keep bridging to platform error types outside the core."
        )]
    }

    // MARK: - Rule 4: collaborators the core builds itself

    private func dependencyFindings(_ declaration: Declaration) -> [Finding] {
        declaration.constructedDependencies.map { dependency in
            let classification = lens.catalog.classify(dependency)
            let detail: String
            switch classification {
            case .platformBound(let framework):
                detail = "Constructs \(dependency) (\(framework)) internally, so the core cannot be built without \(framework)."
            case .portable:
                detail = "Constructs \(dependency) internally, so no consumer can substitute it — including tests."
            }
            return Finding(
                declaration: declaration.name,
                breakKind: .dependencyInjection,
                nominalOwner: .sharedCoreOwner,
                detail: detail,
                remediation: "Inject \(dependency) behind a core-owned protocol; let each platform supply its own conformance."
            )
        }
    }
}
