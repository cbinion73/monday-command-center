import XCTest
@testable import Command_Center

final class CommandCenterContractTests: XCTestCase {
    func testSchemaThreePlanRequiresIdentifier() throws {
        let plan = try decode(planID: nil, validUntil: "2026-09-24T00:00:00-04:00")
        XCTAssertEqual(
            plan.validation(expectedDate: "2026-09-23", now: instant("2026-09-23T12:00:00-04:00"), enforceFreshness: true),
            .missingPlanIdentifier
        )
    }

    func testExpiredCurrentPlanIsRejected() throws {
        let plan = try decode(planID: "plan-1", validUntil: "2026-09-23T11:00:00-04:00")
        guard case .expired = plan.validation(
            expectedDate: "2026-09-23",
            now: instant("2026-09-23T12:00:00-04:00"),
            enforceFreshness: true
        ) else {
            return XCTFail("Expected expired validation")
        }
    }

    func testReadbackBindsDisplayedPlan() throws {
        let plan = try decode(planID: "plan-verified", validUntil: "2026-09-24T00:00:00-04:00")
        let readback = try XCTUnwrap(plan.readback(consumer: "MONDAY Command Center", appVersion: "0.2.0"))
        XCTAssertEqual(readback.planID, "plan-verified")
        XCTAssertEqual(readback.planSchemaVersion, 3)
        XCTAssertEqual(readback.state, "displayed")
    }

    func testUnknownCalendarRemainsExplicit() throws {
        let plan = try decode(planID: "plan-verified", validUntil: "2026-09-24T00:00:00-04:00")
        XCTAssertEqual(plan.sources.first(where: { $0.kind == "calendar" })?.status, "unknown")
        XCTAssertTrue(plan.schedule.isEmpty)
    }

    func testPlannerFollowingTodayRollsAcrossMidnight() {
        let selected = instant("2026-09-23T08:00:00-04:00")
        let afterMidnight = instant("2026-09-24T00:01:00-04:00")
        let result = PlannerDayRollover.selection(current: selected, now: afterMidnight, followsToday: true)
        XCTAssertEqual(result, instant("2026-09-24T00:00:00-04:00"))
    }

    func testPlannerBrowsingArchiveDoesNotRollAcrossMidnight() {
        let selected = instant("2026-09-22T00:00:00-04:00")
        let afterMidnight = instant("2026-09-24T00:01:00-04:00")
        XCTAssertEqual(PlannerDayRollover.selection(current: selected, now: afterMidnight, followsToday: false), selected)
    }

