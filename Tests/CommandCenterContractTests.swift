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

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
