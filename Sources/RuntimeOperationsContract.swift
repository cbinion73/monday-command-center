import CryptoKit
import Foundation

struct RuntimeOperationsProjection: Decodable {
    let schemaVersion: Int
    let projectionID: String
    let contentDigest: String
    let generatedAt: Date
    let validUntil: Date
    let producer: String
    let audience: String
    let runtimeVersion: String
    let workflows: [RuntimeWorkflow]
    let retries: [RuntimeRetry]
    let deadLetters: [RuntimeDeadLetter]
    let externalActions: [RuntimeExternalAction]
    let commitments: [RuntimeCommitment]
    let decisions: [RuntimeDecision]
    let sources: [RuntimeSourceHealth]
    let connections: [RuntimeConnection]
    let compatibility: RuntimeCompatibility
    let migrations: [RuntimeMigration]
    let alerts: [RuntimeAlert]
    let recoveryInstructions: [RuntimeRecoveryInstruction]
    let coverage: RuntimeCoverage

    func validation(appVersion: String, now: Date = .now) -> RuntimeProjectionValidation {
        guard schemaVersion == 2 else { return .unsupportedSchema(schemaVersion) }
        guard projectionID.range(of: #"^runtime-[a-zA-Z0-9._-]{8,160}$"#, options: .regularExpression) != nil else { return .missingProjectionIdentifier }
        guard contentDigest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              projectionID.hasSuffix(String(contentDigest.prefix(12))) else { return .invalidContentDigest }
        guard generatedAt <= validUntil, validUntil > now else { return .expired(validUntil) }
        guard producer == "monday-runtime", audience == "Chris-private-local" else { return .invalidProducerOrAudience }
        guard !runtimeVersion.isEmpty, !RuntimeProjectionPrivacy.containsProhibited([runtimeVersion]) else { return .prohibitedMaterial("runtimeVersion") }

        let identifierGroups: [(String, [String])] = [
            ("workflow", workflows.map(\.workflowID)),
            ("retry", retries.map(\.retryID)),
            ("dead letter", deadLetters.map(\.deadLetterID)),
            ("external action", externalActions.map(\.actionID)),
            ("commitment", commitments.map(\.commitmentID)),
            ("decision", decisions.map(\.decisionID)),
            ("source", sources.map(\.sourceID)),
            ("connection", connections.map(\.connectionID)),
            ("migration", migrations.map(\.migrationID)),
            ("alert", alerts.map(\.alertID)),
            ("recovery instruction", recoveryInstructions.map(\.instructionID))
        ]
        for (label, values) in identifierGroups where Set(values).count != values.count {
            return .duplicateIdentifier(label)
        }

        let workflowsByID = Dictionary(uniqueKeysWithValues: workflows.map { ($0.workflowID, $0) })
        let instructionIDs = Set(recoveryInstructions.map(\.instructionID))
        let commitmentIDs = Set(commitments.map(\.commitmentID))
        let decisionIDs = Set(decisions.map(\.decisionID))
        let sourceIDs = Set(sources.map(\.sourceID))
        for workflow in workflows {
            guard workflow.isValid else { return .invalidWorkflow(workflow.workflowID) }
            if workflow.containsProhibitedMaterial { return .prohibitedMaterial(workflow.workflowID) }
        }
        for retry in retries {
            guard let workflow = workflowsByID[retry.workflowID], retry.isValid,
                  ["waiting", "retrying"].contains(workflow.state),
                  retry.attemptNumber <= workflow.attemptCount else { return .orphanReference(retry.retryID) }
            if retry.containsProhibitedMaterial { return .prohibitedMaterial(retry.retryID) }
        }
        for deadLetter in deadLetters {
            guard let workflow = workflowsByID[deadLetter.workflowID], workflow.state == "dead-lettered",
                  instructionIDs.contains(deadLetter.recoveryInstructionID), deadLetter.isValid else { return .orphanReference(deadLetter.deadLetterID) }
            if deadLetter.containsProhibitedMaterial { return .prohibitedMaterial(deadLetter.deadLetterID) }
        }
        for action in externalActions {
            guard action.isValid else { return .invalidExternalAction(action.actionID) }
            if action.containsProhibitedMaterial { return .prohibitedMaterial(action.actionID) }
        }
        for commitment in commitments {
            guard commitment.isValid, Set(commitment.decisionIDs).isSubset(of: decisionIDs) else { return .orphanReference(commitment.commitmentID) }
            if commitment.containsProhibitedMaterial { return .prohibitedMaterial(commitment.commitmentID) }
        }
        for decision in decisions {
            guard decision.isValid, Set(decision.commitmentIDs).isSubset(of: commitmentIDs) else { return .orphanReference(decision.decisionID) }
            if decision.containsProhibitedMaterial { return .prohibitedMaterial(decision.decisionID) }
        }
        for source in sources {
            guard source.isValid else { return .invalidSource(source.sourceID) }
            if source.containsProhibitedMaterial { return .prohibitedMaterial(source.sourceID) }
        }
        for connection in connections {
            guard connection.isValid, sourceIDs.contains(connection.sourceID) else { return .orphanReference(connection.connectionID) }
            if connection.containsProhibitedMaterial { return .prohibitedMaterial(connection.connectionID) }
        }
        guard compatibility.isValid(appVersion: appVersion) else { return .incompatibleApp(compatibility.minimumAppVersion) }
        if compatibility.containsProhibitedMaterial { return .prohibitedMaterial("compatibility") }
        for migration in migrations {
            guard migration.isValid else { return .invalidMigration(migration.migrationID) }
            if migration.containsProhibitedMaterial { return .prohibitedMaterial(migration.migrationID) }
        }
        for alert in alerts {
            guard alert.isValid, Set(alert.recoveryInstructionIDs).isSubset(of: instructionIDs) else { return .orphanReference(alert.alertID) }
            if alert.containsProhibitedMaterial { return .prohibitedMaterial(alert.alertID) }
        }
        for instruction in recoveryInstructions {
            guard instruction.isValid else { return .invalidRecoveryInstruction(instruction.instructionID) }
            if instruction.containsProhibitedMaterial { return .prohibitedMaterial(instruction.instructionID) }
        }
        guard coverage.workflowCount == workflows.count,
              coverage.retryCount == retries.count,
              coverage.deadLetterCount == deadLetters.count,
              coverage.externalActionCount == externalActions.count,
              coverage.commitmentCount == commitments.count,
              coverage.decisionCount == decisions.count,
              coverage.sourceCount == sources.count,
              coverage.connectionCount == connections.count,
              coverage.migrationCount == migrations.count,
              coverage.alertCount == alerts.count,
              coverage.recoveryInstructionCount == recoveryInstructions.count,
              coverage.unresolvedCount >= 0 else {
            return .denominatorMismatch
        }
        return .current
    }

    func readback(viewID: String, consumer: String, appVersion: String, displayedAt: Date = .now) -> RuntimeOperationsReadback? {
        guard validation(appVersion: appVersion, now: displayedAt) == .current,
              RuntimeOperationsReadback.allowedViewIDs.contains(viewID) else { return nil }
        return RuntimeOperationsReadback(
            schemaVersion: 1,
            projectionID: projectionID,
            projectionSchemaVersion: schemaVersion,
            contentDigest: contentDigest,
            consumer: consumer,
            appVersion: appVersion,
            displayedAt: displayedAt,
            state: "displayed",
            viewIDs: [viewID]
        )
    }
}

enum RuntimeProjectionValidation: Equatable {
    case current
    case unsupportedSchema(Int)
    case missingProjectionIdentifier
    case invalidContentDigest
    case expired(Date)
    case invalidProducerOrAudience
    case duplicateIdentifier(String)
    case invalidWorkflow(String)
    case invalidExternalAction(String)
    case invalidSource(String)
    case invalidMigration(String)
    case invalidRecoveryInstruction(String)
    case orphanReference(String)
    case incompatibleApp(String)
    case denominatorMismatch
    case prohibitedMaterial(String)
    case malformedShape(String)
}

struct RuntimeWorkflow: Decodable, Identifiable {
    var id: String { workflowID }
    let workflowID: String
    let kind: String
    let state: String
    let attemptCount: Int
    let maxAttempts: Int
    let idempotencyKey: String
    let updatedAt: Date
    let startedAt: Date?
    let nextAttemptAt: Date?
    let checkpoint: String?
    let errorCode: String?

