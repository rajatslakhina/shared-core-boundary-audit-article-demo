// Ownership.swift
//
// The part that makes this an org tool rather than a linter.
//
// Every finding routes to whoever has to make the change. Three of the four
// break categories route somewhere obvious. The fourth — who owns the shared
// core itself — is the whole argument, because on most teams that owner does
// not exist as a named, staffed role. When it does not, its queue does not
// vanish; it silently drains into the iOS team.

/// The four ways a shared-core boundary breaks.
public enum BoundaryBreak: String, Sendable, Hashable, CaseIterable {
    /// A platform type appears in a core signature.
    case platformType
    /// Core code assumes an isolation model only one platform has.
    case concurrencyModel
    /// Core code throws errors a second consumer cannot enumerate.
    case errorTaxonomy
    /// Core code constructs its own collaborators instead of receiving them.
    case dependencyInjection

    public var summary: String {
        switch self {
        case .platformType:
            return "Platform type in a core signature"
        case .concurrencyModel:
            return "Isolation model only one platform has"
        case .errorTaxonomy:
            return "Untyped throw across the boundary"
        case .dependencyInjection:
            return "Collaborator constructed, not injected"
        }
    }
}

/// Who has to do the work.
public enum Owner: String, Sendable, Hashable, CaseIterable {
    /// The iOS feature team that wrote the leaking code.
    case iOSTeam
    /// Whoever owns the shared core's API design.
    case sharedCoreOwner
    /// The Android side, consuming what the core exposes.
    case androidConsumer

    public var label: String {
        switch self {
        case .iOSTeam: return "iOS team"
        case .sharedCoreOwner: return "Shared-core owner"
        case .androidConsumer: return "Android consumer"
        }
    }
}

/// Whether the shared core has a named owner.
public enum OwnershipModel: String, Sendable, Hashable, CaseIterable {
    /// A real, staffed core team. `.sharedCoreOwner` work goes to them.
    case staffedCoreTeam
    /// Nobody is named. This is the default state of every team that treats
    /// the port as a build-system project, and it is where `.sharedCoreOwner`
    /// work quietly becomes iOS work.
    case impliedOwnership
}

/// One boundary defect.
public struct Finding: Sendable, Hashable {
    public let declaration: String
    public let breakKind: BoundaryBreak
    /// Who owns it when the core has a real owner.
    public let nominalOwner: Owner
    public let detail: String
    public let remediation: String

    public init(
        declaration: String,
        breakKind: BoundaryBreak,
        nominalOwner: Owner,
        detail: String,
        remediation: String
    ) {
        self.declaration = declaration
        self.breakKind = breakKind
        self.nominalOwner = nominalOwner
        self.detail = detail
        self.remediation = remediation
    }

    /// Who actually receives the ticket under a given ownership model.
    ///
    /// This single collapse is the argument the whole library exists to make.
    public func effectiveOwner(under model: OwnershipModel) -> Owner {
        switch model {
        case .staffedCoreTeam:
            return nominalOwner
        case .impliedOwnership:
            return nominalOwner == .sharedCoreOwner ? .iOSTeam : nominalOwner
        }
    }
}

/// How findings distribute across teams under one ownership model.
public struct TicketLoad: Sendable, Hashable {
    public let model: OwnershipModel
    public let countsByOwner: [Owner: Int]
    public let total: Int

    public init(model: OwnershipModel, countsByOwner: [Owner: Int], total: Int) {
        self.model = model
        self.countsByOwner = countsByOwner
        self.total = total
    }

    public func count(for owner: Owner) -> Int {
        countsByOwner[owner] ?? 0
    }

    /// Share of all findings landing on one team, in the range `0...1`.
    ///
    /// Returns `0` for an empty audit rather than a NaN. A dashboard that
    /// renders "NaN% of work is yours" on a clean repo is worse than useless.
    public func share(for owner: Owner) -> Double {
        guard total > 0 else { return 0 }
        return Double(count(for: owner)) / Double(total)
    }
}
