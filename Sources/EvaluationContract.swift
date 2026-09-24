import CryptoKit
import Foundation

struct EvaluationProjection: Decodable {
    let schemaVersion: Int
    let projectionID: String
    let contentDigest: String
    let generatedAt: Date
    let validUntil: Date
    let producer: String
    let audience: String
    let releaseCandidate: EvaluationReleaseCandidate
    let suite: EvaluationSuite
    let caseCoverage: [EvaluationCaseResult]
    let gateResults: [EvaluationGateResult]
    let connectorDecisions: [EvaluationConnectorDecision]
    let pilot: EvaluationPilot
    let enterpriseClaim: EvaluationEnterpriseClaim
    let evidence: [EvaluationEvidence]
    let coverage: EvaluationCoverage

    func validation(appVersion: String, pairedPluginVersion: String? = nil, now: Date = .now) -> EvaluationProjectionValidation {
        guard schemaVersion == 1 else { return .unsupportedSchema(schemaVersion) }
        guard projectionID.range(of: #"^evaluation-[a-zA-Z0-9._-]{8,160}$"#, options: .regularExpression) != nil,
              projectionID.hasSuffix(String(contentDigest.prefix(12))) else { return .missingProjectionIdentifier }
        guard contentDigest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return .invalidContentDigest }
        guard generatedAt <= validUntil, validUntil > now else { return .expired(validUntil) }
        guard producer == "monday-evaluation", audience == "Chris-private-local" else { return .invalidProducerOrAudience }
        guard releaseCandidate.isValid, releaseCandidate.isCompatible(appVersion: appVersion, pairedPluginVersion: pairedPluginVersion), suite.isValid else { return .incompatibleReleaseCandidate }

        let identifierGroups: [(String, [String])] = [
            ("case", caseCoverage.map(\.caseID)),
            ("gate", gateResults.map(\.gateID)),
            ("connector", connectorDecisions.map(\.connectorID)),
            ("evidence", evidence.map(\.evidenceID))
        ]
        for (label, identifiers) in identifierGroups where Set(identifiers).count != identifiers.count {
            return .duplicateIdentifier(label)
        }

        let evidenceIDs = Set(evidence.map(\.evidenceID))
        for item in caseCoverage {
            guard item.isValid, Set(item.evidenceIDs).isSubset(of: evidenceIDs) else { return .invalidCase(item.caseID) }
        }
        for gate in gateResults {
            guard gate.isValid, Set(gate.evidenceIDs).isSubset(of: evidenceIDs) else { return .invalidGate(gate.gateID) }
        }
        for connector in connectorDecisions {
            guard connector.isValid, Set(connector.evidenceIDs).isSubset(of: evidenceIDs) else { return .invalidConnector(connector.connectorID) }
        }
        guard pilot.isValid, Set(pilot.evidenceIDs).isSubset(of: evidenceIDs) else { return .invalidPilot }
        for item in evidence where !item.isValid { return .invalidEvidence(item.evidenceID) }

        let requiredGates = Set(["engineering-release", "pilot-start", "connector-activation", "enterprise-claim"])
        guard requiredGates.isSubset(of: Set(gateResults.map(\.gateID))) else { return .missingRequiredGate }
        if let engineering = gateResults.first(where: { $0.gateID == "engineering-release" }), engineering.status == "PASS",
           caseCoverage.contains(where: { $0.releaseBlocking && $0.result != "pass" }) { return .invalidGate(engineering.gateID) }
        guard let enterpriseGate = gateResults.first(where: { $0.gateID == "enterprise-claim" }),
              enterpriseClaim.isValid(machineGate: enterpriseGate, pilot: pilot) else { return .invalidEnterpriseClaim }

        let resultCounts = Dictionary(grouping: caseCoverage, by: \.result).mapValues(\.count)
        guard coverage.caseCount == caseCoverage.count,
              coverage.gateCount == gateResults.count,
              coverage.connectorCount == connectorDecisions.count,
              coverage.evidenceCount == evidence.count,
              coverage.passedCaseCount == resultCounts["pass", default: 0],
              coverage.failedCaseCount == resultCounts["fail", default: 0],
              coverage.blockedCaseCount == resultCounts["blocked", default: 0],
              coverage.skippedCaseCount == resultCounts["skipped", default: 0],
              coverage.notRunCaseCount == resultCounts["not-run", default: 0],
              coverage.releaseBlockingCount == caseCoverage.filter(\.releaseBlocking).count,
              coverage.releaseBlockingPassedCount == caseCoverage.filter({ $0.releaseBlocking && $0.result == "pass" }).count,
              coverage.unresolvedCount >= 0,
              suite.requiredCaseCount == caseCoverage.count else { return .denominatorMismatch }
        return .current
    }

