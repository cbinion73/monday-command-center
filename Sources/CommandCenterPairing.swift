import AppKit
import Foundation
import SwiftUI

enum MondayRuntimePluginValidation: Equatable {
    case compatible(pluginVersion: String)
    case upgradeRequired(reason: String)

    var isCompatible: Bool {
        if case .compatible = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .compatible(let version): "MONDAY \(version) provides runtime capability 2.0.0 and Operations schema 2."
        case .upgradeRequired(let reason): "Upgrade Required: \(reason) Planner and Digital Twin remain available."
        }
    }
}

enum MondayEvaluationPluginValidation: Equatable {
    case compatible(pluginVersion: String)
    case upgradeRequired(reason: String)

    var isCompatible: Bool {
        if case .compatible = self { return true }
        return false
    }
    var message: String {
        switch self {
        case .compatible(let version): "MONDAY \(version) provides the governed evaluation capability."
        case .upgradeRequired(let reason): "Evaluation Upgrade Required: \(reason) Existing Planner, Twin, and Runtime rooms remain available."
        }
    }
}

struct MondayPluginVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let base = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let components = base.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3, components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

enum MondayRuntimePluginInspector {
    static func validate(pluginURL: URL, appVersion: String) -> MondayRuntimePluginValidation {
        let manifestURL = pluginURL.appendingPathComponent(".codex-plugin/plugin.json")
        guard let manifest = jsonObject(at: manifestURL), manifest["name"] as? String == "monday",
              let version = manifest["version"] as? String,
              let parsedVersion = MondayPluginVersion(version),
              let minimum = MondayPluginVersion("0.1.0"), let maximum = MondayPluginVersion("0.2.0"),
              parsedVersion >= minimum, parsedVersion < maximum else {
            return .upgradeRequired(reason: "The selected folder is not a supported primary monday plugin version (requires 0.1.x).")
        }

        let runtimeSkill = pluginURL.appendingPathComponent("skills/monday-runtime/SKILL.md")
        guard FileManager.default.fileExists(atPath: runtimeSkill.path) else {
            return .upgradeRequired(reason: "The primary plugin does not contain the monday-runtime capability.")
        }

        let registryURL = pluginURL.appendingPathComponent("skills/monday-core/references/capability-registry.json")
        guard let registry = jsonObject(at: registryURL), registry["schemaVersion"] as? Int == 1,
              let capabilities = registry["capabilities"] as? [[String: Any]],
              capabilities.contains(where: { $0["id"] as? String == "monday-runtime" }) else {
            return .upgradeRequired(reason: "The primary capability registry does not route monday-runtime.")
        }

        let matrixURL = pluginURL.appendingPathComponent("skills/monday-runtime/references/compatibility-matrix.json")
        guard let matrix = jsonObject(at: matrixURL),
              matrix["schemaVersion"] as? Int == 2,
              matrix["runtimeDatabaseVersion"] as? Int == 2,
              matrix["operationsProjectionVersion"] as? Int == 2,
              matrix["operationsReadbackVersion"] as? Int == 1,
              matrix["capabilityVersion"] as? String == "2.0.0",
              let supported = matrix["supportedAppVersions"] as? [String: Any],
              let minimumApp = supported["minimumInclusive"] as? String,
              let maximumApp = supported["maximumExclusive"] as? String,
              appIsSupported(appVersion, minimum: minimumApp, maximumExclusive: maximumApp) else {
            return .upgradeRequired(reason: "MONDAY does not advertise runtime DB 2, Operations schema 2, readback schema 1, and support for this app version.")
        }
        return .compatible(pluginVersion: version)
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func appIsSupported(_ value: String, minimum: String, maximumExclusive: String) -> Bool {
        guard let current = MondayPluginVersion(value), let lower = MondayPluginVersion(minimum), let upper = MondayPluginVersion(maximumExclusive) else { return false }
        return current >= lower && current < upper
    }
}

enum MondayEvaluationPluginInspector {
    static func validate(pluginURL: URL, appVersion: String) -> MondayEvaluationPluginValidation {
        guard let manifest = jsonObject(at: pluginURL.appendingPathComponent(".codex-plugin/plugin.json")),
              manifest["name"] as? String == "monday", let version = manifest["version"] as? String,
              let plugin = MondayPluginVersion(version), let minimum = MondayPluginVersion("0.1.0"), let maximum = MondayPluginVersion("0.2.0"),
              plugin >= minimum, plugin < maximum,
              let app = MondayPluginVersion(appVersion), let minimumApp = MondayPluginVersion("0.4.2"), let maximumApp = MondayPluginVersion("0.5.0"),
              app >= minimumApp, app < maximumApp else {
            return .upgradeRequired(reason: "The selected primary plugin or app version is outside the supported 0.1.x / 0.4.2-to-0.5.0 range.")
        }
        guard FileManager.default.fileExists(atPath: pluginURL.appendingPathComponent("skills/monday-evaluation/SKILL.md").path) else {
            return .upgradeRequired(reason: "The primary plugin does not contain monday-evaluation.")
        }
        guard let registry = jsonObject(at: pluginURL.appendingPathComponent("skills/monday-core/references/capability-registry.json")),
              registry["schemaVersion"] as? Int == 1,
              let capabilities = registry["capabilities"] as? [[String: Any]],
              capabilities.contains(where: { $0["id"] as? String == "monday-evaluation" }) else {
            return .upgradeRequired(reason: "The primary capability registry does not route monday-evaluation.")
        }
        return .compatible(pluginVersion: version)
    }