    var isValid: Bool {
        ["queued", "running", "waiting", "retrying", "succeeded", "failed", "dead-lettered", "cancelled"].contains(state)
            && attemptCount >= 0 && maxAttempts >= 1 && attemptCount <= maxAttempts
            && RuntimeProjectionPrivacy.isOpaqueIdentifier(workflowID)
            && RuntimeProjectionPrivacy.isOpaqueIdentifier(idempotencyKey)
            && (state == "retrying" ? nextAttemptAt != nil : true)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([workflowID, kind, idempotencyKey, checkpoint, errorCode].compactMap { $0 }) }
}

struct RuntimeRetry: Decodable, Identifiable {
    var id: String { retryID }
    let retryID: String
    let workflowID: String
    let attemptNumber: Int
    let state: String
    let reasonCode: String
    let scheduledAt: Date
    let backoffSeconds: Int

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(retryID) && attemptNumber >= 1 && backoffSeconds >= 0
            && ["scheduled", "running", "succeeded", "exhausted", "cancelled"].contains(state)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([retryID, workflowID, reasonCode]) }
}

struct RuntimeDeadLetter: Decodable, Identifiable {
    var id: String { deadLetterID }
    let deadLetterID: String
    let workflowID: String
    let createdAt: Date
    let reasonCode: String
    let attemptCount: Int
    let replayEligibility: String
    let recoveryInstructionID: String

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(deadLetterID) && attemptCount >= 1
            && ["eligible", "blocked", "requires-review"].contains(replayEligibility)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([deadLetterID, workflowID, reasonCode, recoveryInstructionID]) }
}

