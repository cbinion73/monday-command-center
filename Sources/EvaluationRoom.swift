import SwiftUI

struct EvaluationRoom: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case coverage = "Coverage"
        case gates = "Release Gates"
        case connectors = "Connectors"
        case pilot = "Pilot"
        case enterprise = "Enterprise Claim"
        var id: String { rawValue }
        var viewID: String {
            switch self {
            case .overview: "evaluation-overview"
            case .coverage: "evaluation-coverage"
            case .gates: "evaluation-release-gates"
            case .connectors: "evaluation-connectors"
            case .pilot: "evaluation-pilot"
            case .enterprise: "evaluation-enterprise-claim"
            }
        }
    }

    @State private var projection: EvaluationProjection?
    @State private var lastValidProjection: EvaluationProjection?
    @State private var section: Section = .overview
    @State private var errorMessage: String?
    @ObservedObject private var pairing = CommandCenterPairing.shared

    var body: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                picker
                if let projection {
                    content(projection, stale: false)
                } else if let lastValidProjection {
                    diagnostic("The newest evaluation projection was rejected or expired. This retained view is explicitly stale and cannot produce readback.")
                    content(lastValidProjection, stale: true)
                } else {
                    emptyState
                }
            }
            .padding(30)
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: section) { await writeReadback() }
        .task(id: pairing.revision) { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("MONDAY EVALUATION", systemImage: "checkmark.seal.text.page.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(DashboardPalette.accent)
                Text("Evaluation & Pilot")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("Read-only release evidence, coverage, connector decisions, pilot progress, and claim boundaries.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
        }
    }

    private var picker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Section.allCases) { item in
                Button(item.rawValue) { section = item }.buttonStyle(EvaluationTabStyle(selected: section == item))
            }
        }
    }

    @ViewBuilder private func content(_ value: EvaluationProjection, stale: Bool) -> some View {
        ScrollView {
            switch section {
            case .overview: overview(value, stale: stale)
            case .coverage: coverage(value)
            case .gates: gates(value)
            case .connectors: connectors(value)
            case .pilot: pilot(value)
            case .enterprise: enterprise(value)
            }
        }
    }

    private func overview(_ value: EvaluationProjection, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage { diagnostic(errorMessage) }
            HStack(spacing: 12) {
                metric("Cases", value.coverage.caseCount, "checklist")
                metric("Passed", value.coverage.passedCaseCount, "checkmark.circle.fill")
                metric("Gates", value.coverage.gateCount, "shield.lefthalf.filled")
                metric("Unresolved", value.coverage.unresolvedCount, "exclamationmark.triangle.fill")
            }
            card("Release candidate", icon: "shippingbox.fill") {
                HStack { status(value.releaseCandidate.compatibilityStatus); Spacer(); Text(value.releaseCandidate.releaseID).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4)) }
                Text("Plugin \(value.releaseCandidate.pluginVersion) · app \(value.releaseCandidate.appVersion) (\(value.releaseCandidate.appBuild))")
                    .foregroundStyle(.white.opacity(0.72))
                Text("Suite \(value.suite.suiteID) · \(value.suite.suiteVersion) · valid until \(value.validUntil.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            card("Inspection boundary", icon: "eye.fill") {
                Text(stale ? "This is retained evidence only. It is not current and no display receipt will be written." : "Command Center displays the evaluated record. It does not run tests, activate connectors, approve a pilot, or authorize a claim.")
                    .foregroundStyle(stale ? .orange : .white.opacity(0.72))
            }
        }
    }

    private func coverage(_ value: EvaluationProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            card("Denominator", icon: "chart.bar.doc.horizontal.fill") {
                Text("\(value.coverage.caseCount) of \(value.suite.requiredCaseCount) required cases are represented. \(value.coverage.releaseBlockingPassedCount) of \(value.coverage.releaseBlockingCount) release-blocking cases pass.")
                    .foregroundStyle(.white.opacity(0.72))
                Text("Fail \(value.coverage.failedCaseCount) · blocked \(value.coverage.blockedCaseCount) · skipped \(value.coverage.skippedCaseCount) · not run \(value.coverage.notRunCaseCount)")
                    .font(.caption).foregroundStyle(.white.opacity(0.52))
            }
            ForEach(value.caseCoverage) { item in
                card(item.caseID, icon: item.result == "pass" ? "checkmark.circle.fill" : "exclamationmark.circle.fill") {
                    HStack { status(item.result); status(item.severity); if item.releaseBlocking { status("release blocking") }; Spacer() }
                    Text("\(item.category) · \(item.requirementIDs.joined(separator: ", "))").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private func gates(_ value: EvaluationProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(value.gateResults) { gate in
                card(gate.gateID.replacingOccurrences(of: "-", with: " ").capitalized, icon: "lock.shield.fill") {
                    HStack { status(gate.status); Spacer(); Text(gate.evaluatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.white.opacity(0.42)) }
                    if gate.reasonCodes.isEmpty { Text("No blocking reason was projected.").foregroundStyle(.white.opacity(0.55)) }
                    ForEach(gate.reasonCodes, id: \.self) { Text("• \($0)").foregroundStyle(gate.status == "PASS" ? .white.opacity(0.58) : .orange) }
                }
            }
        }
    }

    private func connectors(_ value: EvaluationProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            card("Connection is not coverage", icon: "network.badge.shield.half.filled") {
                Text("Lifecycle, authentication, and reviewed content coverage are independent. An active connector can still have unknown or partial coverage.")
                    .foregroundStyle(.orange)
            }
            if value.connectorDecisions.isEmpty { empty("No connector decisions are projected.") }
            ForEach(value.connectorDecisions) { connector in
                card(connector.connectorID, icon: "point.3.connected.trianglepath.dotted") {
                    HStack { status("Tier \(connector.tier)"); status(connector.status); status(connector.authenticationState); status(connector.coverageState); Spacer() }
                    Text("Route \(connector.route) · source \(connector.sourceID) · approval \(connector.approvalState)").font(.caption).foregroundStyle(.white.opacity(0.58))
                    Text("Processed \(connector.processedCount) of \(connector.itemCount); unresolved \(connector.unresolvedCount). Read-only: \(connector.readOnly ? "yes" : "no")")
                        .font(.caption).foregroundStyle(.white.opacity(0.48))
                }
            }
        }
    }

    private func pilot(_ value: EvaluationProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Bounded pilot", icon: "person.crop.circle.badge.clock.fill") {
                HStack { status(value.pilot.status); status(value.pilot.disposition); Spacer(); Text(value.pilot.pilotID).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4)) }
                Text("\(value.pilot.cohort) · \(value.pilot.plannedBusinessDays) business days · \(value.pilot.timezone)").foregroundStyle(.white.opacity(0.72))
                progress("Planning checkpoints", current: value.pilot.attemptedCheckpoints, total: value.pilot.plannedCheckpoints)
                progress("Unattended rollovers", current: value.pilot.unattendedRolloversCompleted, total: value.pilot.unattendedRolloversPlanned)
                progress("Tier 1 attempts", current: value.pilot.tier1AttemptsRecorded, total: value.pilot.tier1AttemptsPlanned)
                Text("Manual interventions: \(value.pilot.manualInterventionCount)").font(.caption).foregroundStyle(value.pilot.manualInterventionCount == 0 ? .green : .orange)
            }
            card("Acceptance boundary", icon: "hand.raised.fill") {
                Text("Pilot acceptance requires the fixed denominator and an explicit accept, extend, or stop disposition. Accepted single-user evidence remains single-user evidence.")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func enterprise(_ value: EvaluationProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card(value.enterpriseClaim.claimAllowed ? "ENTERPRISE CLAIM ALLOWED" : "ENTERPRISE CLAIM BLOCKED", icon: value.enterpriseClaim.claimAllowed ? "checkmark.shield.fill" : "nosign") {
                status(value.enterpriseClaim.status)
                Text(value.enterpriseClaim.safeStatement).font(.title3.bold()).foregroundStyle(value.enterpriseClaim.claimAllowed ? .green : .orange)
                Text("Evidence scope: \(value.enterpriseClaim.scope)").font(.caption).foregroundStyle(.white.opacity(0.55))
                ForEach(value.enterpriseClaim.unmetRequirementIDs, id: \.self) { Text("• \($0)").foregroundStyle(.orange) }
            }
            card("Non-inference rule", icon: "exclamationmark.shield.fill") {
                Text("An accepted single-user bounded pilot never establishes enterprise readiness. Only a passing machine enterprise gate with representative enterprise evidence can allow that claim.")
                    .foregroundStyle(.orange)
            }
        }
    }

    @MainActor private func refresh() async {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2"
        let plugin = pairing.evaluationPluginValidation
        guard case .compatible(let pluginVersion) = plugin else {
            projection = nil
            errorMessage = plugin.message
            return
        }
        do {
            let candidate = try EvaluationReader.load()
            let result = candidate.validation(appVersion: appVersion, pairedPluginVersion: pluginVersion)
            guard result == .current else {
                projection = nil
                errorMessage = "Evaluation projection rejected: \(String(describing: result))."
                return
            }
            projection = candidate
            lastValidProjection = candidate
            errorMessage = nil
            await writeReadback()
        } catch {
            projection = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func writeReadback() async {
        guard let projection,
              case .compatible(let pluginVersion) = pairing.evaluationPluginValidation else { return }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2"
        guard let receipt = projection.readback(viewID: section.viewID, consumer: "MONDAY Command Center", appVersion: appVersion, pairedPluginVersion: pluginVersion) else { return }
        try? EvaluationReadbackWriter.write(receipt)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.text.page").font(.system(size: 38)).foregroundStyle(.white.opacity(0.35))
            Text("EVALUATION NOT AVAILABLE").font(.caption.bold()).tracking(1.2).foregroundStyle(.orange)
            Text(errorMessage ?? "Install a compatible MONDAY evaluation capability and publish a current privacy-reduced inspection projection.")
                .foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center).frame(maxWidth: 680)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ title: String, current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption); Spacer(); Text("\(current) / \(total)").font(.caption.monospaced()) }.foregroundStyle(.white.opacity(0.58))
            ProgressView(value: Double(current), total: Double(max(total, 1))).tint(current == total ? .green : DashboardPalette.accent)
        }
    }
    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.white.opacity(0.55)); Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white) }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) { Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white); content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
    }
    private func status(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 4)
            .background((text == "PASS" || text == "pass" || text == "compatible" || text == "complete" || text == "accepted" ? Color.green : Color.orange).opacity(0.16), in: Capsule())
            .foregroundStyle(text == "PASS" || text == "pass" || text == "compatible" || text == "complete" || text == "accepted" ? .green : .orange)
    }
    private func diagnostic(_ text: String) -> some View { Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
    private func empty(_ text: String) -> some View { Text(text).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }
}

private struct EvaluationTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.58))
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(selected ? DashboardPalette.accent.opacity(0.22) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? DashboardPalette.accent.opacity(0.55) : Color.white.opacity(0.07)))
    }
}
