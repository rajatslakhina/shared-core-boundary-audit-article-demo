// PortabilityLens.swift
//
// The article's one-line test, made executable:
//
//   "Can this declaration be described without naming a platform type?"
//
// The lens answers that and nothing else. It is deliberately conservative:
// an unrecognised type is portable. A tool that flags every unfamiliar name
// gets muted in a week, and a muted tool is worth less than no tool.

/// The verdict for a single type name.
public enum Portability: Sendable, Hashable {
    case portable
    /// The type is owned by a platform framework that does not exist off-Apple.
    case platformBound(framework: String)
}

/// A catalog of type names that cannot cross the boundary, grouped by the
/// framework that owns them.
///
/// This is a denylist, not an allowlist, on purpose. The set of platform types
/// is small and slow-moving; the set of *your* types is large and changes every
/// sprint. Denylists stay quiet as the codebase grows. Allowlists do not.
public struct PlatformCatalog: Sendable {
    /// Exact type names, mapped to their owning framework.
    public let exactNames: [String: String]
    /// Name prefixes that reliably indicate a platform type (`NS`, `UI`, `CG`…),
    /// mapped to the framework they belong to.
    public let prefixes: [(prefix: String, framework: String)]
    /// Names that must never be flagged, checked before anything else.
    ///
    /// This field exists because the prefix heuristic collides with ordinary
    /// domain vocabulary, and I found that out the hard way: the first run of
    /// this auditor over its own sample module reported `SKU` as a StoreKit
    /// type, because `SK` + an uppercase `U` is indistinguishable from
    /// `SKProduct` by shape alone. Any prefix rule shipped without an escape
    /// hatch will do this to somebody's glossary.
    public let knownPortableNames: Set<String>

    public init(
        exactNames: [String: String],
        prefixes: [(prefix: String, framework: String)],
        knownPortableNames: Set<String> = []
    ) {
        self.exactNames = exactNames
        self.prefixes = prefixes
        self.knownPortableNames = knownPortableNames
    }

    /// The catalog used by `BoundaryAuditor` when none is supplied.
    ///
    /// Note what is *absent*: `Date`, `Data`, `URL` and `UUID` are all
    /// swift-corelibs-foundation types that genuinely compile on Linux and
    /// Android, so flagging them would be wrong. The line is drawn at
    /// Darwin-only frameworks, not at "sounds like Foundation."
    public static let appleDefault = PlatformCatalog(
        exactNames: [
            "UIImage": "UIKit",
            "UIColor": "UIKit",
            "UIViewController": "UIKit",
            "UIApplication": "UIKit",
            "Color": "SwiftUI",
            "Image": "SwiftUI",
            "AnyView": "SwiftUI",
            "AnyPublisher": "Combine",
            "PassthroughSubject": "Combine",
            "CurrentValueSubject": "Combine",
            "NSManagedObjectContext": "CoreData",
            "ModelContext": "SwiftData",
            "CLLocation": "CoreLocation",
            "UNNotificationRequest": "UserNotifications",
            "SecKeyRef": "Security",
            "OSLog": "OSLog",
            "Logger": "OSLog",
        ],
        prefixes: [
            (prefix: "UI", framework: "UIKit"),
            (prefix: "NS", framework: "Foundation (Darwin-only surface)"),
            (prefix: "CG", framework: "CoreGraphics"),
            (prefix: "CA", framework: "CoreAnimation"),
            (prefix: "CL", framework: "CoreLocation"),
            (prefix: "AV", framework: "AVFoundation"),
            (prefix: "SK", framework: "StoreKit"),
        ],
        // Domain acronyms that collide with the prefix table. Real teams will
        // add to this on day one, which is the point of exposing it.
        knownPortableNames: ["SKU", "UID"]
    )

    /// Classify a single type name.
    ///
    /// Precedence is carve-out, then exact match, then prefix. The carve-out has
    /// to come first or it cannot rescue a name the prefix table would claim.
    public func classify(_ typeName: String) -> Portability {
        if knownPortableNames.contains(typeName) {
            return .portable
        }
        if let framework = exactNames[typeName] {
            return .platformBound(framework: framework)
        }
        for entry in prefixes where Self.hasPlatformPrefix(typeName, entry.prefix) {
            return .platformBound(framework: entry.framework)
        }
        return .portable
    }

    /// A prefix match only counts when the character *after* the prefix is
    /// uppercase. Without this, `Update` matches the `UI` prefix — and a tool
    /// that flags `UpdatePolicy` as UIKit is a tool nobody runs twice.
    static func hasPlatformPrefix(_ typeName: String, _ prefix: String) -> Bool {
        guard typeName.count > prefix.count, typeName.hasPrefix(prefix) else { return false }
        let boundary = typeName.index(typeName.startIndex, offsetBy: prefix.count)
        return typeName[boundary].isUppercase
    }
}

/// Applies `PlatformCatalog` to whole declarations.
public struct PortabilityLens: Sendable {
    public let catalog: PlatformCatalog

    public init(catalog: PlatformCatalog = .appleDefault) {
        self.catalog = catalog
    }

    /// Every platform-bound type this declaration names, in signature order,
    /// with duplicates removed. Order is preserved so that a report reads the
    /// way the signature does.
    public func platformBoundTypes(in declaration: Declaration) -> [(type: String, framework: String)] {
        var seen: Set<String> = []
        var result: [(type: String, framework: String)] = []
        for typeName in declaration.referencedTypes {
            guard case .platformBound(let framework) = catalog.classify(typeName) else { continue }
            guard seen.insert(typeName).inserted else { continue }
            result.append((type: typeName, framework: framework))
        }
        return result
    }

    /// The article's test, as a single call.
    public func isDescribableWithoutPlatformTypes(_ declaration: Declaration) -> Bool {
        platformBoundTypes(in: declaration).isEmpty
    }
}
