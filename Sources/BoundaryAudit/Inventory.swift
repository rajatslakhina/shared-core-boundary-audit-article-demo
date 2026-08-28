// Inventory.swift
//
// The input side of the audit: a description of what a shared-core module
// actually declares. This is deliberately a *value* rather than something
// scraped from source, because the interesting arguments here are about the
// model, not about parsing Swift. In a real pipeline this struct is what an
// index-store or SourceKit pass emits.

/// Which side of the app a declaration lives on.
///
/// Every rule in this auditor is scoped to `.core`. A `@MainActor` view model
/// is not a portability defect — it is a view model. Running these rules across
/// an entire app is how static analysis earns its reputation for noise.
public enum Layer: String, Sendable, Hashable, CaseIterable {
    /// Intended to compile on every platform the product ships to.
    case core
    /// Platform-specific by design. Exempt from every rule here.
    case presentation
}

/// How a declaration is isolated.
public enum Isolation: Sendable, Hashable {
    case nonisolated
    /// `@MainActor`. On iOS that means the UI thread. It compiles anywhere, but
    /// on Android the main thread belongs to the JVM's Looper, which Swift's
    /// main executor does not drive — so the annotation keeps its meaning and
    /// loses its usefulness.
    case mainActor
    /// Some other global actor, by name.
    case globalActor(String)
    /// A member of an `actor` declaration. Portable.
    case actorInstance
}

/// What a declaration can throw, from a caller's point of view.
public enum ThrownErrors: Sendable, Hashable {
    case nonThrowing
    /// A typed throw whose error type the caller can switch over exhaustively.
    case typed(String)
    /// Bare `throws`. The caller receives `any Error` and cannot enumerate the
    /// cases, so it cannot render them, retry selectively, or test them.
    case untyped
}

/// One declaration in a module's public surface.
public struct Declaration: Sendable, Hashable {
    public let name: String
    public let layer: Layer
    /// Type names appearing anywhere in the signature.
    public let referencedTypes: [String]
    public let isolation: Isolation
    public let thrownErrors: ThrownErrors
    /// Concrete types the body constructs itself instead of receiving. A shared
    /// core that builds its own collaborators has pinned itself to whatever
    /// platform those collaborators came from.
    public let constructedDependencies: [String]

    public init(
        name: String,
        layer: Layer = .core,
        referencedTypes: [String] = [],
        isolation: Isolation = .nonisolated,
        thrownErrors: ThrownErrors = .nonThrowing,
        constructedDependencies: [String] = []
    ) {
        self.name = name
        self.layer = layer
        self.referencedTypes = referencedTypes
        self.isolation = isolation
        self.thrownErrors = thrownErrors
        self.constructedDependencies = constructedDependencies
    }
}

/// The module under audit.
public struct ModuleInventory: Sendable {
    public let moduleName: String
    public let declarations: [Declaration]

    public init(moduleName: String, declarations: [Declaration]) {
        self.moduleName = moduleName
        self.declarations = declarations
    }

    /// The declarations the rules actually apply to.
    public var coreDeclarations: [Declaration] {
        declarations.filter { $0.layer == .core }
    }
}