    func readback(viewID: String, consumer: String, appVersion: String, pairedPluginVersion: String? = nil, displayedAt: Date = .now) -> EvaluationReadback? {
        guard validation(appVersion: appVersion, pairedPluginVersion: pairedPluginVersion, now: displayedAt) == .current,
              EvaluationReadback.allowedViewIDs.contains(viewID) else { return nil }
        return EvaluationReadback(schemaVersion: 1, projectionID: projectionID, projectionSchemaVersion: schemaVersion, contentDigest: contentDigest, consumer: consumer, appVersion: appVersion, displayedAt: displayedAt, state: "displayed", viewIDs: [viewID])
    }
}

enum EvaluationProjectionValidation: Equatable {
    case current
    case unsupportedSchema(Int)
    case missingProjectionIdentifier
    case invalidContentDigest
    case expired(Date)
    case invalidProducerOrAudience
    case incompatibleReleaseCandidate
    case duplicateIdentifier(String)
    case invalidCase(String)
    case invalidGate(String)
    case invalidConnector(String)
    case invalidPilot
    case invalidEnterpriseClaim
    case invalidEvidence(String)
    case missingRequiredGate
    case denominatorMismatch
    case prohibitedMaterial
}

struct EvaluationReleaseCandidate: Decodable {
    let releaseID: String
    let pluginVersion: String
    let pluginCommit: String
    let appVersion: String
    let appBuild: Int
    let appCommit: String
    let minimumPluginVersion: String
    let maximumPluginVersionExclusive: String
    let minimumAppVersion: String
    let maximumAppVersionExclusive: String
    let compatibilityStatus: String

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(releaseID)
            && pluginCommit.range(of: "^[a-f0-9]{7,64}$", options: .regularExpression) != nil
            && appCommit.range(of: "^[a-f0-9]{7,64}$", options: .regularExpression) != nil
            && appBuild >= 1
    }

    func isCompatible(appVersion currentApp: String, pairedPluginVersion: String?) -> Bool {
        guard compatibilityStatus == "compatible", appVersion == currentApp,
              let current = EvaluationSemanticVersion(currentApp),
              let minimumApp = EvaluationSemanticVersion(minimumAppVersion),
              let maximumApp = EvaluationSemanticVersion(maximumAppVersionExclusive),
              current >= minimumApp, current < maximumApp,
              let plugin = EvaluationSemanticVersion(pairedPluginVersion ?? pluginVersion),
              let minimumPlugin = EvaluationSemanticVersion(minimumPluginVersion),
              let maximumPlugin = EvaluationSemanticVersion(maximumPluginVersionExclusive),
              plugin >= minimumPlugin, plugin < maximumPlugin else { return false }
        return pluginVersion == (pairedPluginVersion ?? pluginVersion) && appBuild >= 1
    }
}

struct EvaluationSuite: Decodable {
    let suiteID: String
    let suiteVersion: String
    let suiteDigest: String
    let requiredCaseCount: Int

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(suiteID)
            && EvaluationSemanticVersion(suiteVersion) != nil
            && suiteDigest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            && requiredCaseCount >= 0
    }
}

