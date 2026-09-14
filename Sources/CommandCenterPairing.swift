import AppKit
import Foundation
import SwiftUI

/// User-approved local locations. Command Center reads them but never stores
/// Codex, calendar, or vault credentials.
@MainActor
final class CommandCenterPairing: ObservableObject {
    static let shared = CommandCenterPairing()
    @Published private(set) var pluginURL: URL?
    @Published private(set) var projectVaultURL: URL?
    @Published private(set) var captainsLogURL: URL?
    @Published private(set) var researchJournalURL: URL?
    @Published private(set) var plannerFeedURL: URL?
    @Published private(set) var revision = 0

    private enum Key {
        static let plugin = "pairing.pluginPath"
        static let projectVault = "pairing.projectVaultPath"
        static let captainsLog = "pairing.captainsLogPath"
        static let researchJournal = "pairing.researchJournalPath"
        static let plannerFeed = "pairing.plannerFeedPath"
    }

    private init(defaults: UserDefaults = .standard) {
        pluginURL = defaults.string(forKey: Key.plugin).map { URL(fileURLWithPath: $0, isDirectory: true) }
        projectVaultURL = defaults.string(forKey: Key.projectVault).map { URL(fileURLWithPath: $0, isDirectory: true) }
        captainsLogURL = defaults.string(forKey: Key.captainsLog).map { URL(fileURLWithPath: $0, isDirectory: true) }
        researchJournalURL = defaults.string(forKey: Key.researchJournal).map { URL(fileURLWithPath: $0, isDirectory: true) }
        plannerFeedURL = defaults.string(forKey: Key.plannerFeed).map { URL(fileURLWithPath: $0) } ?? Self.discoveredPlannerFeeds().first
        discardInvalidLocations()
    }