struct RuntimeExternalAction: Decodable, Identifiable {
    var id: String { actionID }
    let actionID: String
    let kind: String
    let targetLabel: String
    let state: String
    let confirmationRequired: Bool
    let confirmedAt: Date?
    let attemptedAt: Date?
    let verifiedAt: Date?
    let readbackStatus: String
    let retrySafe: Bool

    var isValid: Bool {
        guard RuntimeProjectionPrivacy.isOpaqueIdentifier(actionID),
              ["confirmation-required", "confirmed", "attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate", "cancelled"].contains(state),
              ["missing", "matched", "indeterminate"].contains(readbackStatus),
              confirmationRequired == ["confirmation-required", "failed-before-dispatch"].contains(state),
              !retrySafe || state == "failed-before-dispatch" else { return false }
        if ["confirmed", "attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate"].contains(state) && confirmedAt == nil { return false }
        if ["attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate"].contains(state) && attemptedAt == nil { return false }
        if state == "verified" && readbackStatus != "matched" { return false }
        if state == "failed-before-dispatch" && !["missing", "matched"].contains(readbackStatus) { return false }
        if state == "indeterminate" && readbackStatus != "indeterminate" { return false }
        if ["confirmation-required", "confirmed", "attempting", "attempted", "cancelled"].contains(state) && readbackStatus != "missing" { return false }
        if state == "verified" && verifiedAt == nil { return false }
        if state != "verified" && verifiedAt != nil { return false }
        if let confirmedAt, let attemptedAt, attemptedAt < confirmedAt { return false }
        if let attemptedAt, let verifiedAt, verifiedAt < attemptedAt { return false }
        return true
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([actionID, kind, targetLabel, state, readbackStatus]) }
}

struct RuntimeCommitment: Decodable, Identifiable {
    var id: String { commitmentID }
    let commitmentID: String
    let title: String
    let state: String
    let ownerLabel: String
    let dueAt: Date?
    let consequence: String
    let evidenceStatus: String
    let decisionIDs: [String]

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(commitmentID)
            && ["proposed", "active", "fulfilled", "renegotiation-needed", "closed", "cancelled"].contains(state)
            && ["unknown", "reported", "supported", "validated"].contains(evidenceStatus)
            && !title.isEmpty && !ownerLabel.isEmpty
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([commitmentID, title, state, ownerLabel, consequence, evidenceStatus] + decisionIDs) }
}