struct EvaluationCaseResult: Decodable, Identifiable {
    var id: String { caseID }
    let caseID: String
    let category: String
    let severity: String
    let result: String
    let releaseBlocking: Bool
    let requirementIDs: [String]
    let evidenceIDs: [String]

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(caseID)
            && ["critical", "high", "medium", "low"].contains(severity)
            && ["pass", "fail", "blocked", "skipped", "not-run"].contains(result)
            && !category.isEmpty && !requirementIDs.isEmpty
    }
}

struct EvaluationGateResult: Decodable, Identifiable {
    var id: String { gateID }
    let gateID: String
    let status: String
    let evaluatedAt: Date
    let reasonCodes: [String]
    let evidenceIDs: [String]

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(gateID)
            && ["PASS", "PASS WITH CONDITIONS", "FAIL", "BLOCKED"].contains(status)
    }
}

struct EvaluationConnectorDecision: Decodable, Identifiable {
    var id: String { connectorID }
    let connectorID: String
    let tier: Int
    let status: String
    let route: String
    let sourceID: String
    let authenticationState: String
    let coverageState: String
    let itemCount: Int
    let processedCount: Int
    let unresolvedCount: Int
    let readOnly: Bool
    let approvalState: String
    let evidenceIDs: [String]

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(connectorID) && EvaluationPrivacy.isOpaqueIdentifier(sourceID)
            && [1, 2, 3].contains(tier)
            && ["proposed", "evaluating", "approved-for-pilot", "active", "rejected", "retired"].contains(status)
            && ["authenticated", "expired", "missing", "unknown"].contains(authenticationState)
            && ["not-attempted", "empty", "partial", "complete", "blocked", "unknown"].contains(coverageState)
            && ["not-required", "pending", "approved", "rejected"].contains(approvalState)
            && itemCount >= 0 && processedCount >= 0 && unresolvedCount >= 0
            && processedCount + unresolvedCount == itemCount && readOnly
            && !(coverageState == "complete" && authenticationState != "authenticated")
            && !(["approved-for-pilot", "active"].contains(status) && approvalState != "approved")
            && !(tier == 3 && ["approved-for-pilot", "active"].contains(status))
    }
}

struct EvaluationPilot: Decodable {
    let pilotID: String
    let status: String
    let cohort: String
    let timezone: String
    let plannedBusinessDays: Int
    let plannedCheckpoints: Int
    let attemptedCheckpoints: Int
    let unattendedRolloversPlanned: Int
    let unattendedRolloversCompleted: Int
    let tier1AttemptsPlanned: Int
    let tier1AttemptsRecorded: Int
    let manualInterventionCount: Int
    let disposition: String
    let evidenceIDs: [String]

    var isValid: Bool {
        guard EvaluationPrivacy.isOpaqueIdentifier(pilotID)
            && ["not-started", "blocked", "running", "completed", "accepted", "extended", "stopped"].contains(status)
            && ["pending", "accept", "extend", "stop"].contains(disposition)
            && plannedBusinessDays >= 1 && plannedCheckpoints >= 1 && attemptedCheckpoints >= 0 && attemptedCheckpoints <= plannedCheckpoints
            && unattendedRolloversPlanned >= 1 && unattendedRolloversCompleted >= 0 && unattendedRolloversCompleted <= unattendedRolloversPlanned
            && tier1AttemptsPlanned >= 1 && tier1AttemptsRecorded >= 0 && tier1AttemptsRecorded <= tier1AttemptsPlanned
            && manualInterventionCount >= 0 && timezone == "America/New_York" else { return false }
        if status == "accepted" {
            return disposition == "accept" && attemptedCheckpoints == plannedCheckpoints
                && unattendedRolloversCompleted == unattendedRolloversPlanned
                && tier1AttemptsRecorded == tier1AttemptsPlanned && manualInterventionCount == 0
        }
        return true
    }
}

struct EvaluationEnterpriseClaim: Decodable {
    let status: String
    let claimAllowed: Bool
    let scope: String
    let safeStatement: String
    let unmetRequirementIDs: [String]

