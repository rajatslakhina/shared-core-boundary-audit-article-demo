#if canImport(SwiftUI)
import SwiftUI
import BoundaryAudit

/// The demo screen. Flip the ownership toggle and watch the same eleven
/// findings redistribute — that redistribution is the whole argument.
public struct BoundaryAuditView: View {
    @State private var model: OwnershipModel = .staffedCoreTeam

    private let report = BoundaryAuditor().audit(SampleInventory.checkoutCore)

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                summarySection
                ownershipSection
                findingsSection
            }
            .navigationTitle("Boundary Audit")
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            LabeledContent("Module", value: report.moduleName)
            LabeledContent("Core declarations", value: "\(report.declarationsAudited)")
            LabeledContent("Findings", value: "\(report.findings.count)")
        } header: {
            Text("Audit")
        } footer: {
            Text("Presentation-layer declarations are exempt from every rule.")
        }
    }

    private var ownershipSection: some View {
        let load = report.ticketLoad(under: model)
        return Section {
            Picker("Shared core is", selection: $model) {
                Text("Owned by a core team").tag(OwnershipModel.staffedCoreTeam)
                Text("Owned by nobody").tag(OwnershipModel.impliedOwnership)
            }
            .pickerStyle(.segmented)

            ForEach(Owner.allCases, id: \.self) { owner in
                LabeledContent(owner.label) {
                    Text("\(load.count(for: owner))  ·  \(percent(load.share(for: owner)))")
                        .monospacedDigit()
                        .foregroundStyle(owner == .iOSTeam ? .primary : .secondary)
                        .fontWeight(owner == .iOSTeam ? .semibold : .regular)
                }
            }
        } header: {
            Text("Who gets the ticket")
        } footer: {
            Text("Naming no owner moves \(report.implicitIOSTeamSurcharge) of \(report.findings.count) findings onto the iOS team.")
        }
    }

    private var findingsSection: some View {
        ForEach(BoundaryBreak.allCases, id: \.self) { kind in
            let findings = report.findings(ofKind: kind)
            if !findings.isEmpty {
                Section(kind.summary) {
                    ForEach(findings, id: \.self) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.declaration)
                                .font(.system(.subheadline, design: .monospaced))
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(finding.effectiveOwner(under: model).label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Formatting

    /// Whole-percent formatting without Foundation's formatter machinery, so
    /// this file stays readable and the rounding is visible at the call site.
    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

#Preview {
    BoundaryAuditView()
}
#endif