    func testTwinProjectionValidatesAndBindsReadback() throws {
        let projection = try decodeTwin()
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .current)
        let receipt = try XCTUnwrap(projection.readback(consumer: "MONDAY Command Center", appVersion: "0.3.0", displayedAt: instant("2026-09-23T12:00:00-04:00")))
        XCTAssertEqual(receipt.projectionID, "twin-2026-09-23-aaaaaaaaaaaa")
        XCTAssertEqual(receipt.contentDigest, String(repeating: "a", count: 64))
        XCTAssertEqual(receipt.viewIDs, ["digital-twin"])
    }

    func testTwinProjectionRejectsUnsupportedSchema() throws {
        let projection = try decodeTwin(schemaVersion: 2)
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .unsupportedSchema(2))
    }

    func testTwinProjectionRejectsExpiredProjection() throws {
        let projection = try decodeTwin(validUntil: "2026-09-23T11:00:00-04:00")
        guard case .expired = projection.validation(now: instant("2026-09-23T12:00:00-04:00")) else { return XCTFail("Expected expired projection") }
    }

    func testTwinProjectionRejectsPersonalStatementLeak() throws {
        let projection = try decodeTwin(personalStatement: true)
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .personalStatementExposed("private-pref"))
    }

    func testTwinProjectionRejectsDenominatorMismatch() throws {
        let projection = try decodeTwin(professionalCount: 9)
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .denominatorMismatch)
    }

    func testTwinProjectionRejectsSecretBearingRecord() throws {
        let projection = try decodeTwin(professionalStatement: "Read /Users/chris/private.txt")
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .prohibitedMaterial("work-style"))
    }

    func testGovernedPathRejectsTraversalAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let insideFile = root.appendingPathComponent("inside.json")
        let outsideFile = outside.appendingPathComponent("outside.json")
        try Data("{}".utf8).write(to: insideFile)
        try Data("{}".utf8).write(to: outsideFile)
        let link = root.appendingPathComponent("escape.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)
        XCTAssertEqual(GovernedPath.containedFile(insideFile, within: root), insideFile.standardizedFileURL)
        XCTAssertNil(GovernedPath.containedFile(outsideFile, within: root))
        XCTAssertNil(GovernedPath.containedFile(link, within: root))
    }

    private func decode(planID: String?, validUntil: String) throws -> DailyPlannerPlan {
        let identifier = planID.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "schemaVersion": 3,
          "planID": \(identifier),
          "date": "2026-09-23",
          "generatedAt": "2026-09-23T10:00:00-04:00",
          "validUntil": "\(validUntil)",
          "timezone": "America/New_York",
          "sources": [{"kind":"calendar","name":"Apple Calendar","status":"unknown","fetchedAt":"2026-09-23T10:00:00-04:00"}],
          "coverage": {"status":"unknown","sources":[],"unresolved":["Apple Calendar: unknown"]},
          "primaryFocus": "Protect commitments",
          "schedule": [],
          "priorities": {"a":[],"b":[],"c":[]},
          "notes": [],
          "compass": [],
          "publication": {"producer":"monday@personal","contractVersion":3,"state":"published"}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DailyPlannerPlan.self, from: Data(json.utf8))
    }

    private func decodeTwin(
        schemaVersion: Int = 1,
        validUntil: String = "2026-09-24T10:00:00-04:00",
        professionalCount: Int = 1,
        personalStatement: Bool = false,
        professionalStatement: String = "Chris prefers concise evidence-backed briefs."
    ) throws -> TwinInspectionProjection {
        let privateStatement = personalStatement ? #", "statement": "Private material""# : ""
        let json = """
        {
          "schemaVersion": \(schemaVersion),
          "projectionID": "twin-2026-09-23-aaaaaaaaaaaa",
          "contentDigest": "\(String(repeating: "a", count: 64))",
          "generatedAt": "2026-09-23T10:00:00-04:00",
          "validUntil": "\(validUntil)",
          "producer": "monday-digital-twin@personal",
          "audience": "Chris-private-local",
          "contractAudit": {"status":"PASS","promiseCount":10,"implementedPromiseCount":10,"sourceCount":15,"recordCount":5,"errors":[],"auditedAt":"2026-09-23T10:00:00-04:00"},
          "promises": [{"id":"P2-18","promise":"Trace promises","owner":"monday-core","control":"audit","status":"implemented"}],
          "authoritySources": [{"id":"project-knowledge","domain":"professional","role":"authoritative-record","suitableFor":["project-state"],"notProofOf":["personal-state"],"authoritativeRecord":"project-knowledge","owner":"project-intelligence","allowedTwinDomains":["professional"],"retention":"governed","conflictRule":"preserve disagreement"}],
          "authorityRecords": [{"id":"professional-twin","domain":"professional","owner":"monday-digital-twin","allowedIngress":["project-knowledge"],"allowedEgress":["private-command-center"],"prohibitedEgress":["personal-project-knowledge"],"audience":"Chris-private","retention":"reviewed"}],
          "records": [
            {"recordID":"work-style","domain":"professional","recordType":"working-preference","statement":"\(professionalStatement)","status":"active","version":1,"evidenceClass":"validated","confidence":0.9,"sensitivity":"shareable","purpose":"Planning","updatedAt":"2026-09-23T10:00:00-04:00","reviewAt":"2026-12-23T10:00:00-05:00","sourceIDs":["project-knowledge"],"evidenceCount":1,"contradictionCount":0,"supersedes":null},
            {"recordID":"private-pref","domain":"personal","recordType":"preference"\(privateStatement),"status":"active","version":1,"evidenceClass":"reported","confidence":0.8,"sensitivity":"private","purpose":"Private planning","updatedAt":"2026-09-23T10:00:00-04:00","reviewAt":"2026-12-23T10:00:00-05:00","sourceIDs":["user-supplied"],"evidenceCount":1,"contradictionCount":0,"supersedes":null}
          ],
          "governanceEvents": [],
          "optOuts": {"schemaVersion":1,"global":false,"domains":[],"sources":[],"recordTypes":[],"updatedAt":null},
          "playbooks": [],
          "coverage": {"professionalCount":\(professionalCount),"personalCount":1,"governanceEventCount":0,"promiseCount":10,"implementedPromiseCount":10,"unresolvedCount":0}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TwinInspectionProjection.self, from: Data(json.utf8))
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