    func isValid(machineGate: EvaluationGateResult, pilot: EvaluationPilot) -> Bool {
        guard ["PASS", "BLOCKED"].contains(status), ["single-user", "representative-enterprise"].contains(scope), !safeStatement.isEmpty else { return false }
        if scope == "single-user" || pilot.cohort == "single-user" {
            return status == "BLOCKED" && !claimAllowed && machineGate.status != "PASS"
        }
        return claimAllowed
            ? status == "PASS" && machineGate.status == "PASS" && pilot.status == "accepted" && unmetRequirementIDs.isEmpty
            : status == "BLOCKED" && machineGate.status != "PASS"
    }
}

struct EvaluationEvidence: Decodable, Identifiable {
    var id: String { evidenceID }
    let evidenceID: String
    let kind: String
    let status: String
    let observedAt: Date
    let safeSummary: String

    var isValid: Bool {
        EvaluationPrivacy.isOpaqueIdentifier(evidenceID)
            && ["test", "build", "signature", "parity", "readback", "pilot-observation", "review"].contains(kind)
            && ["verified", "reported", "blocked", "unknown"].contains(status)
            && !safeSummary.isEmpty
    }
}

struct EvaluationCoverage: Decodable {
    let caseCount: Int
    let gateCount: Int
    let connectorCount: Int
    let evidenceCount: Int
    let passedCaseCount: Int
    let failedCaseCount: Int
    let blockedCaseCount: Int
    let skippedCaseCount: Int
    let notRunCaseCount: Int
    let releaseBlockingCount: Int
    let releaseBlockingPassedCount: Int
    let unresolvedCount: Int
}

struct EvaluationReadback: Codable, Equatable {
    let schemaVersion: Int
    let projectionID: String
    let projectionSchemaVersion: Int
    let contentDigest: String
    let consumer: String
    let appVersion: String
    let displayedAt: Date
    let state: String
    let viewIDs: [String]

    static let allowedViewIDs: Set<String> = [
        "evaluation-overview", "evaluation-coverage", "evaluation-release-gates",
        "evaluation-connectors", "evaluation-pilot", "evaluation-enterprise-claim"
    ]
}

enum EvaluationReader {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-evaluation/inspection.json")

    static func load(from url: URL = defaultURL) throws -> EvaluationProjection {
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        try EvaluationShape.validate(raw)
        if EvaluationPrivacy.containsProhibitedTree(raw) { throw EvaluationContractError.prohibitedMaterial }
        guard let object = raw as? [String: Any], let suppliedDigest = object["contentDigest"] as? String,
              suppliedDigest == (try contentDigest(for: object)) else { throw EvaluationContractError.invalidContentDigest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvaluationProjection.self, from: data)
    }