    var isPaired: Bool { pluginURL != nil && projectsDirectoryURL != nil }
    var projectsDirectoryURL: URL? {
        guard let projectVaultURL else { return nil }
        let projects = projectVaultURL.appendingPathComponent("03 Projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: projects.path) ? projects : nil
    }

    @discardableResult
    func discoverAndPairIfPossible() -> Bool {
        guard !isPaired, let suggestion = suggestedPairing else { return isPaired }
        do {
            try pair(pluginURL: suggestion.pluginURL, projectVaultURL: suggestion.projectVaultURL, captainsLogURL: suggestion.captainsLogURL, researchJournalURL: suggestion.researchJournalURL, plannerFeedURL: suggestion.plannerFeedURL)
            return true
        } catch { return false }
    }

    var suggestedPairing: SuggestedPairing? {
        guard let pluginURL = Self.discoveredPlugins().first, let projectVaultURL = Self.discoveredProjectVaults().first else { return nil }
        return SuggestedPairing(pluginURL: pluginURL, projectVaultURL: projectVaultURL, captainsLogURL: Self.discoveredCaptainsLogs().first, researchJournalURL: Self.discoveredResearchJournals().first, plannerFeedURL: Self.discoveredPlannerFeeds().first)
    }

    func pair(pluginURL: URL, projectVaultURL: URL, captainsLogURL: URL?, researchJournalURL: URL?, plannerFeedURL: URL?) throws {
        guard Self.isMondayPlugin(pluginURL) else { throw PairingError.invalidPlugin }
        guard FileManager.default.fileExists(atPath: projectVaultURL.appendingPathComponent("03 Projects", isDirectory: true).path) else { throw PairingError.invalidProjectVault }
        if let captainsLogURL, !FileManager.default.fileExists(atPath: captainsLogURL.path) { throw PairingError.invalidCaptainsLog }
        if let researchJournalURL, !FileManager.default.fileExists(atPath: researchJournalURL.path) { throw PairingError.invalidResearchJournal }
        if let plannerFeedURL, !FileManager.default.fileExists(atPath: plannerFeedURL.path) { throw PairingError.invalidPlannerFeed }
        self.pluginURL = pluginURL.standardizedFileURL
        self.projectVaultURL = projectVaultURL.standardizedFileURL
        self.captainsLogURL = captainsLogURL?.standardizedFileURL
        self.researchJournalURL = researchJournalURL?.standardizedFileURL
        self.plannerFeedURL = plannerFeedURL?.standardizedFileURL
        persist(); revision += 1
    }

    func clear() {
        pluginURL = nil; projectVaultURL = nil; captainsLogURL = nil; researchJournalURL = nil; plannerFeedURL = nil
        [Key.plugin, Key.projectVault, Key.captainsLog, Key.researchJournal, Key.plannerFeed].forEach(UserDefaults.standard.removeObject(forKey:))
        revision += 1
    }

    private func discardInvalidLocations() {
        guard let pluginURL, let projectVaultURL, Self.isMondayPlugin(pluginURL), FileManager.default.fileExists(atPath: projectVaultURL.appendingPathComponent("03 Projects").path) else { clear(); return }
        if let captainsLogURL, !FileManager.default.fileExists(atPath: captainsLogURL.path) { self.captainsLogURL = nil }
        if let researchJournalURL, !FileManager.default.fileExists(atPath: researchJournalURL.path) { self.researchJournalURL = nil }
        if let plannerFeedURL, !FileManager.default.fileExists(atPath: plannerFeedURL.path) { self.plannerFeedURL = nil }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(pluginURL?.path, forKey: Key.plugin)
        UserDefaults.standard.set(projectVaultURL?.path, forKey: Key.projectVault)
        UserDefaults.standard.set(captainsLogURL?.path, forKey: Key.captainsLog)
        UserDefaults.standard.set(researchJournalURL?.path, forKey: Key.researchJournal)
        UserDefaults.standard.set(plannerFeedURL?.path, forKey: Key.plannerFeed)
    }

    private static func isMondayPlugin(_ url: URL) -> Bool {
        let manifest = url.appendingPathComponent(".codex-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = value["name"] as? String else { return false }
        return name == "monday-thermo"
    }

    private static func discoveredPlugins() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent(".codex/plugins/cache", isDirectory: true), home.appendingPathComponent(".codex/plugins", isDirectory: true)]
        var candidates: [URL] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsPackageDescendants]) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if enumerator.level > 7 { enumerator.skipDescendants(); continue }
                guard url.lastPathComponent == "plugin.json", url.deletingLastPathComponent().lastPathComponent == ".codex-plugin" else { continue }
                let pluginURL = url.deletingLastPathComponent().deletingLastPathComponent()
                if isMondayPlugin(pluginURL) { candidates.append(pluginURL) }
            }
        }
        return Array(Set(candidates.map { $0.standardizedFileURL })).sorted { modifiedDate(for: $0) > modifiedDate(for: $1) }
    }

    private static func discoveredProjectVaults() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent("Documents/MONDAY/Project Knowledge", isDirectory: true), home.appendingPathComponent("Knowledge Vault/Project Knowledge", isDirectory: true)]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("03 Projects", isDirectory: true).path) }
    }
    private static func discoveredCaptainsLogs() -> [URL] { existingDirectory("Knowledge Vault/Chris Knowledge/500 Personal Journal") }
    private static func discoveredResearchJournals() -> [URL] { existingDirectory("Knowledge Vault/Monday Knowledge/500 Research Journal") }
    private static func discoveredPlannerFeeds() -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-planner/daily-plan.json")
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func existingDirectory(_ relativePath: String) -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func modifiedDate(for url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
}

struct SuggestedPairing {
    let pluginURL: URL
    let projectVaultURL: URL
    let captainsLogURL: URL?
    let researchJournalURL: URL?
    let plannerFeedURL: URL?
}

enum PairingError: LocalizedError {
    case invalidPlugin, invalidProjectVault, invalidCaptainsLog, invalidResearchJournal, invalidPlannerFeed
    var errorDescription: String? {
        switch self {
        case .invalidPlugin: "Select the folder containing the installed MONDAY Thermo plugin. Its .codex-plugin/plugin.json file must identify it as monday-thermo."
        case .invalidProjectVault: "Select the Project Knowledge vault that contains a 03 Projects folder."
        case .invalidCaptainsLog: "The selected Captain's Log folder is no longer available."
        case .invalidResearchJournal: "The selected MONDAY Research Journal folder is no longer available."
        case .invalidPlannerFeed: "Choose an existing Planner JSON file. Command Center reads it but never writes calendar credentials to it."
        }
    }
}

