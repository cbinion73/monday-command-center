import Foundation
import SwiftUI

private struct ContinuitySummary: Decodable {
    struct Coverage: Decodable {
        let meetings_in_scope: Int
        let reconciled: Int
        let blocked: Int
        let pending: Int
        let complete: Bool
    }
    struct BacklogItem: Decodable, Identifiable {
        let meeting_key: String
        let date: String
        let title: String
        let disposition: String
        let blocked_reasons: [String]
        var id: String { meeting_key }
    }
    let generated_at: Date
    let run_id: String
    let coverage: Coverage
    let lifecycle_states: [String: Int]
    let routing_dispositions: [String: Int]
    let backlog: [BacklogItem]
}

@MainActor
private final class ContinuityFeed: ObservableObject {
    @Published var summary: ContinuitySummary?
    @Published var message = "Reading the Meeting Continuity reconciliation…"

    func refresh() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/monday-meeting-continuity/summary.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            summary = nil
            message = "No reconciliation summary is available yet. Run the MONDAY Meeting Continuity reconciliation in Codex, then return here."
            return
        }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            summary = try decoder.decode(ContinuitySummary.self, from: Data(contentsOf: url))
            message = ""
        } catch {
            summary = nil
            message = "The Meeting Continuity summary could not be read: \(error.localizedDescription)"
        }
    }
}

struct MeetingContinuityRoom: View {
    @StateObject private var feed = ContinuityFeed()

    var body: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MEETING CONTINUITY").font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.5).foregroundStyle(DashboardPalette.accent)
                        Text("Coverage must be earned.").font(.system(size: 31, weight: .semibold, design: .serif)).foregroundStyle(.white)
                        Text("Every completed meeting is either reconciled, explicitly blocked, or explicitly pending. Nothing disappears because a source was inconvenient.")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let summary = feed.summary {
                        HStack(spacing: 12) {
                            ContinuityMetric(value: summary.coverage.meetings_in_scope, label: "IN SCOPE", color: DashboardPalette.accent)
                            ContinuityMetric(value: summary.coverage.reconciled, label: "RECONCILED", color: DashboardPalette.green)
                            ContinuityMetric(value: summary.coverage.pending, label: "PENDING", color: DashboardPalette.amber)
                            ContinuityMetric(value: summary.coverage.blocked, label: "BLOCKED", color: DashboardPalette.red)
                        }
                        .frame(maxWidth: .infinity)
                        ContinuityPanel(title: summary.coverage.complete ? "RECONCILIATION VERIFIED" : "RECONCILIATION OPEN", detail: summary.coverage.complete ? "Every scoped occurrence has passed the continuity gate." : "The denominator is visible, but this window is not complete. The backlog below is the work MONDAY still owes you.") {
                            HStack(spacing: 14) {
                                ContinuityCounts(title: "LIFECYCLE", values: summary.lifecycle_states)
                                ContinuityCounts(title: "ROUTING", values: summary.routing_dispositions)
                            }
                        }
                        ContinuityPanel(title: "REVIEW BACKLOG", detail: "\(summary.backlog.count) occurrence\(summary.backlog.count == 1 ? "" : "s") require review, project routing, or source recovery.") {
                            if summary.backlog.isEmpty {
                                Text("No unresolved occurrences in this reconciliation window.").foregroundStyle(.white.opacity(0.68))
                            } else {
                                ForEach(summary.backlog.prefix(40)) { item in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(item.date).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55)).frame(width: 78, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                            Text(item.blocked_reasons.isEmpty ? item.disposition.replacingOccurrences(of: "_", with: " ") : item.blocked_reasons.joined(separator: " · "))
                                                .font(.system(size: 11, weight: .medium)).foregroundStyle(DashboardPalette.amber)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 7)
                                    Divider().overlay(.white.opacity(0.1))
                                }
                            }
                        }
                        Text("Last reconciliation: \(summary.generated_at.formatted(date: .abbreviated, time: .shortened)) · Run \(summary.run_id)")
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
                    } else {
                        ContinuityPanel(title: "AWAITING RECONCILIATION", detail: feed.message) { EmptyView() }
                    }
                }
                .padding(42).frame(maxWidth: 1160, alignment: .leading)
            }
        }
        .task { feed.refresh() }
    }
}

private struct ContinuityMetric: View {
    let value: Int; let label: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 10, weight: .black, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ContinuityPanel<Content: View>: View {
    let title: String; let detail: String; @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.2).foregroundStyle(DashboardPalette.accent)
            Text(detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(22).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ContinuityCounts: View {
    let title: String; let values: [String: Int]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .black, design: .rounded)).tracking(1).foregroundStyle(.white.opacity(0.48))
            ForEach(values.keys.sorted(), id: \.self) { key in
                HStack { Text(key.replacingOccurrences(of: "_", with: " ").uppercased()); Spacer(); Text("\(values[key] ?? 0)") }
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