    private static func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

/// User-approved local locations. Command Center reads them but never stores
/// Codex, calendar, or vault credentials.
@MainActor
final class CommandCenterPairing: ObservableObject {
    static let shared = CommandCenterPairing()
    @Published private(set) var pluginURL: URL?
    @Published private(set) var projectVaultURL: URL?
    @Published private(set) var personalProjectVaultURL: URL?
    @Published private(set) var captainsLogURL: URL?
    @Published private(set) var researchJournalURL: URL?
    @Published private(set) var activityLedgerURL: URL?
    @Published private(set) var operationsURL: URL?
    @Published private(set) var plannerFeedURL: URL?
    @Published private(set) var continuityFeedURL: URL?
    @Published private(set) var meetingNotesURL: URL?
    @Published private(set) var weatherAddress: String = ""
    @Published private(set) var revision = 0

    private enum Key {
        static let plugin = "pairing.pluginPath"
        static let projectVault = "pairing.projectVaultPath"
        static let personalProjectVault = "pairing.personalProjectVaultPath"
        static let captainsLog = "pairing.captainsLogPath"
        static let researchJournal = "pairing.researchJournalPath"
        static let activityLedger = "pairing.activityLedgerPath"
        static let operations = "pairing.operationsPath"
        static let plannerFeed = "pairing.plannerFeedPath"
        static let continuityFeed = "pairing.continuityFeedPath"
        static let meetingNotes = "pairing.meetingNotesPath"
        static let weatherAddress = "pairing.weatherAddress"
    }

    private init(defaults: UserDefaults = .standard) {
        pluginURL = defaults.string(forKey: Key.plugin).map { URL(fileURLWithPath: $0, isDirectory: true) }
        projectVaultURL = defaults.string(forKey: Key.projectVault).map { URL(fileURLWithPath: $0, isDirectory: true) }
        personalProjectVaultURL = defaults.string(forKey: Key.personalProjectVault).map { URL(fileURLWithPath: $0, isDirectory: true) }
        captainsLogURL = defaults.string(forKey: Key.captainsLog).map { URL(fileURLWithPath: $0, isDirectory: true) }
        researchJournalURL = defaults.string(forKey: Key.researchJournal).map { URL(fileURLWithPath: $0, isDirectory: true) }
        activityLedgerURL = defaults.string(forKey: Key.activityLedger).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.discoveredActivityLedgers().first
        operationsURL = defaults.string(forKey: Key.operations).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.discoveredOperations().first
        plannerFeedURL = defaults.string(forKey: Key.plannerFeed).map { URL(fileURLWithPath: $0) } ?? Self.discoveredPlannerFeeds().first
        continuityFeedURL = defaults.string(forKey: Key.continuityFeed).map { URL(fileURLWithPath: $0) } ?? Self.discoveredContinuityFeeds().first
        meetingNotesURL = defaults.string(forKey: Key.meetingNotes).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.discoveredMeetingNotes().first
        weatherAddress = defaults.string(forKey: Key.weatherAddress) ?? defaults.string(forKey: "weatherLocation") ?? ""
        discardInvalidLocations()
    }