struct RuntimeDecision: Decodable, Identifiable {
    var id: String { decisionID }
    let decisionID: String
    let title: String
    let state: String
    let ownerLabel: String
    let decidedAt: Date?
    let evidenceStatus: String
    let commitmentIDs: [String]

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(decisionID)
            && ["proposed", "pending", "decided", "superseded", "withdrawn"].contains(state)
            && ["unknown", "reported", "supported", "validated"].contains(evidenceStatus)
            && !title.isEmpty && !ownerLabel.isEmpty
            && (state == "decided" ? decidedAt != nil : true)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([decisionID, title, state, ownerLabel, evidenceStatus] + commitmentIDs) }
}

struct RuntimeSourceHealth: Decodable, Identifiable {
    var id: String { sourceID }
    let sourceID: String
    let status: String
    let scopeLabel: String
    let attemptedAt: Date?
    let succeededAt: Date?
    let itemCount: Int
    let processedCount: Int
    let unresolvedCount: Int
    let freshness: String
    let errorCode: String?

    var isValid: Bool {
        guard RuntimeProjectionPrivacy.isOpaqueIdentifier(sourceID),
              ["available", "empty", "partial", "stale", "blocked", "unavailable", "unknown"].contains(status),
              ["fresh", "aging", "stale", "unknown"].contains(freshness),
              itemCount >= 0, processedCount >= 0, unresolvedCount >= 0,
              processedCount <= itemCount, unresolvedCount <= itemCount,
              processedCount + unresolvedCount <= itemCount else { return false }
        if status == "available" { return succeededAt != nil && unresolvedCount == 0 && itemCount == processedCount }
        if status == "empty" { return succeededAt != nil && itemCount == 0 && processedCount == 0 && unresolvedCount == 0 }
        return true
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([sourceID, status, scopeLabel, freshness, errorCode].compactMap { $0 }) }
}

struct RuntimeConnection: Decodable, Identifiable {
    var id: String { connectionID }
    let connectionID: String
    let sourceID: String
    let status: String
    let authenticationState: String
    let coverageState: String
    let lastCheckedAt: Date
    let diagnosticCodes: [String]

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(connectionID)
            && ["connected", "disconnected", "blocked", "unknown"].contains(status)
            && ["authenticated", "expired", "missing", "unknown"].contains(authenticationState)
            && ["not-attempted", "empty", "partial", "complete", "blocked", "unknown"].contains(coverageState)
            && !(authenticationState != "authenticated" && coverageState == "complete")
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([connectionID, sourceID, status, authenticationState, coverageState] + diagnosticCodes) }
}

struct RuntimeCompatibility: Decodable {
    let projectionSchemaVersion: Int
    let pluginVersion: String
    let capabilityVersion: String
    let databaseSchemaVersion: Int
    let readbackSchemaVersion: Int
    let minimumAppVersion: String
    let maximumAppVersion: String?
    let status: String
    let issueCodes: [String]
    let upgradePolicy: String
    let downgradePolicy: String
    let rollbackPolicy: String

    func isValid(appVersion: String) -> Bool {
        guard projectionSchemaVersion == 2, databaseSchemaVersion == 2, readbackSchemaVersion == 1,
              capabilityVersion == "2.0.0", MondayPluginVersion(pluginVersion) != nil,
              ["compatible", "update-required", "migration-required", "incompatible"].contains(status),
              RuntimeSemanticVersion(appVersion) != nil,
              let minimum = RuntimeSemanticVersion(minimumAppVersion),
              let maximumAppVersion, let maximum = RuntimeSemanticVersion(maximumAppVersion),
              let current = RuntimeSemanticVersion(appVersion), current >= minimum, current < maximum,
              !upgradePolicy.isEmpty, !downgradePolicy.isEmpty, !rollbackPolicy.isEmpty else { return false }
        return status == "compatible" || status == "migration-required"
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([pluginVersion, capabilityVersion, minimumAppVersion, maximumAppVersion, status, upgradePolicy, downgradePolicy, rollbackPolicy].compactMap { $0 } + issueCodes) }
}

