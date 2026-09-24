import SwiftUI

struct TwinInspectionRoom: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case promises = "Promises"
        case claims = "Claims & Evidence"
        case authority = "Authority & Boundaries"
        case privacy = "Privacy & Lifecycle"
        case playbooks = "Playbooks"
        var id: String { rawValue }
    }

    @State private var projection: TwinInspectionProjection?
    @State private var lastValidProjection: TwinInspectionProjection?
    @State private var section: Section = .overview
    @State private var errorMessage: String?
    @State private var refreshedAt: Date?

    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.027, blue: 0.045).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                header
                sectionPicker
                if let projection {
                    content(projection)
                } else if let lastValidProjection {
                    staleBanner
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
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("GOVERNED DIGITAL TWIN", systemImage: "person.text.rectangle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 0.35, green: 0.82, blue: 0.95))
                Text("What MONDAY believes, and why")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Professional and personal records remain separate. This room is read-only and shows only the privacy-reduced projection.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
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
                        .buttonStyle(TwinTabStyle(selected: section == item))
                }
            }
        }
    }

    @ViewBuilder private func content(_ projection: TwinInspectionProjection) -> some View {
        ScrollView {
            switch section {
            case .overview: overview(projection)
            case .promises: promises(projection)
            case .claims: claims(projection)
            case .authority: authority(projection)
            case .privacy: privacy(projection)
            case .playbooks: playbooks(projection)
            }
        }
    }

    private func overview(_ value: TwinInspectionProjection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage { diagnostic(errorMessage) }
            HStack(spacing: 14) {
                metric("Professional", value.coverage.professionalCount, "briefcase.fill")
                metric("Personal", value.coverage.personalCount, "lock.fill")
                metric("Promises", value.coverage.promiseCount, "checklist")
                metric("Open controls", value.coverage.unresolvedCount, "exclamationmark.shield.fill")
            }
            card("Contract audit", icon: "checkmark.shield.fill") {
                HStack {
                    statusPill(value.contractAudit.status)
                    Text("\(value.contractAudit.implementedPromiseCount) of \(value.contractAudit.promiseCount) promises implemented")
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("Projection \(value.projectionID)").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.42))
                }
                if !value.contractAudit.errors.isEmpty {
                    ForEach(value.contractAudit.errors, id: \.self) { Text("• \($0)").foregroundStyle(.orange) }
                }
            }
            card("Boundary posture", icon: "lock.shield.fill") {
                Text("Personal statements are omitted from this projection. Source locators, raw communications, credentials, forgotten content, and hidden reasoning are not accepted by the contract.")
                    .foregroundStyle(.white.opacity(0.72))
                Text("Valid until \(value.validUntil.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func promises(_ value: TwinInspectionProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(value.promises) { promise in
                card(promise.id, icon: "checklist") {
                    Text(promise.promise).foregroundStyle(.white.opacity(0.9))
                    HStack { statusPill(promise.status); Text("Owner: \(promise.owner) · Control: \(promise.control)").font(.caption).foregroundStyle(.white.opacity(0.5)) }
                }
            }
        }
    }

    private func claims(_ value: TwinInspectionProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            domainSection("Professional Twin", domain: "professional", records: value.records)
            domainSection("Personal Twin", domain: "personal", records: value.records)
        }
    }

    private func domainSection(_ title: String, domain: String, records: [TwinInspectionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.bold()).tracking(1.3).foregroundStyle(domain == "personal" ? .purple : .cyan)
            let filtered = records.filter { $0.domain == domain }
            if filtered.isEmpty {
                Text("No projected \(domain) Twin records.").foregroundStyle(.white.opacity(0.5)).padding(.vertical, 12)
            }
            ForEach(filtered) { record in
                card(record.recordType.replacingOccurrences(of: "-", with: " ").capitalized, icon: domain == "personal" ? "lock.fill" : "briefcase.fill") {
                    if let statement = record.statement { Text(statement).foregroundStyle(.white.opacity(0.9)) }
                    else { Text("Private statement withheld. Purpose: \(record.purpose)").foregroundStyle(.white.opacity(0.66)) }
                    HStack(spacing: 8) {
                        statusPill(record.status)
                        statusPill(record.evidenceClass)
                        Text("Confidence \(Int(record.confidence * 100))%")
                        Text("\(record.evidenceCount) evidence reference\(record.evidenceCount == 1 ? "" : "s")")
                        if record.contradictionCount > 0 { Text("\(record.contradictionCount) contradiction\(record.contradictionCount == 1 ? "" : "s")").foregroundStyle(.orange) }
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                    Text("Sources: \(record.sourceIDs.joined(separator: ", ")) · Review \(record.reviewAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.white.opacity(0.42))
                }
            }
        }
    }

    private func authority(_ value: TwinInspectionProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("SOURCES").font(.caption.bold()).tracking(1.3).foregroundStyle(.cyan)
            ForEach(value.authoritySources) { source in
                card(source.id, icon: "arrow.triangle.branch") {
                    Text("\(source.role) · \(source.domain) · owner \(source.owner)").foregroundStyle(.white.opacity(0.72))
                    Text("Suitable for: \(source.suitableFor.joined(separator: ", "))").font(.caption).foregroundStyle(.green.opacity(0.8))
                    Text("Not proof of: \(source.notProofOf.joined(separator: ", "))").font(.caption).foregroundStyle(.orange.opacity(0.9))
                    Text("Conflict rule: \(source.conflictRule)").font(.caption).foregroundStyle(.white.opacity(0.45))
                }
            }
            Text("RECORD BOUNDARIES").font(.caption.bold()).tracking(1.3).foregroundStyle(.cyan).padding(.top, 8)
            ForEach(value.authorityRecords) { record in
                card(record.id, icon: "square.3.layers.3d") {
                    Text("\(record.domain) · owner \(record.owner) · audience \(record.audience)").foregroundStyle(.white.opacity(0.72))
                    Text("Allowed out: \(record.allowedEgress.joined(separator: ", "))").font(.caption).foregroundStyle(.green.opacity(0.8))
                    Text("Prohibited out: \(record.prohibitedEgress.joined(separator: ", "))").font(.caption).foregroundStyle(.red.opacity(0.8))
                }
            }
        }
    }

    private func privacy(_ value: TwinInspectionProjection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card("Learning controls", icon: "hand.raised.fill") {
                Text(value.optOuts.global ? "All durable Twin learning is opted out." : "Global Twin learning is enabled.")
                    .foregroundStyle(value.optOuts.global ? .orange : .green)
                Text("Domains: \(value.optOuts.domains.isEmpty ? "none" : value.optOuts.domains.joined(separator: ", "))")
                Text("Sources: \(value.optOuts.sources.isEmpty ? "none" : value.optOuts.sources.joined(separator: ", "))")
                Text("Record types: \(value.optOuts.recordTypes.isEmpty ? "none" : value.optOuts.recordTypes.joined(separator: ", "))")
            }
            Text("RECENT LIFECYCLE EVENTS").font(.caption.bold()).tracking(1.3).foregroundStyle(.cyan)
            ForEach(value.governanceEvents.reversed()) { event in
                card(event.action.replacingOccurrences(of: "-", with: " ").capitalized, icon: "clock.arrow.circlepath") {
                    Text("\(event.domain) · \(event.recordID) · \(event.result)").foregroundStyle(.white.opacity(0.72))
                    Text(event.reason).font(.caption).foregroundStyle(.white.opacity(0.55))
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.white.opacity(0.38))
                }
            }
        }
    }

    private func playbooks(_ value: TwinInspectionProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if value.playbooks.isEmpty { Text("No redacted playbook packages have been prepared.").foregroundStyle(.white.opacity(0.5)).padding(.vertical, 20) }
            ForEach(value.playbooks) { playbook in
                card(playbook.title ?? playbook.playbookID ?? "Playbook", icon: "doc.badge.gearshape") {
                    HStack { statusPill(playbook.state ?? "unknown"); statusPill(playbook.qaVerdict ?? "unknown") }
                    Text("Audience: \(playbook.audience ?? "unknown")").font(.caption).foregroundStyle(.white.opacity(0.55))
                    if let digest = playbook.packageDigest { Text("Package \(digest.prefix(12))").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.4)) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.text.rectangle").font(.system(size: 38)).foregroundStyle(.white.opacity(0.35))
            Text("No valid Digital Twin inspection projection is available").font(.title3.bold()).foregroundStyle(.white)
            Text(errorMessage ?? "Run the MONDAY Digital Twin projection workflow. Missing information remains unknown, not empty.")
                .foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center).frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var staleBanner: some View { diagnostic("The latest projection was rejected. The last valid projection remains visible and is explicitly stale.") }

    private func diagnostic(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout).foregroundStyle(.orange)
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
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
            .foregroundStyle(status.localizedCaseInsensitiveContains("fail") || status.localizedCaseInsensitiveContains("blocked") ? .orange : .cyan)
    }

    @MainActor private func refresh() async {
        do {
            let candidate = try TwinInspectionReader.load()
            guard candidate.validation() == .current else {
                throw TwinInspectionViewError.invalidProjection(candidate.validation())
            }
            projection = candidate
            lastValidProjection = candidate
            errorMessage = nil
            refreshedAt = .now
            if let readback = candidate.readback(consumer: "MONDAY Command Center", appVersion: appVersion) {
                try TwinInspectionReadbackWriter.write(readback)
            }
        } catch {
            projection = nil
            errorMessage = error.localizedDescription
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}

private struct TwinTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Color.cyan.opacity(0.19) : Color.white.opacity(configuration.isPressed ? 0.09 : 0.05), in: Capsule())
            .foregroundStyle(selected ? .cyan : .white.opacity(0.68))
    }
}

private enum TwinInspectionViewError: LocalizedError {
    case invalidProjection(TwinProjectionValidation)
    var errorDescription: String? {
        switch self {
        case .invalidProjection(let validation): "Digital Twin projection rejected: \(String(describing: validation))"
        }
    }
}
