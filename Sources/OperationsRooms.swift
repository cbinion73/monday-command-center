import Foundation
import SwiftUI

struct GovernedRecordLibraryRoom: View {
    let title: String
    let subtitle: String
    let rootURL: URL?
    let emptyMessage: String

    @State private var records: [GovernedRecord] = []
    @State private var selected: GovernedRecord?
    @State private var message = "Reading governed records…"

    var body: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            HSplitView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(DashboardPalette.accent)
                        Text(subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if records.isEmpty {
                        ContentUnavailableView(title, systemImage: "tray", description: Text(message))
                            .foregroundStyle(.white)
                    } else {
                        List(records, selection: $selected) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).font(.system(size: 13, weight: .semibold))
                                Text(record.modified.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .tag(record)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(26)
                .frame(minWidth: 330, idealWidth: 390)

                ScrollView {
                    if let selected {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(selected.title)
                                .font(.system(size: 27, weight: .semibold, design: .serif))
                                .foregroundStyle(.white)
                            Text(selected.relativePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                                .textSelection(.enabled)
                            Divider().overlay(.white.opacity(0.12))
                            Text(selected.contents)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(34)
                    } else {
                        ContentUnavailableView("Choose a record", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 500)
                    }
                }
                .frame(minWidth: 520)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: rootURL) { reload() }
    }

    private func reload() {
        guard let rootURL else {
            records = []
            selected = nil
            message = emptyMessage
            return
        }
        let governedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            records = []
            selected = nil
            message = "The configured folder could not be read."
            return
        }
        let allowed = Set(["md", "json", "jsonl", "txt"])
        var loaded: [GovernedRecord] = []
        for case let url as URL in enumerator {
            guard let resolved = GovernedPath.containedFile(url, within: governedRoot),
                  allowed.contains(resolved.pathExtension.lowercased()),
                  let values = try? resolved.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 524_288,
                  let contents = try? String(contentsOf: resolved, encoding: .utf8) else { continue }
            loaded.append(GovernedRecord(
                url: resolved,
                relativePath: String(resolved.path.dropFirst(governedRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                title: resolved.deletingPathExtension().lastPathComponent,
                modified: values.contentModificationDate ?? .distantPast,
                contents: Self.privacyReduced(contents)
            ))
        }
        records = loaded.sorted { lhs, rhs in
            lhs.modified == rhs.modified ? lhs.title < rhs.title : lhs.modified > rhs.modified
        }
        if let selected, records.contains(selected) {
            self.selected = records.first { $0 == selected }
        } else {
            selected = records.first
        }
        message = records.isEmpty ? emptyMessage : ""
    }

    private static func privacyReduced(_ value: String) -> String {
        var result = value
        let replacements: [(String, String)] = [
            (#"(?i)\b(?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*[^\s,;]+"#, "[REDACTED CREDENTIAL]"),
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "[REDACTED CREDENTIAL]"),
            (#"(?i)\b(?:https?|file)://\S+"#, "[REDACTED LINK]"),
            (#"(?<![A-Za-z0-9])/(?:Users|Volumes|private|var|tmp|home|etc)/[^\s\]\[)}`'\"]+"#, "[REDACTED PATH]")
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }
}

private struct GovernedRecord: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let relativePath: String
    let title: String
    let modified: Date
    let contents: String

    static func == (lhs: GovernedRecord, rhs: GovernedRecord) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
