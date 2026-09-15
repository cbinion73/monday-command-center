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
        let note_path: String?
        var id: String { meeting_key }
    }
    struct ProjectCoverage: Decodable, Identifiable {
        let project: String
        let meeting_count: Int
        let pending: Int
        let blocked: Int
        let updated: Int
        var id: String { project }
    }
    struct ProjectLinkAccounting: Decodable {
        let meetings_with_project_link: Int
        let meetings_without_project_link: Int
        let project_link_count: Int
    }
    let generated_at: Date
    let run_id: String
    let coverage: Coverage
    let lifecycle_states: [String: Int]
    let routing_dispositions: [String: Int]
    let backlog: [BacklogItem]
    let project_coverage: [ProjectCoverage]
    let project_link_accounting: ProjectLinkAccounting?
}

@MainActor
private final class ContinuityFeed: ObservableObject {
    @Published var summary: ContinuitySummary?
    @Published var message = "Reading the Meeting Continuity reconciliation…"

    func refresh() {
        guard let url = CommandCenterPairing.shared.continuityFeedURL,
              FileManager.default.fileExists(atPath: url.path) else {
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
    @StateObject private var noteIndex = MeetingNoteIndex()
    @State private var selectedNote: MeetingNote?
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private var todayKey: String { Self.dateFormatter.string(from: .now) }

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
                    ContinuityPanel(title: "TODAY'S MEETING NOTES", detail: "Governed notes for \(todayKey). Each meeting keeps its own dated note and can also route supported impact into an existing project.") {
                        let todayNotes = noteIndex.notes(for: todayKey)
                        if todayNotes.isEmpty {
                            Text("No governed meeting notes have been recorded for today.").foregroundStyle(.white.opacity(0.68))
                        } else {
                            ForEach(todayNotes) { note in
                                Button { selectedNote = note } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "doc.text.fill").foregroundStyle(DashboardPalette.accent)
                                        Text(note.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.42))
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let summary = feed.summary {
                        Text("RECONCILIATION LEDGER · ALL GOVERNED NOTES")
                            .font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.48))
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
                        ContinuityPanel(title: "PROJECT LINKS", detail: projectLinkDetail(summary)) {
                            if let accounting = summary.project_link_accounting {
                                HStack(spacing: 14) {
                                    ContinuityRouteMetric(value: accounting.meetings_with_project_link, label: "WITH PROJECT LINK", color: DashboardPalette.accent)
                                    ContinuityRouteMetric(value: accounting.meetings_without_project_link, label: "NO PROJECT LINK", color: .white.opacity(0.68))
                                }
                            }
                            if summary.project_coverage.isEmpty {
                                Text("No existing project routes were recorded in this window.").foregroundStyle(.white.opacity(0.68))
                            } else {
                                ForEach(summary.project_coverage.prefix(20)) { item in
                                    HStack {
                                        Text(item.project).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                        Spacer()
                                        Text("\(item.meeting_count) meetings").foregroundStyle(.white.opacity(0.62))
                                        if item.pending > 0 { Text("\(item.pending) pending").foregroundStyle(DashboardPalette.amber) }
                                        if item.blocked > 0 { Text("\(item.blocked) blocked").foregroundStyle(DashboardPalette.red) }
                                        if item.updated > 0 { Text("\(item.updated) updated").foregroundStyle(DashboardPalette.green) }
                                    }
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                        ContinuityPanel(title: "REVIEW BACKLOG", detail: "\(summary.backlog.count) occurrence\(summary.backlog.count == 1 ? "" : "s") require review, project routing, or source recovery.") {
                            if summary.backlog.isEmpty {
                                Text("No unresolved occurrences in this reconciliation window.").foregroundStyle(.white.opacity(0.68))
                            } else {
                                ForEach(summary.backlog.prefix(40)) { item in
                                    Button { selectedNote = note(for: item) } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(item.date).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55)).frame(width: 78, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                                Text(item.blocked_reasons.isEmpty ? item.disposition.replacingOccurrences(of: "_", with: " ") : item.blocked_reasons.joined(separator: " · "))
                                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(DashboardPalette.amber)
                                            }
                                            Spacer()
                                            Image(systemName: item.note_path == nil ? "doc.badge.questionmark" : "doc.text.fill").foregroundStyle(DashboardPalette.accent)
                                        }
                                        .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)
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
        .task {
            while !Task.isCancelled {
                feed.refresh()
                noteIndex.reload()
                do { try await Task.sleep(for: .seconds(1800)) }
                catch { return }
            }
        }
        .sheet(item: $selectedNote) { MeetingNoteSheet(note: $0) }
    }

    private func note(for item: ContinuitySummary.BacklogItem) -> MeetingNote? {
        guard let path = item.note_path else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return MeetingNote(id: item.meeting_key, date: item.date, title: item.title, url: url, contents: contents)
    }

    private func projectLinkDetail(_ summary: ContinuitySummary) -> String {
        guard let accounting = summary.project_link_accounting else {
            return "Meeting coverage grouped by the existing project routes recorded in governed notes."
        }
        return "\(accounting.meetings_with_project_link) meetings have at least one recorded project link and \(accounting.meetings_without_project_link) have none. These counts add to \(summary.coverage.meetings_in_scope). Individual project rows are links, so they can overlap."
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

private struct ContinuityRouteMetric: View {
    let value: Int; let label: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
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
