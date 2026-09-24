import Foundation

struct TwinInspectionProjection: Decodable {
    let schemaVersion: Int
    let projectionID: String
    let contentDigest: String
    let generatedAt: Date
    let validUntil: Date
    let producer: String
    let audience: String
    let contractAudit: TwinContractAudit
    let promises: [TwinPromise]
    let authoritySources: [TwinAuthoritySource]
    let authorityRecords: [TwinAuthorityRecord]
    let records: [TwinInspectionRecord]
    let governanceEvents: [TwinGovernanceEvent]
    let optOuts: TwinOptOuts
    let playbooks: [TwinPlaybook]
    let coverage: TwinCoverage

    func validation(now: Date = .now) -> TwinProjectionValidation {
        guard schemaVersion == 1 else { return .unsupportedSchema(schemaVersion) }
        guard !projectionID.isEmpty else { return .missingProjectionIdentifier }
        guard contentDigest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return .invalidContentDigest }
        guard generatedAt <= validUntil, validUntil > now else { return .expired(validUntil) }
        guard audience == "Chris-private-local" else { return .invalidAudience }
        guard Set(promises.map(\.id)).count == promises.count else { return .duplicateIdentifier("promise") }
        guard Set(authoritySources.map(\.id)).count == authoritySources.count else { return .duplicateIdentifier("authority source") }
        guard Set(authorityRecords.map(\.id)).count == authorityRecords.count else { return .duplicateIdentifier("authority record") }
        guard Set(records.map(\.recordID)).count == records.count else { return .duplicateIdentifier("Twin record") }
        guard coverage.professionalCount == records.filter({ $0.domain == "professional" }).count,
              coverage.personalCount == records.filter({ $0.domain == "personal" }).count else { return .denominatorMismatch }
        for record in records {
            guard ["professional", "personal"].contains(record.domain) else { return .invalidDomain(record.recordID) }
            if record.domain == "personal", record.statement != nil { return .personalStatementExposed(record.recordID) }
            if record.containsProhibitedMaterial { return .prohibitedMaterial(record.recordID) }
        }
        for event in governanceEvents where event.containsProhibitedMaterial {
            return .prohibitedMaterial(event.eventID)
        }
        for playbook in playbooks where playbook.containsProhibitedMaterial {
            return .prohibitedMaterial(playbook.id)
        }
        return .current
    }

    func readback(consumer: String, appVersion: String, displayedAt: Date = .now) -> TwinInspectionReadback? {
        guard validation(now: displayedAt) == .current else { return nil }
        return TwinInspectionReadback(
            schemaVersion: 1,
            projectionID: projectionID,
            projectionSchemaVersion: schemaVersion,
            contentDigest: contentDigest,
            consumer: consumer,
            appVersion: appVersion,
            displayedAt: displayedAt,
            state: "displayed",
            viewIDs: ["digital-twin"]
        )
    }
}

enum TwinProjectionValidation: Equatable {
    case current
    case unsupportedSchema(Int)
    case missingProjectionIdentifier
    case invalidContentDigest
    case expired(Date)
    case invalidAudience
    case duplicateIdentifier(String)
    case denominatorMismatch
    case invalidDomain(String)
    case personalStatementExposed(String)
    case prohibitedMaterial(String)
}

struct TwinContractAudit: Decodable {
    let status: String
    let promiseCount: Int
    let implementedPromiseCount: Int
    let sourceCount: Int
    let recordCount: Int
    let errors: [String]
    let auditedAt: Date
}

struct TwinPromise: Decodable, Identifiable {
    let id: String
    let promise: String
    let owner: String
    let control: String
    let status: String
}

struct TwinAuthoritySource: Decodable, Identifiable {
    let id: String
    let domain: String
    let role: String
    let suitableFor: [String]
    let notProofOf: [String]
    let authoritativeRecord: String
    let owner: String
    let allowedTwinDomains: [String]
    let retention: String
    let conflictRule: String
}

struct TwinAuthorityRecord: Decodable, Identifiable {
    let id: String
    let domain: String
    let owner: String
    let allowedIngress: [String]
    let allowedEgress: [String]
    let prohibitedEgress: [String]
    let audience: String
    let retention: String
}

struct TwinInspectionRecord: Decodable, Identifiable {
    var id: String { recordID }
    let recordID: String
    let domain: String
    let recordType: String
    let statement: String?
    let status: String
    let version: Int
    let evidenceClass: String
    let confidence: Double
    let sensitivity: String
    let purpose: String
    let updatedAt: Date
    let reviewAt: Date
    let sourceIDs: [String]
    let evidenceCount: Int
    let contradictionCount: Int
    let supersedes: String?

    var containsProhibitedMaterial: Bool {
        TwinProjectionPrivacy.containsProhibited([statement, purpose, supersedes].compactMap { $0 } + sourceIDs)
    }
}

struct TwinGovernanceEvent: Decodable, Identifiable {
    var id: String { eventID }
    let eventID: String
    let occurredAt: Date
    let action: String
    let domain: String
    let recordID: String
    let reason: String
    let beforeVersion: Int?
    let afterVersion: Int?
    let result: String

    var containsProhibitedMaterial: Bool {
        reason != "Withheld from privacy-reduced projection." || TwinProjectionPrivacy.containsProhibited([reason])
    }
}

struct TwinOptOuts: Decodable {
    let schemaVersion: Int
    let global: Bool
    let domains: [String]
    let sources: [String]
    let recordTypes: [String]
    let updatedAt: Date?
}

struct TwinPlaybook: Decodable, Identifiable {
    var id: String { playbookID ?? title ?? "unknown-playbook" }
    let playbookID: String?
    let title: String?
    let state: String?
    let updatedAt: Date?
    let audience: String?
    let qaVerdict: String?
    let packageDigest: String?

    var containsProhibitedMaterial: Bool {
        TwinProjectionPrivacy.containsProhibited([title, audience].compactMap { $0 })
    }
}

private enum TwinProjectionPrivacy {
    static func containsProhibited(_ values: [String]) -> Bool {
        let prohibited = ["http://", "https://", "file://", "/Users/", "/Volumes/", "Bearer "]
        return values.contains { value in
            prohibited.contains(where: value.localizedCaseInsensitiveContains)
                || value.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil
                || value.range(of: #"(?i)\b(?:api[_-]?key|password|passwd|secret|token)\s*[:=]\s*[^\s,;]+"#, options: .regularExpression) != nil
        }
    }
}

struct TwinCoverage: Decodable {
    let professionalCount: Int
    let personalCount: Int
    let governanceEventCount: Int
    let promiseCount: Int
    let implementedPromiseCount: Int
    let unresolvedCount: Int
}

struct TwinInspectionReadback: Codable, Equatable {
    let schemaVersion: Int
    let projectionID: String
    let projectionSchemaVersion: Int
    let contentDigest: String
    let consumer: String
    let appVersion: String
    let displayedAt: Date
    let state: String
    let viewIDs: [String]
}

enum TwinInspectionReader {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-twin/inspection.json")

    static func load(from url: URL = defaultURL) throws -> TwinInspectionProjection {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TwinInspectionProjection.self, from: data)
    }
}

enum TwinInspectionReadbackWriter {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-twin/readback.json")

    static func write(_ readback: TwinInspectionReadback, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(readback).write(to: url, options: [.atomic])
    }
}
