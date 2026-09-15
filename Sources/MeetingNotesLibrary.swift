import Foundation
import SwiftUI

struct MeetingNote: Identifiable {
    let id: String
    let date: String
    let title: String
    let url: URL
    let contents: String
}

@MainActor
final class MeetingNoteIndex: ObservableObject {
    @Published private(set) var notes: [MeetingNote] = []

    func reload() {
        guard let root = CommandCenterPairing.shared.meetingNotesURL,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            notes = []
            return
        }
        notes = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let metadata = Self.frontmatter(text)
            guard let date = metadata["meeting_date"], let title = metadata["meeting_title"], !date.isEmpty, !title.isEmpty else { return nil }
            return MeetingNote(id: metadata["stable_meeting_key"] ?? url.path, date: date, title: title, url: url, contents: text)
        }.sorted { ($0.date, $0.title) > ($1.date, $1.title) }
    }

    func note(for date: String, title: String) -> MeetingNote? {
        let candidates = notes.filter { $0.date == date }
        let normalizedTitle = Self.normalized(title)
        return candidates.first { Self.normalized($0.title) == normalizedTitle }
            ?? candidates.first { Self.normalized($0.title).contains(normalizedTitle) || normalizedTitle.contains(Self.normalized($0.title)) }
            ?? candidates.max { Self.sharedTerms($0.title, title) < Self.sharedTerms($1.title, title) }.flatMap { Self.sharedTerms($0.title, title) >= 2 ? $0 : nil }
    }

    func notes(for date: String) -> [MeetingNote] {
        notes.filter { $0.date == date }
    }

    private static func frontmatter(_ text: String) -> [String: String] {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { return [:] }
        return text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n").reduce(into: [:]) { result, line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    private static func normalized(_ value: String) -> String { value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined() }
    private static func sharedTerms(_ lhs: String, _ rhs: String) -> Int {
        let left = Set(lhs.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 })
        let right = Set(rhs.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 2 })
        return left.intersection(right).count
    }
}

struct MeetingNoteSheet: View {
    let note: MeetingNote
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MeetingNoteMarkdown(source: note.contents)
                    .padding(28)
            }
            .navigationTitle(note.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 760, minHeight: 620)
    }
}

private struct MeetingNoteMarkdown: View {
    private struct Block: Identifiable {
        enum Kind { case heading(Int), paragraph, quote, bullet, table(headers: [String], rows: [[String]]), rule }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    let source: String
    private var blocks: [Block] { Self.parse(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    MeetingNoteInline(block.text)
                        .font(.system(size: level == 1 ? 28 : level == 2 ? 21 : 17, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .padding(.top, level == 1 ? 0 : 10)
                case .paragraph:
                    MeetingNoteInline(block.text)
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                case .quote:
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(.tint).frame(width: 3)
                        MeetingNoteInline(block.text)
                            .font(.system(size: 16, design: .serif)).italic().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.tint)
                        MeetingNoteInline(block.text).font(.system(size: 16, design: .serif)).foregroundStyle(.primary)
                    }
                case .table(let headers, let rows):
                    MeetingNoteTable(headers: headers, rows: rows)
                case .rule:
                    Divider().padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func parse(_ source: String) -> [Block] {
        let lines = withoutFrontmatter(source).components(separatedBy: .newlines)
        var result: [Block] = []
        var index = 0

        func heading(_ line: String) -> (Int, String)? {
            let level = line.prefix(while: { $0 == "#" }).count
            guard level > 0, line.dropFirst(level).first == " " else { return nil }
            return (level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
        }
        func isTableDivider(_ line: String) -> Bool {
            let cells = cells(in: line)
            return !cells.isEmpty && cells.allSatisfy { $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }
        }
        func startsBlock(_ line: String) -> Bool {
            heading(line) != nil || line == "---" || line.hasPrefix(">") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("|")
        }

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            if let (level, text) = heading(line) {
                result.append(Block(kind: .heading(level), text: text)); index += 1
            } else if line == "---" {
                result.append(Block(kind: .rule, text: "")); index += 1
            } else if line.hasPrefix("|") && index + 1 < lines.count && isTableDivider(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                let headers = cells(in: line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") else { break }
                    let values = cells(in: row)
                    guard values.count == headers.count else { break }
                    rows.append(values); index += 1
                }
                result.append(Block(kind: .table(headers: headers, rows: rows), text: ""))
            } else if line.hasPrefix(">") {
                result.append(Block(kind: .quote, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); index += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                result.append(Block(kind: .bullet, text: String(line.dropFirst(2)))); index += 1
            } else {
                var paragraph = [line]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty || startsBlock(next) { break }
                    paragraph.append(next); index += 1
                }
                result.append(Block(kind: .paragraph, text: paragraph.joined(separator: " ")))
            }
        }
        return result
    }

    private static func withoutFrontmatter(_ source: String) -> String {
        guard source.hasPrefix("---\n"), let range = source.range(of: "\n---", range: source.index(source.startIndex, offsetBy: 4)..<source.endIndex) else { return source }
        var after = range.upperBound
        if after < source.endIndex, source[after] == "\n" {
            after = source.index(after, offsetBy: 1)
        }
        return String(source[after...])
    }

    private static func cells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

private struct MeetingNoteTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(headers.indices, id: \.self) { column in
                    MeetingNoteInline(headers[column])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.primary.opacity(0.07))
                }
            }
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(headers.indices, id: \.self) { column in
                        MeetingNoteInline(rows[row][column])
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .background(.primary.opacity(row.isMultiple(of: 2) ? 0.025 : 0.055))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.primary.opacity(0.12), lineWidth: 1))
        .textSelection(.enabled)
    }
}

private struct MeetingNoteInline: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        if let attributed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
        } else {
            Text(source)
        }
    }
}
