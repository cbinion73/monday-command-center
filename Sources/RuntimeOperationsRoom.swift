import SwiftUI

struct RuntimeOperationsRoom: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case workflows = "Workflows & Dead Letters"
        case actions = "External Actions & Approvals"
        case commitments = "Commitments & Decisions"
        case sources = "Source Health & Coverage"
        case connections = "Connections & Diagnostics"
        case compatibility = "Compatibility & Migrations"
        case recovery = "Alerts & Recovery"
        var id: String { rawValue }
        var viewID: String {
            switch self {
            case .overview: "operations-overview"
            case .workflows: "operations-workflows-dead-letters"
            case .actions: "operations-external-actions"
            case .commitments: "operations-commitments-decisions"
            case .sources: "operations-source-health"
            case .connections: "operations-connections"
            case .compatibility: "operations-compatibility-migrations"
            case .recovery: "operations-alerts-recovery"
            }
        }
    }

    @State private var projection: RuntimeOperationsProjection?
    @State private var lastValidProjection: RuntimeOperationsProjection?
    @State private var section: Section = .overview
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                sectionPicker
                if let projection {
                    content(projection)
                } else if let lastValidProjection {
                    diagnostic("The latest runtime projection was rejected. The last valid projection remains visible and is explicitly stale.")
                    content(lastValidProjection)
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
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
        .task(id: section) { await writeReadbackForVisibleSection() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("MONDAY RUNTIME", systemImage: "gearshape.2.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5)
                    .foregroundStyle(DashboardPalette.accent)
                Text("Operations you can inspect")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("Read-only workflow state, retries, dead letters, governed external actions, compatibility, alerts, and recovery guidance.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { item in
                    Button(item.rawValue) { section = item }
                        .buttonStyle(RuntimeTabStyle(selected: section == item))
                }
            }
        }
    }

    @ViewBuilder private func content(_ value: RuntimeOperationsProjection) -> some View {
        ScrollView {
            switch section {
            case .overview: overview(value)
            case .workflows: workflows(value)
            case .actions: actions(value)
            case .commitments: commitments(value)
            case .sources: sources(value)
            case .connections: connections(value)
            case .compatibility: compatibility(value)
            case .recovery: recovery(value)
            }
        }
    }

    private func overview(_ value: RuntimeOperationsProjection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage { diagnostic(errorMessage) }
            HStack(spacing: 12) {
                metric("Workflows", value.coverage.workflowCount, "point.3.connected.trianglepath.dotted")
                metric("Retries", value.coverage.retryCount, "arrow.clockwise")
                metric("Dead letters", value.coverage.deadLetterCount, "tray.full.fill")
                metric("Open controls", value.coverage.unresolvedCount, "exclamationmark.shield.fill")
            }
            card("Runtime posture", icon: "checkmark.shield.fill") {
                HStack {
                    statusPill(value.compatibility.status)
                    Text("Runtime \(value.runtimeVersion) · schema \(value.schemaVersion)").foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(value.projectionID).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.42))
                }
                Text("Valid until \(value.validUntil.formatted(date: .abbreviated, time: .shortened)). Missing work remains visible; this projection cannot retry, replay, migrate, or create an external effect.")
                    .font(.caption).foregroundStyle(.white.opacity(0.52))
            }
            card("Action boundary", icon: "hand.raised.fill") {
                Text("Command Center is inspection-only. Recovery steps marked requires confirmation stop before any external or consequential action.")
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func workflows(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if value.workflows.isEmpty { empty("No runtime workflows are projected.") }
            ForEach(value.workflows) { workflow in
                card(workflow.kind.replacingOccurrences(of: "-", with: " ").capitalized, icon: "gearshape.2") {
                    HStack { statusPill(workflow.state); Text("Attempt \(workflow.attemptCount) of \(workflow.maxAttempts)").font(.caption).foregroundStyle(.white.opacity(0.52)); Spacer(); Text(workflow.workflowID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.38)) }
                    if let checkpoint = workflow.checkpoint { Text("Checkpoint: \(checkpoint)").font(.caption).foregroundStyle(.white.opacity(0.62)) }
                    if let next = workflow.nextAttemptAt { Text("Next attempt: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.orange.opacity(0.9)) }
                    if let error = workflow.errorCode { Text("Error code: \(error)").font(.caption).foregroundStyle(.orange.opacity(0.9)) }
                    Text("Updated \(workflow.updatedAt.formatted(date: .abbreviated, time: .shortened)) · idempotency \(workflow.idempotencyKey)").font(.caption2).foregroundStyle(.white.opacity(0.38))
                }
            }
            Text("RETRIES").font(.caption.bold()).tracking(1.3).foregroundStyle(DashboardPalette.accent).padding(.top, 6)
            if value.retries.isEmpty { empty("No retries are scheduled or retained in this projection.") }
            ForEach(value.retries) { retry in
                card("Attempt \(retry.attemptNumber) · \(retry.workflowID)", icon: "arrow.clockwise") {
                    HStack { statusPill(retry.state); Text(retry.reasonCode).font(.caption).foregroundStyle(.white.opacity(0.58)); Spacer(); Text("Backoff \(retry.backoffSeconds)s").font(.caption).foregroundStyle(.white.opacity(0.45)) }
                    Text("Scheduled \(retry.scheduledAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.38))
                }
            }
            Text("DEAD LETTERS").font(.caption.bold()).tracking(1.3).foregroundStyle(.orange).padding(.top, 6)
            if value.deadLetters.isEmpty { empty("No dead letters are retained in this projection.") }
            ForEach(value.deadLetters) { item in
                card(item.deadLetterID, icon: "tray.full.fill") {
                    HStack { statusPill(item.replayEligibility); Text("\(item.attemptCount) attempts · \(item.reasonCode)").font(.caption).foregroundStyle(.white.opacity(0.58)) }
                    Text("Recovery: \(item.recoveryInstructionID) · created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private func commitments(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("COMMITMENTS").font(.caption.bold()).tracking(1.3).foregroundStyle(DashboardPalette.accent)
            if value.commitments.isEmpty { empty("No privacy-reduced commitments are projected.") }
            ForEach(value.commitments) { item in
                card(item.title, icon: "person.crop.circle.badge.checkmark") {
                    HStack { statusPill(item.state); statusPill(item.evidenceStatus); Spacer(); Text(item.commitmentID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.38)) }
                    Text("Owner: \(item.ownerLabel) · Consequence: \(item.consequence)").foregroundStyle(.white.opacity(0.7))
                    if let due = item.dueAt { Text("Due \(due.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.orange) }
                }
            }
            Text("DECISIONS").font(.caption.bold()).tracking(1.3).foregroundStyle(DashboardPalette.accent).padding(.top, 6)
            if value.decisions.isEmpty { empty("No privacy-reduced decisions are projected.") }
            ForEach(value.decisions) { item in
                card(item.title, icon: "signpost.right.and.left.fill") {
                    HStack { statusPill(item.state); statusPill(item.evidenceStatus); Spacer(); Text(item.decisionID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.38)) }
                    Text("Owner: \(item.ownerLabel)").foregroundStyle(.white.opacity(0.7))
                    if let decided = item.decidedAt { Text("Decided \(decided.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.white.opacity(0.48)) }
                }
            }
        }
    }

    private func sources(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if value.sources.isEmpty { empty("No source-health records are projected. Coverage is unknown.") }
            ForEach(value.sources) { source in
                card(source.sourceID, icon: "externaldrive.connected.to.line.below") {
                    HStack { statusPill(source.status); statusPill(source.freshness); Spacer(); Text(source.scopeLabel).font(.caption).foregroundStyle(.white.opacity(0.48)) }
                    Text("Found \(source.itemCount) · processed \(source.processedCount) · unresolved \(source.unresolvedCount)").foregroundStyle(.white.opacity(0.72))
                    if let attempted = source.attemptedAt { Text("Attempted \(attempted.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.4)) }
                    if let succeeded = source.succeededAt { Text("Last success \(succeeded.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.4)) }
                    if let error = source.errorCode { Text("Error code: \(error)").font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }

    private func connections(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            card("Authentication is not coverage", icon: "checkmark.shield") {
                Text("Connected proves a route and authentication state only. Content coverage is reported independently.").foregroundStyle(.white.opacity(0.7))
            }
            if value.connections.isEmpty { empty("No connection diagnostics are projected.") }
            ForEach(value.connections) { connection in
                card(connection.sourceID, icon: "network") {
                    HStack { statusPill(connection.status); statusPill(connection.authenticationState); statusPill(connection.coverageState); Spacer(); Text(connection.connectionID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.38)) }
                    Text("Checked \(connection.lastCheckedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.white.opacity(0.5))
                    ForEach(connection.diagnosticCodes, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }

    private func actions(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if value.externalActions.isEmpty { empty("No governed external actions are projected.") }
            ForEach(value.externalActions) { action in
                card(action.kind.replacingOccurrences(of: "-", with: " ").capitalized, icon: "arrow.up.right.square.fill") {
                    HStack { statusPill(action.state); statusPill(action.readbackStatus); Spacer(); Text(action.actionID).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.38)) }
                    Text("Target: \(action.targetLabel)").foregroundStyle(.white.opacity(0.72))
                    Text(action.confirmationRequired ? "Confirmation required before attempt" : "No additional confirmation required by this record").font(.caption).foregroundStyle(action.confirmationRequired ? .orange : .green)
                    Text(action.retrySafe ? "A controlled retry is permitted." : "Do not retry automatically.").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func compatibility(_ value: RuntimeOperationsProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Compatibility", icon: "arrow.triangle.2.circlepath") {
                HStack { statusPill(value.compatibility.status); Text("Projection schema \(value.compatibility.projectionSchemaVersion)").foregroundStyle(.white.opacity(0.7)) }
                Text("Supported app range: \(value.compatibility.minimumAppVersion) through \(value.compatibility.maximumAppVersion ?? "current and later")").font(.caption).foregroundStyle(.white.opacity(0.52))
                ForEach(value.compatibility.issueCodes, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) }
            }
            Text("MIGRATIONS").font(.caption.bold()).tracking(1.3).foregroundStyle(DashboardPalette.accent)
            if value.migrations.isEmpty { empty("No runtime migrations are recorded.") }
            ForEach(value.migrations) { migration in
                card(migration.migrationID, icon: "square.3.layers.3d.down.right") {
                    HStack { statusPill(migration.state); Text("\(migration.fromVersion) → \(migration.toVersion)").font(.caption).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(migration.reversible ? "reversible" : "not reversible").font(.caption).foregroundStyle(migration.reversible ? .green : .orange) }
                    Text(migration.safeSummary).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func recovery(_ value: RuntimeOperationsProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("ALERTS").font(.caption.bold()).tracking(1.3).foregroundStyle(.orange)
            if value.alerts.isEmpty { empty("No operational alerts are projected.") }
            ForEach(value.alerts) { alert in
                card(alert.title, icon: alert.severity == "critical" ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill") {
                    HStack { statusPill(alert.severity); statusPill(alert.state); Text(alert.category).font(.caption).foregroundStyle(.white.opacity(0.48)) }
                    Text(alert.safeSummary).foregroundStyle(.white.opacity(0.72))
                    if !alert.recoveryInstructionIDs.isEmpty { Text("Recovery: \(alert.recoveryInstructionIDs.joined(separator: ", "))").font(.caption).foregroundStyle(DashboardPalette.accent) }
                }
            }
            Text("RECOVERY INSTRUCTIONS").font(.caption.bold()).tracking(1.3).foregroundStyle(DashboardPalette.accent).padding(.top, 6)
            if value.recoveryInstructions.isEmpty { empty("No recovery instructions are required.") }
            ForEach(value.recoveryInstructions) { instruction in
                card(instruction.title, icon: "lifepreserver.fill") {
                    statusPill(instruction.actionBoundary)
                    ForEach(Array(instruction.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)").foregroundStyle(.white.opacity(0.72))
                    }
                    if instruction.actionBoundary == "requires-confirmation" { Text("Stop before the consequential step and obtain confirmation.").font(.caption.bold()).foregroundStyle(.orange) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2").font(.system(size: 38)).foregroundStyle(.white.opacity(0.35))
            Text("UPGRADE REQUIRED")
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2)
                .foregroundStyle(.orange)
            Text("Runtime operations are not available yet").font(.title3.bold()).foregroundStyle(.white)
            Text(errorMessage ?? "Update the MONDAY plugin/runtime so it can publish the Priority 3 privacy-reduced projection. Planner and Digital Twin remain available while this room waits for a compatible projection.")
                .foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center).frame(maxWidth: 660)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func empty(_ text: String) -> some View { Text(text).foregroundStyle(.white.opacity(0.5)).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }

    private func diagnostic(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(.white.opacity(0.55))
            Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.075)))
    }

    private func statusPill(_ status: String) -> some View {
        Text(status.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(status.localizedCaseInsensitiveContains("fail") || status.localizedCaseInsensitiveContains("blocked") || status.localizedCaseInsensitiveContains("critical") ? .orange : DashboardPalette.accent)
    }

    @MainActor private func refresh() async {
        do {
            let candidate = try RuntimeOperationsReader.load()
            let validation = candidate.validation(appVersion: appVersion)
            guard validation == .current else { throw RuntimeOperationsViewError.invalidProjection(validation) }
            projection = candidate
            lastValidProjection = candidate
            errorMessage = nil
            if let readback = candidate.readback(viewID: section.viewID, consumer: "MONDAY Command Center", appVersion: appVersion) {
                try RuntimeOperationsReadbackWriter.write(readback)
            }
        } catch {
            projection = nil
            if !FileManager.default.fileExists(atPath: RuntimeOperationsReader.defaultURL.path) {
                errorMessage = "The installed MONDAY plugin has not published its Priority 3 runtime projection. Update MONDAY, then refresh. Planner and Digital Twin continue to work."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor private func writeReadbackForVisibleSection() async {
        guard let projection,
              let readback = projection.readback(viewID: section.viewID, consumer: "MONDAY Command Center", appVersion: appVersion) else { return }
        do { try RuntimeOperationsReadbackWriter.write(readback) }
        catch { errorMessage = error.localizedDescription }
    }

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown" }
}

private struct RuntimeTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? DashboardPalette.accent.opacity(0.19) : Color.white.opacity(configuration.isPressed ? 0.09 : 0.05), in: Capsule())
            .foregroundStyle(selected ? DashboardPalette.accent : .white.opacity(0.68))
    }
}

private enum RuntimeOperationsViewError: LocalizedError {
    case invalidProjection(RuntimeProjectionValidation)
    var errorDescription: String? {
        switch self { case .invalidProjection(let validation): "Runtime operations projection rejected: \(String(describing: validation))" }
    }
}