    static func contentDigest(for object: [String: Any]) throws -> String {
        var canonical = object
        canonical.removeValue(forKey: "contentDigest")
        canonical.removeValue(forKey: "projectionID")
        let data = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys, .withoutEscapingSlashes])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum EvaluationReadbackWriter {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-evaluation/readback.json")

    static func write(_ readback: EvaluationReadback, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(readback).write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum EvaluationDisplayState: Equatable {
    case current
    case staleLastValid
    case unavailable

    static func resolve(latest: EvaluationProjection?, validation: EvaluationProjectionValidation?, hasLastValid: Bool) -> Self {
        if latest != nil, validation == .current { return .current }
        return hasLastValid ? .staleLastValid : .unavailable
    }
}

enum EvaluationContractError: LocalizedError {
    case malformedShape(String)
    case invalidContentDigest
    case prohibitedMaterial

    var errorDescription: String? {
        switch self {
        case .malformedShape(let location): "Evaluation projection has an unsupported field shape at \(location)."
        case .invalidContentDigest: "Evaluation projection failed its content-integrity check."
        case .prohibitedMaterial: "Evaluation projection contains material that is not permitted in Command Center."
        }
    }
}

private struct EvaluationSemanticVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let base = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let components = base.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! } + Array(repeating: 0, count: 3 - components.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

private enum EvaluationPrivacy {
    static func isOpaqueIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._:-]{2,160}$"#, options: .regularExpression) != nil
    }
    static func containsProhibited(_ value: String) -> Bool {
        ["http://", "https://", "file://", "/Users/", "/Volumes/", "Bearer "].contains(where: value.localizedCaseInsensitiveContains)
            || value.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil
            || value.range(of: #"(?i)\b(?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*[^\s,;]+"#, options: .regularExpression) != nil
    }
    static func containsProhibitedTree(_ value: Any) -> Bool {
        if let value = value as? String { return containsProhibited(value) }
        if let values = value as? [Any] { return values.contains(where: containsProhibitedTree) }
        if let values = value as? [String: Any] { return values.values.contains(where: containsProhibitedTree) }
        return false
    }
}

private enum EvaluationShape {
    private static let top = Set(["schemaVersion", "projectionID", "contentDigest", "generatedAt", "validUntil", "producer", "audience", "releaseCandidate", "suite", "caseCoverage", "gateResults", "connectorDecisions", "pilot", "enterpriseClaim", "evidence", "coverage"])

    static func validate(_ value: Any) throws {
        guard let object = value as? [String: Any], Set(object.keys) == top else { throw EvaluationContractError.malformedShape("root") }
        try exact(object["releaseCandidate"], at: "releaseCandidate", keys: ["releaseID", "pluginVersion", "pluginCommit", "appVersion", "appBuild", "appCommit", "minimumPluginVersion", "maximumPluginVersionExclusive", "minimumAppVersion", "maximumAppVersionExclusive", "compatibilityStatus"])
        try exact(object["suite"], at: "suite", keys: ["suiteID", "suiteVersion", "suiteDigest", "requiredCaseCount"])
        try array(object["caseCoverage"], at: "caseCoverage", keys: ["caseID", "category", "severity", "result", "releaseBlocking", "requirementIDs", "evidenceIDs"])
        try array(object["gateResults"], at: "gateResults", keys: ["gateID", "status", "evaluatedAt", "reasonCodes", "evidenceIDs"])
        try array(object["connectorDecisions"], at: "connectorDecisions", keys: ["connectorID", "tier", "status", "route", "sourceID", "authenticationState", "coverageState", "itemCount", "processedCount", "unresolvedCount", "readOnly", "approvalState", "evidenceIDs"])
        try exact(object["pilot"], at: "pilot", keys: ["pilotID", "status", "cohort", "timezone", "plannedBusinessDays", "plannedCheckpoints", "attemptedCheckpoints", "unattendedRolloversPlanned", "unattendedRolloversCompleted", "tier1AttemptsPlanned", "tier1AttemptsRecorded", "manualInterventionCount", "disposition", "evidenceIDs"])
        try exact(object["enterpriseClaim"], at: "enterpriseClaim", keys: ["status", "claimAllowed", "scope", "safeStatement", "unmetRequirementIDs"])
        try array(object["evidence"], at: "evidence", keys: ["evidenceID", "kind", "status", "observedAt", "safeSummary"])
        try exact(object["coverage"], at: "coverage", keys: ["caseCount", "gateCount", "connectorCount", "evidenceCount", "passedCaseCount", "failedCaseCount", "blockedCaseCount", "skippedCaseCount", "notRunCaseCount", "releaseBlockingCount", "releaseBlockingPassedCount", "unresolvedCount"])
    }

    private static func array(_ value: Any?, at location: String, keys: Set<String>) throws {
        guard let values = value as? [Any] else { throw EvaluationContractError.malformedShape(location) }
        for (index, value) in values.enumerated() { try exact(value, at: "\(location)[\(index)]", keys: keys) }
    }
    private static func exact(_ value: Any?, at location: String, keys: Set<String>) throws {
        guard let value = value as? [String: Any], Set(value.keys) == keys else { throw EvaluationContractError.malformedShape(location) }
    }
}
