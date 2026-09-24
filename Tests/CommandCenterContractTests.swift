import XCTest
@testable import Command_Center

final class CommandCenterContractTests: XCTestCase {
    func testCommandCenterRoomLaunchRouting() {
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center"]), .today)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "digitalTwin"]), .digitalTwin)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "runtimeOperations"]), .runtimeOperations)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "unknown"]), .today)
    }

    func testRuntimeProjectionSupportsPopulatedPartialRetryingDeadLetteredAndIndeterminateState() throws {
        let projection = try decodeRuntime()
        XCTAssertEqual(projection.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertTrue(projection.workflows.contains(where: { $0.state == "retrying" }))
        XCTAssertTrue(projection.workflows.contains(where: { $0.state == "dead-lettered" }))
        XCTAssertEqual(projection.deadLetters.first?.replayEligibility, "requires-review")
        XCTAssertEqual(projection.sources.first?.status, "partial")
        XCTAssertEqual(projection.connections.first?.coverageState, "unknown")
    }

    func testRuntimeProjectionSupportsEmptyAndRecoveredStates() throws {
        let empty = try decodeRuntime { object in
            for key in ["workflows", "retries", "deadLetters", "externalActions", "commitments", "decisions", "sources", "connections", "migrations", "alerts", "recoveryInstructions"] {
                object[key] = []
            }
            object["coverage"] = runtimeCoverage()
        }
        XCTAssertEqual(empty.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .current)

        let recovered = try decodeRuntime { object in
            var workflow = (object["workflows"] as! [[String: Any]])[0]
            workflow["state"] = "succeeded"
            workflow["nextAttemptAt"] = NSNull()
            workflow["errorCode"] = NSNull()
            object["workflows"] = [workflow]
            object["retries"] = []
            object["deadLetters"] = []
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["state"] = "resolved"
            alert["resolvedAt"] = "2026-09-23T11:45:00-04:00"
            object["alerts"] = [alert]
            object["coverage"] = runtimeCoverage(workflows: 1, actions: 1, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1)
        }
        XCTAssertEqual(recovered.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertEqual(recovered.workflows.first?.state, "succeeded")
        XCTAssertEqual(recovered.alerts.first?.state, "resolved")
    }

    func testRuntimeReadbackIsViewSpecificForEveryOperationalSurface() throws {
        let projection = try decodeRuntime()
        XCTAssertEqual(RuntimeOperationsReadback.allowedViewIDs.count, 8)
        for viewID in RuntimeOperationsReadback.allowedViewIDs {
            let receipt = try XCTUnwrap(projection.readback(
                viewID: viewID,
                consumer: "MONDAY Command Center",
                appVersion: "0.4.0",
                displayedAt: instant("2026-09-23T12:00:00-04:00")
            ))
            XCTAssertEqual(receipt.projectionID, projection.projectionID)
            XCTAssertEqual(receipt.viewIDs, [viewID])
            XCTAssertEqual(receipt.state, "displayed")
        }
        XCTAssertNil(projection.readback(viewID: "operations-all", consumer: "MONDAY Command Center", appVersion: "0.4.0"))
    }

    func testRuntimeProjectionRejectsFutureSchemaAndIncompatibleApp() throws {
        let future = try decodeRuntime { $0["schemaVersion"] = 2 }
        XCTAssertEqual(future.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .unsupportedSchema(2))

        let incompatible = try decodeRuntime { object in
            var compatibility = object["compatibility"] as! [String: Any]
            compatibility["minimumAppVersion"] = "0.5.0"
            compatibility["status"] = "update-required"
            object["compatibility"] = compatibility
        }
        XCTAssertEqual(incompatible.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .incompatibleApp("0.5.0"))
        XCTAssertNil(incompatible.readback(viewID: "operations-overview", consumer: "MONDAY Command Center", appVersion: "0.4.0"))
    }

    func testRuntimeProjectionRejectsInvalidDigestAndDuplicateIdentifiers() throws {
        let digest = try decodeRuntime { $0["contentDigest"] = String(repeating: "d", count: 64) }
        XCTAssertEqual(digest.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .invalidContentDigest)

        let duplicate = try decodeRuntime { object in
            let workflows = object["workflows"] as! [[String: Any]]
            object["workflows"] = workflows + [workflows[0]]
            object["coverage"] = runtimeCoverage(workflows: 3, retries: 1, deadLetters: 1, actions: 1, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1, unresolved: 5)
        }
        XCTAssertEqual(duplicate.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .duplicateIdentifier("workflow"))
    }

    func testRuntimeProjectionRejectsImpossibleActionAndDenominatorMismatch() throws {
        let impossible = try decodeRuntime { object in
            var action = (object["externalActions"] as! [[String: Any]])[0]
            action["state"] = "verified"
            action["readbackStatus"] = "matched"
            action["confirmedAt"] = "2026-09-23T11:00:00-04:00"
            action["attemptedAt"] = "2026-09-23T11:05:00-04:00"
            action["verifiedAt"] = NSNull()
            object["externalActions"] = [action]
        }
        XCTAssertEqual(impossible.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .invalidExternalAction("action-calendar-001"))

        let mismatch = try decodeRuntime { object in
            object["coverage"] = runtimeCoverage(workflows: 99)
        }
        XCTAssertEqual(mismatch.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .denominatorMismatch)
    }

    func testRuntimeProjectionRejectsProhibitedMaterialAndUnknownFields() throws {
        let prohibited = try decodeRuntime { object in
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["safeSummary"] = "Inspect /Users/chris/private.txt"
            object["alerts"] = [alert]
        }
        XCTAssertEqual(prohibited.validation(appVersion: "0.4.0", now: instant("2026-09-23T12:00:00-04:00")), .prohibitedMaterial("alert-runtime-001"))

        var unknown = runtimeObject()
        unknown["rawEmailBody"] = "not permitted"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: unknown).write(to: url)
        XCTAssertThrowsError(try RuntimeOperationsReader.load(from: url)) { error in
            guard case RuntimeOperationsContractError.malformedShape("root") = error else { return XCTFail("Expected root shape rejection, got \(error)") }
        }
    }

    func testRuntimeReaderVerifiesCanonicalContentDigest() throws {
        var valid = runtimeObject()
        valid.removeValue(forKey: "contentDigest")
        valid.removeValue(forKey: "projectionID")
        let digest = try RuntimeOperationsReader.contentDigest(for: valid)
        valid["contentDigest"] = digest
        valid["projectionID"] = "runtime-2026-09-23-\(digest.prefix(12))"
        let validURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let tamperedURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: validURL); try? FileManager.default.removeItem(at: tamperedURL) }
        try JSONSerialization.data(withJSONObject: valid, options: [.sortedKeys]).write(to: validURL)
        XCTAssertNoThrow(try RuntimeOperationsReader.load(from: validURL))