struct RuntimeMigration: Decodable, Identifiable {
    var id: String { migrationID }
    let migrationID: String
    let fromVersion: String
    let toVersion: String
    let state: String
    let reversible: Bool
    let appliedAt: Date?
    let safeSummary: String

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(migrationID)
            && RuntimeSemanticVersion(fromVersion) != nil && RuntimeSemanticVersion(toVersion) != nil
            && ["planned", "in-progress", "applied", "failed", "rolled-back"].contains(state)
            && (state == "applied" ? appliedAt != nil : true)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([migrationID, fromVersion, toVersion, state, safeSummary]) }
}

struct RuntimeAlert: Decodable, Identifiable {
    var id: String { alertID }
    let alertID: String
    let severity: String
    let category: String
    let state: String
    let title: String
    let safeSummary: String
    let raisedAt: Date
    let firstSeen: Date
    let lastSeen: Date
    let count: Int
    let status: String
    let acknowledgedAt: Date?
    let suppressedUntil: Date?
    let resolvedAt: Date?
    let sourceKind: String
    let evidenceIDs: [String]
    let recoveryInstructionIDs: [String]

    var isValid: Bool {
        guard RuntimeProjectionPrivacy.isOpaqueIdentifier(alertID)
            && ["info", "warning", "error", "critical"].contains(severity)
            && ["open", "acknowledged", "resolved"].contains(state)
            && ["open", "acknowledged", "resolved"].contains(status)
            && ["runtime-derived", "external-monitor"].contains(sourceKind)
            && state == status && count >= 1 && firstSeen <= lastSeen && raisedAt == firstSeen else { return false }
        if status == "open" && (acknowledgedAt != nil || resolvedAt != nil) { return false }
        if status == "acknowledged" && (acknowledgedAt == nil || resolvedAt != nil) { return false }
        if status == "resolved" && resolvedAt == nil { return false }
        if let acknowledgedAt, acknowledgedAt < firstSeen { return false }
        if let resolvedAt, resolvedAt < firstSeen { return false }
        if let suppressedUntil, suppressedUntil < firstSeen { return false }
        return true
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([alertID, severity, category, state, title, safeSummary, status, sourceKind] + evidenceIDs + recoveryInstructionIDs) }
}

struct RuntimeRecoveryInstruction: Decodable, Identifiable {
    var id: String { instructionID }
    let instructionID: String
    let title: String
    let steps: [String]
    let verificationSteps: [String]
    let rollbackSteps: [String]
    let actionBoundary: String
    let relatedIDs: [String]
    let evidenceIDs: [String]

    var isValid: Bool {
        RuntimeProjectionPrivacy.isOpaqueIdentifier(instructionID) && !steps.isEmpty && steps.count <= 12
            && !verificationSteps.isEmpty && verificationSteps.count <= 12 && rollbackSteps.count <= 12
            && ["local-read-only", "local-governed", "requires-confirmation"].contains(actionBoundary)
    }
    var containsProhibitedMaterial: Bool { RuntimeProjectionPrivacy.containsProhibited([instructionID, title, actionBoundary] + steps + verificationSteps + rollbackSteps + relatedIDs + evidenceIDs) }
}

struct RuntimeCoverage: Decodable {
    let workflowCount: Int
    let retryCount: Int
    let deadLetterCount: Int
    let externalActionCount: Int
    let commitmentCount: Int
    let decisionCount: Int
    let sourceCount: Int
    let connectionCount: Int
    let migrationCount: Int
    let alertCount: Int
    let recoveryInstructionCount: Int
    let unresolvedCount: Int
}

struct RuntimeOperationsReadback: Codable, Equatable {
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
        "operations-overview",
        "operations-workflows-dead-letters",
        "operations-external-actions",
        "operations-commitments-decisions",
        "operations-source-health",
        "operations-connections",
        "operations-compatibility-migrations",
        "operations-alerts-recovery"
    ]
}

enum RuntimeOperationsReader {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-runtime/operations.json")