struct CommandCenterPairingView: View {
    @ObservedObject private var pairing = CommandCenterPairing.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pluginURL: URL?
    @State private var projectVaultURL: URL?
    @State private var captainsLogURL: URL?
    @State private var researchJournalURL: URL?
    @State private var plannerFeedURL: URL?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("COMMAND CENTER SETTINGS", systemImage: "gearshape.2").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.blue)
                Text("Connect only the MONDAY data you choose").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("Command Center automatically finds the installed plugin and standard vaults. Calendar authorization stays in Codex. The Planner skill shares only its exported local plan file with this app.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            PairingPathRow(title: "Installed MONDAY plugin", detail: "Required. Select the monday-thermo plugin folder.", url: pluginURL) { pluginURL = chooseDirectory(prompt: "Select your installed MONDAY Thermo plugin") }
            PairingPathRow(title: "Project Knowledge vault", detail: "Required. Select the vault containing 03 Projects.", url: projectVaultURL) { projectVaultURL = chooseDirectory(prompt: "Select your Project Knowledge vault") }
            PairingPathRow(title: "Captain's Log", detail: "Personal journal. Default: Chris Knowledge/500 Personal Journal.", url: captainsLogURL) { captainsLogURL = chooseDirectory(prompt: "Select your Captain's Log folder") }
            PairingPathRow(title: "MONDAY Research Journal", detail: "MONDAY's journal. Default: Monday Knowledge/500 Research Journal.", url: researchJournalURL) { researchJournalURL = chooseDirectory(prompt: "Select MONDAY's Research Journal folder") }
            PairingPathRow(title: "Planner shared plan", detail: "Optional JSON file exported by the Codex Planner skill. It supplies the Planner and today's calendar.", url: plannerFeedURL) { plannerFeedURL = chooseFile(prompt: "Select the Planner JSON file") }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if pairing.isPaired { Button("Forget this Mac") { pairing.clear(); pluginURL = nil; projectVaultURL = nil; captainsLogURL = nil; researchJournalURL = nil; plannerFeedURL = nil }.foregroundStyle(.red) }
                Spacer(); Button("Cancel") { dismiss() }; Button("Save Settings") { save() }.buttonStyle(.borderedProminent).disabled(pluginURL == nil || projectVaultURL == nil)
            }
        }
        .padding(28).frame(width: 680)
        .onAppear {
            let suggestion = pairing.suggestedPairing
            pluginURL = pairing.pluginURL ?? suggestion?.pluginURL
            projectVaultURL = pairing.projectVaultURL ?? suggestion?.projectVaultURL
            captainsLogURL = pairing.captainsLogURL ?? suggestion?.captainsLogURL
            researchJournalURL = pairing.researchJournalURL ?? suggestion?.researchJournalURL
            plannerFeedURL = pairing.plannerFeedURL
        }
    }

    private func save() {
        guard let pluginURL, let projectVaultURL else { return }
        do {
            try pairing.pair(pluginURL: pluginURL, projectVaultURL: projectVaultURL, captainsLogURL: captainsLogURL, researchJournalURL: researchJournalURL, plannerFeedURL: plannerFeedURL)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel(); panel.message = prompt; panel.prompt = "Choose"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func chooseFile(prompt: String) -> URL? {
        let panel = NSOpenPanel(); panel.message = prompt; panel.prompt = "Choose"; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct PairingPathRow: View {
    let title: String; let detail: String; let url: URL?; let action: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(url?.path ?? detail).font(.system(size: 11)).foregroundStyle(url == nil ? Color.secondary : Color.green).lineLimit(2).truncationMode(.middle)
            }
            Spacer(); Button(url == nil ? "Choose…" : "Change…", action: action)
        }
        .padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}