        var alerts = valid["alerts"] as! [[String: Any]]
        alerts[0]["safeSummary"] = "The normalized evidence changed after publication."
        valid["alerts"] = alerts
        try JSONSerialization.data(withJSONObject: valid, options: [.sortedKeys]).write(to: tamperedURL)
        XCTAssertThrowsError(try RuntimeOperationsReader.load(from: tamperedURL)) { error in
            guard case RuntimeOperationsContractError.invalidContentDigest = error else { return XCTFail("Expected integrity rejection, got \(error)") }
        }
    }

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

    func testTwinProjectionRejectsSensitiveGovernanceReason() throws {
        let projection = try decodeTwin(governanceReason: "Private note at user@example.com")
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .prohibitedMaterial("event-123"))
    }

    func testTwinProjectionRejectsSensitivePlaybookMetadata() throws {
        let projection = try decodeTwin(playbookAudience: "/Users/chris/private.txt")
        XCTAssertEqual(projection.validation(now: instant("2026-09-23T12:00:00-04:00")), .prohibitedMaterial("playbook-123"))
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
        professionalStatement: String = "Chris prefers concise evidence-backed briefs.",
        governanceReason: String = "Withheld from privacy-reduced projection.",
        playbookAudience: String = "Approved collaborator"
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
          "governanceEvents": [{"eventID":"event-123","occurredAt":"2026-09-23T10:00:00-04:00","action":"corrected","domain":"professional","recordID":"work-style","reason":"\(governanceReason)","beforeVersion":1,"afterVersion":2,"result":"applied"}],
          "optOuts": {"schemaVersion":1,"global":false,"domains":[],"sources":[],"recordTypes":[],"updatedAt":null},
          "playbooks": [{"playbookID":"playbook-123","title":"Working guide","state":"prepared","updatedAt":"2026-09-23T10:00:00-04:00","audience":"\(playbookAudience)","qaVerdict":"PASS","packageDigest":"\(String(repeating: "b", count: 64))"}],
          "coverage": {"professionalCount":\(professionalCount),"personalCount":1,"governanceEventCount":1,"promiseCount":10,"implementedPromiseCount":10,"unresolvedCount":0}
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TwinInspectionProjection.self, from: Data(json.utf8))
    }

    private func decodeRuntime(_ update: (inout [String: Any]) -> Void = { _ in }) throws -> RuntimeOperationsProjection {
        var object = runtimeObject()
        update(&object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuntimeOperationsProjection.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func runtimeObject() -> [String: Any] {
        let digest = String(repeating: "c", count: 64)
        return [
            "schemaVersion": 1,
            "projectionID": "runtime-2026-09-23-\(String(digest.prefix(12)))",
            "contentDigest": digest,
            "generatedAt": "2026-09-23T10:00:00-04:00",
            "validUntil": "2026-09-24T10:00:00-04:00",
            "producer": "monday-runtime",
            "audience": "Chris-private-local",
            "runtimeVersion": "1.0.0",
            "workflows": [
                [
                    "workflowID": "workflow-planning-001", "kind": "daily-planning", "state": "retrying",
                    "attemptCount": 2, "maxAttempts": 4, "idempotencyKey": "idem-planning-001",
                    "updatedAt": "2026-09-23T11:30:00-04:00", "startedAt": "2026-09-23T11:00:00-04:00",
                    "nextAttemptAt": "2026-09-23T12:15:00-04:00", "checkpoint": "source-validation", "errorCode": "SOURCE_PARTIAL"
                ],
                [
                    "workflowID": "workflow-meeting-001", "kind": "meeting-continuity", "state": "dead-lettered",
                    "attemptCount": 4, "maxAttempts": 4, "idempotencyKey": "idem-meeting-001",
                    "updatedAt": "2026-09-23T11:35:00-04:00", "startedAt": "2026-09-23T10:00:00-04:00",
                    "checkpoint": "project-writeback", "errorCode": "RETRY_LIMIT"
                ]
            ],
            "retries": [[
                "retryID": "retry-planning-002", "workflowID": "workflow-planning-001", "attemptNumber": 2,
                "state": "scheduled", "reasonCode": "SOURCE_PARTIAL", "scheduledAt": "2026-09-23T12:15:00-04:00", "backoffSeconds": 900
            ]],
            "deadLetters": [[
                "deadLetterID": "deadletter-meeting-001", "workflowID": "workflow-meeting-001",
                "createdAt": "2026-09-23T11:35:00-04:00", "reasonCode": "RETRY_LIMIT",
                "attemptCount": 4, "replayEligibility": "requires-review", "recoveryInstructionID": "recovery-runtime-001"
            ]],
            "externalActions": [[
                "actionID": "action-calendar-001", "kind": "calendar-write", "targetLabel": "Primary work calendar",
                "state": "proposed", "confirmationRequired": true, "readbackStatus": "missing", "retrySafe": false
            ]],
            "commitments": [[
                "commitmentID": "commitment-foundry-001", "title": "Prepare the bounded daily report", "state": "active",
                "ownerLabel": "Chris", "dueAt": "2026-09-23T17:00:00-04:00", "consequence": "Stakeholder update delayed",
                "evidenceStatus": "supported", "decisionIDs": ["decision-foundry-001"]
            ]],
            "decisions": [[
                "decisionID": "decision-foundry-001", "title": "Use the governed report route", "state": "decided",
                "ownerLabel": "Chris", "decidedAt": "2026-09-23T09:00:00-04:00", "evidenceStatus": "validated",
                "commitmentIDs": ["commitment-foundry-001"]
            ]],
            "sources": [[
                "sourceID": "outlook-calendar", "status": "partial", "scopeLabel": "Current local day",
                "attemptedAt": "2026-09-23T11:30:00-04:00", "succeededAt": "2026-09-23T11:30:00-04:00",
                "itemCount": 5, "processedCount": 4, "unresolvedCount": 1, "freshness": "fresh", "errorCode": "ONE_UNRESOLVED"
            ]],
            "connections": [[
                "connectionID": "connection-outlook-calendar", "sourceID": "outlook-calendar", "status": "connected",
                "authenticationState": "authenticated", "coverageState": "unknown", "lastCheckedAt": "2026-09-23T11:30:00-04:00",
                "diagnosticCodes": ["CONTENT_COVERAGE_UNKNOWN"]
            ]],
            "compatibility": [
                "projectionSchemaVersion": 1, "minimumAppVersion": "0.4.0", "maximumAppVersion": "0.4.99",
                "status": "compatible", "issueCodes": []
            ],
            "migrations": [[
                "migrationID": "migration-runtime-001", "fromVersion": "0.9.0", "toVersion": "1.0.0", "state": "applied",
                "reversible": true, "appliedAt": "2026-09-23T10:00:00-04:00", "safeSummary": "Runtime state upgraded to the governed schema."
            ]],
            "alerts": [[
                "alertID": "alert-runtime-001", "severity": "warning", "category": "source-health", "state": "open",
                "title": "Calendar coverage is partial", "safeSummary": "One normalized item remains unresolved.",
                "raisedAt": "2026-09-23T11:30:00-04:00", "recoveryInstructionIDs": ["recovery-runtime-001"]
            ]],
            "recoveryInstructions": [[
                "instructionID": "recovery-runtime-001", "title": "Inspect the failed bounded collection",
                "steps": ["Review the privacy-reduced source diagnostic.", "Retry the bounded collection after the source is available."],
                "actionBoundary": "local-governed", "relatedIDs": ["workflow-planning-001", "outlook-calendar"]
            ]],
            "coverage": runtimeCoverage(workflows: 2, retries: 1, deadLetters: 1, actions: 1, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1, unresolved: 5)
        ]
    }

    private func runtimeCoverage(
        workflows: Int = 0, retries: Int = 0, deadLetters: Int = 0, actions: Int = 0,
        commitments: Int = 0, decisions: Int = 0, sources: Int = 0, connections: Int = 0,
        migrations: Int = 0, alerts: Int = 0, recovery: Int = 0, unresolved: Int = 0
    ) -> [String: Any] {
        [
            "workflowCount": workflows, "retryCount": retries, "deadLetterCount": deadLetters,
            "externalActionCount": actions, "commitmentCount": commitments, "decisionCount": decisions,
            "sourceCount": sources, "connectionCount": connections, "migrationCount": migrations,
            "alertCount": alerts, "recoveryInstructionCount": recovery, "unresolvedCount": unresolved
        ]
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