    static func load(from url: URL = defaultURL) throws -> RuntimeOperationsProjection {
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        try RuntimeProjectionShape.validate(raw)
        if RuntimeProjectionPrivacy.containsProhibitedTree(raw) { throw RuntimeOperationsContractError.prohibitedMaterial }
        guard let object = raw as? [String: Any],
              let suppliedDigest = object["contentDigest"] as? String else {
            throw RuntimeOperationsContractError.invalidContentDigest
        }
        let calculatedDigest = try contentDigest(for: object)
        guard suppliedDigest == calculatedDigest else { throw RuntimeOperationsContractError.invalidContentDigest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuntimeOperationsProjection.self, from: data)
    }

    /// SHA-256 of compact, sorted-key JSON after removing the digest and its
    /// digest-derived projection identifier. This is intentionally simple so
    /// the plugin publisher can reproduce the same bytes exactly.
    static func contentDigest(for object: [String: Any]) throws -> String {
        var canonical = object
        canonical.removeValue(forKey: "contentDigest")
        canonical.removeValue(forKey: "projectionID")
        let data = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys, .withoutEscapingSlashes])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum RuntimeOperationsReadbackWriter {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-runtime/readback.json")

    static func write(_ readback: RuntimeOperationsReadback, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(readback).write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum RuntimeOperationsContractError: LocalizedError {
    case malformedShape(String)
    case invalidContentDigest
    case prohibitedMaterial

    var errorDescription: String? {
        switch self {
        case .malformedShape(let location): "Runtime operations projection has an unsupported field shape at \(location)."
        case .invalidContentDigest: "Runtime operations projection failed its content-integrity check."
        case .prohibitedMaterial: "Runtime operations projection contains material that is not permitted in Command Center."
        }
    }
}

private struct RuntimeSemanticVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! } + Array(repeating: 0, count: 3 - components.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

private enum RuntimeProjectionPrivacy {
    static func isOpaqueIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._:-]{2,160}$"#, options: .regularExpression) != nil
    }

    static func containsProhibited(_ values: [String]) -> Bool {
        values.contains { value in
            ["http://", "https://", "file://", "/Users/", "/Volumes/", "Bearer "].contains(where: value.localizedCaseInsensitiveContains)
                || value.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil
                || value.range(of: #"(?i)\b(?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*[^\s,;]+"#, options: .regularExpression) != nil
        }
    }

    static func containsProhibitedTree(_ value: Any) -> Bool {
        if let string = value as? String { return containsProhibited([string]) }
        if let values = value as? [Any] { return values.contains(where: containsProhibitedTree) }
        if let values = value as? [String: Any] { return values.values.contains(where: containsProhibitedTree) }
        return false
    }
}

private enum RuntimeProjectionShape {
    private static let top = Set(["schemaVersion", "projectionID", "contentDigest", "generatedAt", "validUntil", "producer", "audience", "runtimeVersion", "workflows", "retries", "deadLetters", "externalActions", "commitments", "decisions", "sources", "connections", "compatibility", "migrations", "alerts", "recoveryInstructions", "coverage"])

    static func validate(_ value: Any) throws {
        guard let object = value as? [String: Any], Set(object.keys) == top else { throw RuntimeOperationsContractError.malformedShape("root") }
        try validateArray(object["workflows"], at: "workflows", allowed: ["workflowID", "kind", "state", "attemptCount", "maxAttempts", "idempotencyKey", "updatedAt", "startedAt", "nextAttemptAt", "checkpoint", "errorCode"], required: ["workflowID", "kind", "state", "attemptCount", "maxAttempts", "idempotencyKey", "updatedAt"])
        try validateArray(object["retries"], at: "retries", exact: ["retryID", "workflowID", "attemptNumber", "state", "reasonCode", "scheduledAt", "backoffSeconds"])
        try validateArray(object["deadLetters"], at: "deadLetters", exact: ["deadLetterID", "workflowID", "createdAt", "reasonCode", "attemptCount", "replayEligibility", "recoveryInstructionID"])
        try validateArray(object["externalActions"], at: "externalActions", allowed: ["actionID", "kind", "targetLabel", "state", "confirmationRequired", "confirmedAt", "attemptedAt", "verifiedAt", "readbackStatus", "retrySafe"], required: ["actionID", "kind", "targetLabel", "state", "confirmationRequired", "readbackStatus", "retrySafe"])
        try validateArray(object["commitments"], at: "commitments", allowed: ["commitmentID", "title", "state", "ownerLabel", "dueAt", "consequence", "evidenceStatus", "decisionIDs"], required: ["commitmentID", "title", "state", "ownerLabel", "consequence", "evidenceStatus", "decisionIDs"])
        try validateArray(object["decisions"], at: "decisions", allowed: ["decisionID", "title", "state", "ownerLabel", "decidedAt", "evidenceStatus", "commitmentIDs"], required: ["decisionID", "title", "state", "ownerLabel", "evidenceStatus", "commitmentIDs"])
        try validateArray(object["sources"], at: "sources", allowed: ["sourceID", "status", "scopeLabel", "attemptedAt", "succeededAt", "itemCount", "processedCount", "unresolvedCount", "freshness", "errorCode"], required: ["sourceID", "status", "scopeLabel", "itemCount", "processedCount", "unresolvedCount", "freshness"])
        try validateArray(object["connections"], at: "connections", exact: ["connectionID", "sourceID", "status", "authenticationState", "coverageState", "lastCheckedAt", "diagnosticCodes"])
        try validateObject(object["compatibility"], at: "compatibility", exact: ["projectionSchemaVersion", "pluginVersion", "capabilityVersion", "databaseSchemaVersion", "readbackSchemaVersion", "minimumAppVersion", "maximumAppVersion", "status", "issueCodes", "upgradePolicy", "downgradePolicy", "rollbackPolicy"])
        try validateArray(object["migrations"], at: "migrations", allowed: ["migrationID", "fromVersion", "toVersion", "state", "reversible", "appliedAt", "safeSummary"], required: ["migrationID", "fromVersion", "toVersion", "state", "reversible", "safeSummary"])
        try validateArray(object["alerts"], at: "alerts", allowed: ["alertID", "severity", "category", "state", "title", "safeSummary", "raisedAt", "firstSeen", "lastSeen", "count", "status", "acknowledgedAt", "suppressedUntil", "resolvedAt", "sourceKind", "evidenceIDs", "recoveryInstructionIDs"], required: ["alertID", "severity", "category", "state", "title", "safeSummary", "raisedAt", "firstSeen", "lastSeen", "count", "status", "suppressedUntil", "sourceKind", "evidenceIDs", "recoveryInstructionIDs"])
        try validateArray(object["recoveryInstructions"], at: "recoveryInstructions", exact: ["instructionID", "title", "steps", "verificationSteps", "rollbackSteps", "actionBoundary", "relatedIDs", "evidenceIDs"])
        try validateObject(object["coverage"], at: "coverage", exact: ["workflowCount", "retryCount", "deadLetterCount", "externalActionCount", "commitmentCount", "decisionCount", "sourceCount", "connectionCount", "migrationCount", "alertCount", "recoveryInstructionCount", "unresolvedCount"])
    }

    private static func validateArray(_ value: Any?, at location: String, exact keys: Set<String>) throws { try validateArray(value, at: location, allowed: keys, required: keys) }
    private static func validateArray(_ value: Any?, at location: String, allowed: Set<String>, required: Set<String>) throws {
        guard let array = value as? [Any] else { throw RuntimeOperationsContractError.malformedShape(location) }
        for (index, item) in array.enumerated() { try validateObject(item, at: "\(location)[\(index)]", allowed: allowed, required: required) }
    }
    private static func validateObject(_ value: Any?, at location: String, exact keys: Set<String>) throws { try validateObject(value, at: location, allowed: keys, required: keys) }
    private static func validateObject(_ value: Any?, at location: String, allowed: Set<String>, required: Set<String>) throws {
        guard let object = value as? [String: Any], Set(object.keys).isSubset(of: allowed), required.isSubset(of: Set(object.keys)) else { throw RuntimeOperationsContractError.malformedShape(location) }
    }
}
