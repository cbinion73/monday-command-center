import Foundation

enum PlannerDayRollover {
    static func selection(
        current: Date,
        now: Date,
        followsToday: Bool,
        timezoneID: String = "America/New_York"
    ) -> Date {
        guard followsToday else { return current }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneID) ?? .current
        return calendar.startOfDay(for: now)
    }
}

/// Versioned read-only projection produced by the consolidated MONDAY plugin.
/// Command Center is a cockpit. Vaults and governed ledgers remain authoritative.
struct DailyPlannerPlan: Decodable {
    let schemaVersion: Int?
    let planID: String?
    let date: String
    let generatedAt: Date
    let validUntil: Date?
    let timezone: String
    let sources: [PlannerSource]
    let coverage: PlannerCoverage?
    let primaryFocus: String
    let schedule: [PlannerScheduleItem]
    let priorities: PlannerPriorities
    let notes: [String]
    let compass: [PlannerCompassItem]
    let brief: PlannerBrief?
    let publication: PlannerPublication?

    func validation(expectedDate: String, now: Date = .now, enforceFreshness: Bool) -> PlannerValidation {
        if let schemaVersion, schemaVersion > 3 { return .unsupportedSchema(schemaVersion) }
        guard date == expectedDate else { return .wrongDate(expected: expectedDate, actual: date) }
        if enforceFreshness, let validUntil, validUntil <= now { return .expired(validUntil) }
        if schemaVersion == 3, planID?.isEmpty != false { return .missingPlanIdentifier }
        return .current
    }

    func readback(consumer: String, appVersion: String, consumedAt: Date = .now) -> CommandCenterReadback? {
        guard let planID, !planID.isEmpty, let schemaVersion else { return nil }
        return CommandCenterReadback(
            schemaVersion: 1,
            planID: planID,
            planSchemaVersion: schemaVersion,
            consumer: consumer,
            appVersion: appVersion,
            consumedAt: consumedAt,
            state: "displayed"
        )
    }
}

enum PlannerValidation: Equatable {
    case current
    case unsupportedSchema(Int)
    case wrongDate(expected: String, actual: String)
    case expired(Date)
    case missingPlanIdentifier
}

struct PlannerSource: Decodable, Identifiable {
    var id: String { "\(kind):\(name)" }
    let kind: String
    let name: String
    let status: String
    let fetchedAt: Date
    let attemptedAt: Date?
    let succeededAt: Date?
    let itemCount: Int?
    let processedCount: Int?
    let unresolvedCount: Int?
    let detail: String?
    let error: String?
}

struct PlannerCoverage: Decodable {
    let status: String
    let sources: [PlannerSource]
    let unresolved: [String]
}

struct PlannerScheduleItem: Decodable {
    let time: String
    let end: String
    let title: String
}

struct PlannerPriorities: Decodable {
    let a: [String]
    let b: [String]
    let c: [String]
}

struct PlannerCompassItem: Decodable {
    let role: String
    let goal: String
}

struct PlannerPortfolioItem: Decodable, Identifiable {
    let id: String?
    let title: String
    let status: String
    let outcome: String?
    let nextAction: String?
    let owner: String?
    let updated: String
    let reviewDate: String?
    let evidenceStatus: String?
    let path: String?

    var stableID: String { id ?? path ?? title }
}

struct PlannerMeetingContinuity: Decodable {
    let ledger: String
    let occurrenceCount: Int
    let unresolvedCount: Int
    let byStatus: [String: Int]
}

struct PlannerActivitySummary: Decodable {
    let path: String
    let recordCount: Int
}

struct PlannerOperationsSummary: Decodable {
    let path: String
    let receiptCount: Int
}

struct PlannerBrief: Decodable {
    let mission: String
    let pullForwards: [String]
    let risks: [String]
    let workPortfolio: [PlannerPortfolioItem]
    let personalPortfolio: [PlannerPortfolioItem]
    let decisions: [PlannerPortfolioItem]?
    let meetingContinuity: PlannerMeetingContinuity?
    let activityLedger: PlannerActivitySummary?
    let operations: PlannerOperationsSummary?
    let sourceHealth: [PlannerSource]
}

struct PlannerPublication: Decodable {
    let producer: String
    let contractVersion: Int
    let state: String
}

struct CommandCenterReadback: Codable, Equatable {
    let schemaVersion: Int
    let planID: String
    let planSchemaVersion: Int
    let consumer: String
    let appVersion: String
    let consumedAt: Date
    let state: String
}

private struct PlannerAPIResponse: Decodable {
    let status: String
    let plan: DailyPlannerPlan?
}

enum PlannerFeedReader {
    static func load(from url: URL) throws -> DailyPlannerPlan {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let response = try? decoder.decode(PlannerAPIResponse.self, from: data), let plan = response.plan {
            return plan
        }
        return try decoder.decode(DailyPlannerPlan.self, from: data)
    }
}

enum PlannerContractError: LocalizedError {
    case unsupportedSchema(Int)
    case wrongDate(expected: String, actual: String)
    case expired(Date)
    case missingPlanIdentifier

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            "The plan uses unsupported schema version \(schema). Update Command Center before displaying it."
        case .wrongDate(let expected, let actual):
            "The available plan is for \(actual), not \(expected). Rebuild the requested plan."
        case .expired:
            "Today's plan has expired. Rebuild it before relying on Command Center."
        case .missingPlanIdentifier:
            "The plan is missing its verification identifier and was not displayed."
        }
    }
}

enum CommandCenterReadbackWriter {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/monday-planner/readback.json")

    static func write(_ readback: CommandCenterReadback, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(readback).write(to: url, options: [.atomic])
    }
}
