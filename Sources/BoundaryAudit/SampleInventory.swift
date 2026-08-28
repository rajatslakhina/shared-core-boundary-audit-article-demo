// SampleInventory.swift
//
// A checkout module that passes every architecture review it has ever had.
// Ten core declarations, a clean layer split, an actor where you would expect
// one. It is also unshippable to a second platform, and the audit says exactly
// where and — the part that matters — whose calendar pays for it.
//
// Four of the ten declarations are deliberately clean. A sample where
// everything fails proves nothing about the rules.
//
// Note the explicit `[Declaration]` annotations and the split into two arrays.
// Written as one twelve-element literal, this file compiled locally and then
// failed a clean build with "the compiler is unable to type-check this
// expression in reasonable time" — every element has six defaulted parameters,
// so the solver's work grows with the literal, not with the file. Annotating
// the element type collapses it.

public enum SampleInventory {
    public static let checkoutCore = ModuleInventory(
        moduleName: "CheckoutCore",
        declarations: core + presentation
    )

    /// The ten declarations the rules apply to.
    static let core: [Declaration] = [
            // Clean. Pure domain arithmetic over core-owned types.
            Declaration(
                name: "CartTotalCalculator.total(for:)",
                referencedTypes: ["Cart", "Money"]
            ),

            // Two breaks in one signature: the isolation is a UI-thread promise,
            // and the throw is unenumerable.
            Declaration(
                name: "CheckoutSession.begin(with:)",
                referencedTypes: ["Cart", "CheckoutToken"],
                isolation: .mainActor,
                thrownErrors: .untyped
            ),

            // Clean, and typed throws are the reason.
            Declaration(
                name: "PricingRuleEngine.apply(_:to:)",
                referencedTypes: ["PricingRule", "Cart"],
                thrownErrors: .typed("PricingError")
            ),

            // Presentation logic that drifted into the core. Nothing here is
            // wrong on iOS, which is precisely why it survived review.
            Declaration(
                name: "PromoBannerCopy.render(for:)",
                referencedTypes: ["Promotion", "Color", "Image"]
            ),

            // The worst declaration in the module: a platform type in the
            // signature, an unenumerable throw, and a collaborator it builds
            // itself. Being on an actor does not save any of that.
            Declaration(
                name: "OrderRepository.save(_:)",
                referencedTypes: ["Order", "NSManagedObjectContext"],
                isolation: .actorInstance,
                thrownErrors: .untyped,
                constructedDependencies: ["NSManagedObjectContext"]
            ),

            // Clean.
            Declaration(
                name: "AddressValidator.validate(_:)",
                referencedTypes: ["Address", "ValidationResult"],
                thrownErrors: .typed("AddressError")
            ),

            // Clean — and the interesting kind of clean. Locale and Date are
            // swift-corelibs-foundation types that genuinely compile off-Apple,
            // so flagging them would be a false positive.
            Declaration(
                name: "ReceiptFormatter.string(for:)",
                referencedTypes: ["Receipt", "Locale", "Date"]
            ),

            // Portable Swift that still costs the consumer something: a custom
            // global actor exports a schedule the far side inherits.
            Declaration(
                name: "PaymentCoordinator.authorize(_:)",
                referencedTypes: ["PaymentRequest", "PaymentResult"],
                isolation: .globalActor("PaymentActor"),
                thrownErrors: .untyped
            ),

            // Constructs both a platform logger and a network client. Neither
                        // appears in the signature, so no signature-level review catches it.
            Declaration(
                name: "AnalyticsRecorder.record(_:)",
                referencedTypes: ["CheckoutEvent"],
                constructedDependencies: ["Logger", "URLSession"]
            ),

            // Clean. This is what the rest of the module should look like.
            Declaration(
                name: "InventoryReservation.hold(_:)",
                referencedTypes: ["SKU", "ReservationID"],
                isolation: .actorInstance,
                thrownErrors: .typed("InventoryError")
            ),
    ]

    /// Exempt by design — `@MainActor` and `AnyView` are correct here, and a
    /// tool that flags them is a tool nobody runs.
    static let presentation: [Declaration] = [
        Declaration(
            name: "CheckoutScreen.body",
            layer: .presentation,
            referencedTypes: ["AnyView", "Color"],
            isolation: .mainActor
        ),
        Declaration(
            name: "PaymentSheetPresenter.present(from:)",
            layer: .presentation,
            referencedTypes: ["UIViewController"],
            isolation: .mainActor,
            thrownErrors: .untyped
        ),
    ]
}