    var isPaired: Bool { pluginURL != nil && projectsDirectoryURL != nil }
    var runtimePluginValidation: MondayRuntimePluginValidation {
        guard let pluginURL else { return .upgradeRequired(reason: "No primary MONDAY plugin is paired.") }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2"
        return MondayRuntimePluginInspector.validate(pluginURL: pluginURL, appVersion: appVersion)
    }
    var evaluationPluginValidation: MondayEvaluationPluginValidation {
        guard let pluginURL else { return .upgradeRequired(reason: "No primary MONDAY plugin is paired.") }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2"
        return MondayEvaluationPluginInspector.validate(pluginURL: pluginURL, appVersion: appVersion)
    }
    var projectsDirectoryURL: URL? {
        guard let projectVaultURL else { return nil }
        let projects = projectVaultURL.appendingPathComponent("03 Projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: projects.path) ? projects : nil
    }

    var personalProjectsDirectoryURL: URL? {
        guard let personalProjectVaultURL else { return nil }
        let projects = personalProjectVaultURL.appendingPathComponent("03 Projects", isDirectory: true)
        return FileManager.default.fileExists(atPath: projects.path) ? projects : nil
    }

    /// Derived only from governed project records. Command Center never writes it.
    var projectWorkflowFeedURL: URL? {
        guard let projectVaultURL else { return nil }
        return projectVaultURL.appendingPathComponent("04 Portfolio/Command Center/project-workflow-feed.json")
    }

    @discardableResult
    func discoverAndPairIfPossible() -> Bool {
        guard !isPaired, let suggestion = suggestedPairing else { return isPaired }
        do {
            try pair(pluginURL: suggestion.pluginURL, projectVaultURL: suggestion.projectVaultURL, personalProjectVaultURL: suggestion.personalProjectVaultURL, captainsLogURL: suggestion.captainsLogURL, researchJournalURL: suggestion.researchJournalURL, activityLedgerURL: suggestion.activityLedgerURL, operationsURL: suggestion.operationsURL, plannerFeedURL: suggestion.plannerFeedURL, continuityFeedURL: suggestion.continuityFeedURL, meetingNotesURL: suggestion.meetingNotesURL, weatherAddress: weatherAddress)
            return true
        } catch { return false }
    }

    var suggestedPairing: SuggestedPairing? {
        guard let pluginURL = Self.discoveredPlugins().first, let projectVaultURL = Self.discoveredProjectVaults().first else { return nil }
        return SuggestedPairing(pluginURL: pluginURL, projectVaultURL: projectVaultURL, personalProjectVaultURL: Self.discoveredPersonalProjectVaults().first, captainsLogURL: Self.discoveredCaptainsLogs().first, researchJournalURL: Self.discoveredResearchJournals().first, activityLedgerURL: Self.discoveredActivityLedgers().first, operationsURL: Self.discoveredOperations().first, plannerFeedURL: Self.discoveredPlannerFeeds().first, continuityFeedURL: Self.discoveredContinuityFeeds().first, meetingNotesURL: Self.discoveredMeetingNotes().first)
    }

    func pair(pluginURL: URL, projectVaultURL: URL, personalProjectVaultURL: URL?, captainsLogURL: URL?, researchJournalURL: URL?, activityLedgerURL: URL?, operationsURL: URL?, plannerFeedURL: URL?, continuityFeedURL: URL?, meetingNotesURL: URL?, weatherAddress: String) throws {
        guard Self.isMondayPlugin(pluginURL) else { throw PairingError.invalidPlugin }
        guard FileManager.default.fileExists(atPath: projectVaultURL.appendingPathComponent("03 Projects", isDirectory: true).path) else { throw PairingError.invalidProjectVault }
        if let personalProjectVaultURL, !FileManager.default.fileExists(atPath: personalProjectVaultURL.appendingPathComponent("03 Projects", isDirectory: true).path) { throw PairingError.invalidPersonalProjectVault }
        if let captainsLogURL, !FileManager.default.fileExists(atPath: captainsLogURL.path) { throw PairingError.invalidCaptainsLog }
        if let researchJournalURL, !FileManager.default.fileExists(atPath: researchJournalURL.path) { throw PairingError.invalidResearchJournal }
        if let activityLedgerURL, !FileManager.default.fileExists(atPath: activityLedgerURL.path) { throw PairingError.invalidActivityLedger }
        if let operationsURL, !FileManager.default.fileExists(atPath: operationsURL.path) { throw PairingError.invalidOperations }
        if let plannerFeedURL, !FileManager.default.fileExists(atPath: plannerFeedURL.path) { throw PairingError.invalidPlannerFeed }
        if let continuityFeedURL, !FileManager.default.fileExists(atPath: continuityFeedURL.path) { throw PairingError.invalidContinuityFeed }
        if let meetingNotesURL, !FileManager.default.fileExists(atPath: meetingNotesURL.path) { throw PairingError.invalidMeetingNotes }
        self.pluginURL = pluginURL.standardizedFileURL
        self.projectVaultURL = projectVaultURL.standardizedFileURL
        self.personalProjectVaultURL = personalProjectVaultURL?.standardizedFileURL
        self.captainsLogURL = captainsLogURL?.standardizedFileURL
        self.researchJournalURL = researchJournalURL?.standardizedFileURL
        self.activityLedgerURL = activityLedgerURL?.standardizedFileURL
        self.operationsURL = operationsURL?.standardizedFileURL
        self.plannerFeedURL = plannerFeedURL?.standardizedFileURL
        self.continuityFeedURL = continuityFeedURL?.standardizedFileURL
        self.meetingNotesURL = meetingNotesURL?.standardizedFileURL
        self.weatherAddress = weatherAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        persist(); revision += 1
    }

    func clear() {
        pluginURL = nil; projectVaultURL = nil; personalProjectVaultURL = nil; captainsLogURL = nil; researchJournalURL = nil; activityLedgerURL = nil; operationsURL = nil; plannerFeedURL = nil; continuityFeedURL = nil; meetingNotesURL = nil; weatherAddress = ""
        [Key.plugin, Key.projectVault, Key.personalProjectVault, Key.captainsLog, Key.researchJournal, Key.activityLedger, Key.operations, Key.plannerFeed, Key.continuityFeed, Key.meetingNotes, Key.weatherAddress].forEach(UserDefaults.standard.removeObject(forKey:))
        revision += 1
    }

    private func discardInvalidLocations() {
        guard let pluginURL, let projectVaultURL, Self.isMondayPlugin(pluginURL), FileManager.default.fileExists(atPath: projectVaultURL.appendingPathComponent("03 Projects").path) else { clear(); return }
        // Migrate only the previously shipped legacy default. Any other user-chosen
        // location remains untouched.
        let legacyVault = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/MONDAY/Project Knowledge", isDirectory: true).standardizedFileURL
        let canonicalVault = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Knowledge Vault/Project Knowledge", isDirectory: true).standardizedFileURL
        if projectVaultURL.standardizedFileURL == legacyVault,
           FileManager.default.fileExists(atPath: canonicalVault.appendingPathComponent("03 Projects", isDirectory: true).path) {
            self.projectVaultURL = canonicalVault
        }
        if let captainsLogURL, !FileManager.default.fileExists(atPath: captainsLogURL.path) { self.captainsLogURL = nil }
        if let personalProjectVaultURL, !FileManager.default.fileExists(atPath: personalProjectVaultURL.appendingPathComponent("03 Projects", isDirectory: true).path) { self.personalProjectVaultURL = nil }
        if let researchJournalURL, !FileManager.default.fileExists(atPath: researchJournalURL.path) { self.researchJournalURL = nil }
        if let activityLedgerURL, !FileManager.default.fileExists(atPath: activityLedgerURL.path) { self.activityLedgerURL = nil }
        if let operationsURL, !FileManager.default.fileExists(atPath: operationsURL.path) { self.operationsURL = nil }
        if let plannerFeedURL, !FileManager.default.fileExists(atPath: plannerFeedURL.path) { self.plannerFeedURL = nil }
        if let continuityFeedURL, !FileManager.default.fileExists(atPath: continuityFeedURL.path) { self.continuityFeedURL = nil }
        if let meetingNotesURL, !FileManager.default.fileExists(atPath: meetingNotesURL.path) { self.meetingNotesURL = nil }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(pluginURL?.path, forKey: Key.plugin)
        UserDefaults.standard.set(projectVaultURL?.path, forKey: Key.projectVault)
        UserDefaults.standard.set(personalProjectVaultURL?.path, forKey: Key.personalProjectVault)
        UserDefaults.standard.set(captainsLogURL?.path, forKey: Key.captainsLog)
        UserDefaults.standard.set(researchJournalURL?.path, forKey: Key.researchJournal)
        UserDefaults.standard.set(activityLedgerURL?.path, forKey: Key.activityLedger)
        UserDefaults.standard.set(operationsURL?.path, forKey: Key.operations)
        UserDefaults.standard.set(plannerFeedURL?.path, forKey: Key.plannerFeed)
        UserDefaults.standard.set(continuityFeedURL?.path, forKey: Key.continuityFeed)
        UserDefaults.standard.set(meetingNotesURL?.path, forKey: Key.meetingNotes)
        UserDefaults.standard.set(weatherAddress, forKey: Key.weatherAddress)
    }

    private static func isMondayPlugin(_ url: URL) -> Bool {
        let manifest = url.appendingPathComponent(".codex-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = value["name"] as? String else { return false }
        return name == "monday"
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
        let candidates = [home.appendingPathComponent("Knowledge Vault/Project Knowledge", isDirectory: true), home.appendingPathComponent("Documents/MONDAY/Project Knowledge", isDirectory: true)]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("03 Projects", isDirectory: true).path) }
    }
    private static func discoveredPersonalProjectVaults() -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Knowledge Vault/Personal Project Knowledge", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func discoveredCaptainsLogs() -> [URL] { existingDirectory("Knowledge Vault/Chris Knowledge/500 Personal Journal") }
    private static func discoveredResearchJournals() -> [URL] { existingDirectory("Knowledge Vault/Monday Knowledge/500 Research Journal") }
    private static func discoveredActivityLedgers() -> [URL] { existingDirectory("Knowledge Vault/Monday Knowledge/100 Activity Ledger") }
    private static func discoveredOperations() -> [URL] { existingDirectory("Knowledge Vault/Monday Knowledge/400 MONDAY Operations") }
    private static func discoveredPlannerFeeds() -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-planner/daily-plan.json")
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func discoveredContinuityFeeds() -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-meeting-continuity/summary.json")
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func discoveredMeetingNotes() -> [URL] { existingDirectory("Knowledge Vault/Meeting Notes") }
    private static func existingDirectory(_ relativePath: String) -> [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? [url] : []
    }
    private static func modifiedDate(for url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
}

struct SuggestedPairing {
    let pluginURL: URL
    let projectVaultURL: URL
    let personalProjectVaultURL: URL?
    let captainsLogURL: URL?
    let researchJournalURL: URL?
    let activityLedgerURL: URL?
    let operationsURL: URL?
    let plannerFeedURL: URL?
    let continuityFeedURL: URL?
    let meetingNotesURL: URL?
}

enum PairingError: LocalizedError {
    case invalidPlugin, invalidProjectVault, invalidPersonalProjectVault, invalidCaptainsLog, invalidResearchJournal, invalidActivityLedger, invalidOperations, invalidPlannerFeed, invalidContinuityFeed, invalidMeetingNotes
    var errorDescription: String? {
        switch self {
        case .invalidPlugin: "Select the folder containing the consolidated MONDAY plugin. Its .codex-plugin/plugin.json file must identify it as monday."
        case .invalidProjectVault: "Select the Project Knowledge vault that contains a 03 Projects folder."
        case .invalidPersonalProjectVault: "Select the Personal Project Knowledge vault."
        case .invalidCaptainsLog: "The selected Captain's Log folder is no longer available."
        case .invalidResearchJournal: "The selected MONDAY Research Journal folder is no longer available."
        case .invalidActivityLedger: "The selected MONDAY Activity Ledger folder is no longer available."
        case .invalidOperations: "The selected MONDAY Operations folder is no longer available."
        case .invalidPlannerFeed: "Choose an existing Planner JSON file. Command Center reads it but never writes calendar credentials to it."
        case .invalidContinuityFeed: "Choose an existing Meeting Continuity reconciliation JSON file."
        case .invalidMeetingNotes: "The selected Meeting Notes folder is no longer available."
        }
    }
}

struct CommandCenterPairingView: View {
    @ObservedObject private var pairing = CommandCenterPairing.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pluginURL: URL?
    @State private var projectVaultURL: URL?
    @State private var personalProjectVaultURL: URL?
    @State private var captainsLogURL: URL?
    @State private var researchJournalURL: URL?
    @State private var activityLedgerURL: URL?
    @State private var operationsURL: URL?
    @State private var plannerFeedURL: URL?
    @State private var continuityFeedURL: URL?
    @State private var meetingNotesURL: URL?
    @State private var weatherAddress = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("COMMAND CENTER SETTINGS", systemImage: "gearshape.2").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.blue)
                Text("Connect only the MONDAY data you choose").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("Command Center automatically finds the installed plugin and standard vaults. Calendar authorization stays in Codex. The Planner skill shares only its exported local plan file with this app.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weather address").font(.system(size: 14, weight: .semibold))
                TextField("Street address, city, or region", text: $weatherAddress)
                    .textFieldStyle(.roundedBorder)
                Text("Stored locally on this Mac. It is sent to Open-Meteo for current conditions and, for U.S. locations, to the National Weather Service only to detect an active tornado alert. The Deck displays the returned locality, not your street address.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            PairingPathRow(title: "Installed MONDAY plugin", detail: "Required. Select the consolidated monday plugin folder.", url: pluginURL) { pluginURL = chooseDirectory(prompt: "Select your installed MONDAY plugin") }
            if let pluginURL {
                let validation = MondayRuntimePluginInspector.validate(pluginURL: pluginURL, appVersion: appVersion)
                Label(validation.message, systemImage: validation.isCompatible ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(validation.isCompatible ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                let evaluation = MondayEvaluationPluginInspector.validate(pluginURL: pluginURL, appVersion: appVersion)
                Label(evaluation.message, systemImage: evaluation.isCompatible ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(evaluation.isCompatible ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PairingPathRow(title: "Project Knowledge vault", detail: "Required. Select the vault containing 03 Projects.", url: projectVaultURL) { projectVaultURL = chooseDirectory(prompt: "Select your Project Knowledge vault") }
            PairingPathRow(title: "Personal Project Knowledge", detail: "Optional and private. Default: Knowledge Vault/Personal Project Knowledge.", url: personalProjectVaultURL) { personalProjectVaultURL = chooseDirectory(prompt: "Select your Personal Project Knowledge vault") }
            PairingPathRow(title: "Captain's Log", detail: "Personal journal. Default: Chris Knowledge/500 Personal Journal.", url: captainsLogURL) { captainsLogURL = chooseDirectory(prompt: "Select your Captain's Log folder") }
            PairingPathRow(title: "Research Chronicle", detail: "Verified MONDAY system-building records. Default: Monday Knowledge/500 Research Journal.", url: researchJournalURL) { researchJournalURL = chooseDirectory(prompt: "Select MONDAY's Research Chronicle folder") }
            PairingPathRow(title: "Activity Ledger", detail: "Append-only MONDAY activity receipts. Default: Monday Knowledge/100 Activity Ledger.", url: activityLedgerURL) { activityLedgerURL = chooseDirectory(prompt: "Select MONDAY's Activity Ledger folder") }
            PairingPathRow(title: "MONDAY Operations", detail: "Operations receipts, open loops, and pipeline health. Default: Monday Knowledge/400 MONDAY Operations.", url: operationsURL) { operationsURL = chooseDirectory(prompt: "Select MONDAY Operations") }
            PairingPathRow(title: "Planner shared plan", detail: "Optional JSON file exported by the Codex Planner skill. It supplies the Planner and today's calendar.", url: plannerFeedURL) { plannerFeedURL = chooseFile(prompt: "Select the Planner JSON file") }
            PairingPathRow(title: "Meeting Continuity summary", detail: "Optional JSON file exported by MONDAY Meeting Continuity. It supplies coverage and backlog views.", url: continuityFeedURL) { continuityFeedURL = chooseFile(prompt: "Select the Meeting Continuity JSON file") }
            PairingPathRow(title: "Meeting Notes", detail: "Dedicated governed notes. Default: Knowledge Vault/Meeting Notes.", url: meetingNotesURL) { meetingNotesURL = chooseDirectory(prompt: "Select your Meeting Notes folder") }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if pairing.isPaired { Button("Forget this Mac") { pairing.clear(); pluginURL = nil; projectVaultURL = nil; personalProjectVaultURL = nil; captainsLogURL = nil; researchJournalURL = nil; activityLedgerURL = nil; operationsURL = nil; plannerFeedURL = nil; continuityFeedURL = nil; meetingNotesURL = nil; weatherAddress = "" }.foregroundStyle(.red) }
                Spacer(); Button("Cancel") { dismiss() }; Button("Save Settings") { save() }.buttonStyle(.borderedProminent).disabled(pluginURL == nil || projectVaultURL == nil)
            }
        }
        .padding(28).frame(width: 680)
        .onAppear {
            let suggestion = pairing.suggestedPairing
            pluginURL = pairing.pluginURL ?? suggestion?.pluginURL
            projectVaultURL = pairing.projectVaultURL ?? suggestion?.projectVaultURL
            personalProjectVaultURL = pairing.personalProjectVaultURL ?? suggestion?.personalProjectVaultURL
            captainsLogURL = pairing.captainsLogURL ?? suggestion?.captainsLogURL
            researchJournalURL = pairing.researchJournalURL ?? suggestion?.researchJournalURL
            activityLedgerURL = pairing.activityLedgerURL ?? suggestion?.activityLedgerURL
            operationsURL = pairing.operationsURL ?? suggestion?.operationsURL
            plannerFeedURL = pairing.plannerFeedURL
            continuityFeedURL = pairing.continuityFeedURL ?? suggestion?.continuityFeedURL
            meetingNotesURL = pairing.meetingNotesURL ?? suggestion?.meetingNotesURL
            weatherAddress = pairing.weatherAddress
        }
    }

    private func save() {
        guard let pluginURL, let projectVaultURL else { return }
        do {
            try pairing.pair(pluginURL: pluginURL, projectVaultURL: projectVaultURL, personalProjectVaultURL: personalProjectVaultURL, captainsLogURL: captainsLogURL, researchJournalURL: researchJournalURL, activityLedgerURL: activityLedgerURL, operationsURL: operationsURL, plannerFeedURL: plannerFeedURL, continuityFeedURL: continuityFeedURL, meetingNotesURL: meetingNotesURL, weatherAddress: weatherAddress)
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

    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.2" }
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
