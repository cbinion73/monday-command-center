import XCTest
@testable import Command_Center

final class CommandCenterContractTests: XCTestCase {
    func testCommandCenterRoomLaunchRouting() {
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center"]), .today)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "digitalTwin"]), .digitalTwin)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "runtimeOperations"]), .runtimeOperations)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "evaluation"]), .evaluation)
        XCTAssertEqual(CommandCenterRoom.initial(arguments: ["Command Center", "--command-center-room", "unknown"]), .today)
    }

    func testEvaluationProjectionValidatesAndWritesViewSpecificReadback() throws {
        let projectionURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let readbackURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: projectionURL); try? FileManager.default.removeItem(at: readbackURL) }
        try writeJSON(try finalizedEvaluationObject(), to: projectionURL)
        let projection = try EvaluationReader.load(from: projectionURL)
        XCTAssertEqual(projection.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .current)
        XCTAssertEqual(EvaluationReadback.allowedViewIDs.count, 6)
        for viewID in EvaluationReadback.allowedViewIDs {
            let receipt = try XCTUnwrap(projection.readback(viewID: viewID, consumer: "MONDAY Command Center", appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", displayedAt: instant("2026-09-24T12:00:00-04:00")))
            XCTAssertEqual(receipt.viewIDs, [viewID])
            XCTAssertEqual(receipt.projectionID, projection.projectionID)
        }
        let overview = try XCTUnwrap(projection.readback(viewID: "evaluation-overview", consumer: "MONDAY Command Center", appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", displayedAt: instant("2026-09-24T12:00:00-04:00")))
        try EvaluationReadbackWriter.write(overview, to: readbackURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(EvaluationReadback.self, from: Data(contentsOf: readbackURL)), overview)
        XCTAssertNil(projection.readback(viewID: "evaluation-all", consumer: "MONDAY Command Center", appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226"))
    }

    func testEvaluationProjectionRejectsFutureSchemaAndDigestTamper() throws {
        let future = try decodeEvaluation { $0["schemaVersion"] = 2 }
        XCTAssertEqual(future.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .unsupportedSchema(2))

        var object = try finalizedEvaluationObject()
        var suite = object["suite"] as! [String: Any]
        suite["suiteVersion"] = "tampered"
        object["suite"] = suite
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON(object, to: url)
        XCTAssertThrowsError(try EvaluationReader.load(from: url))
    }

    func testEvaluationProjectionRejectsDenominatorMismatchAndDuplicates() throws {
        let denominator = try decodeEvaluation { object in
            var coverage = object["coverage"] as! [String: Any]
            coverage["caseCount"] = 99
            object["coverage"] = coverage
        }
        XCTAssertEqual(denominator.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .denominatorMismatch)

        let duplicateCase = try decodeEvaluation { object in
            let cases = object["caseCoverage"] as! [[String: Any]]
            object["caseCoverage"] = cases + [cases[0]]
            var suite = object["suite"] as! [String: Any]
            suite["requiredCaseCount"] = 3
            object["suite"] = suite
            var coverage = object["coverage"] as! [String: Any]
            coverage["caseCount"] = 3; coverage["passedCaseCount"] = 3; coverage["releaseBlockingCount"] = 3; coverage["releaseBlockingPassedCount"] = 3
            object["coverage"] = coverage
        }
        XCTAssertEqual(duplicateCase.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .duplicateIdentifier("case"))

        let duplicateConnector = try decodeEvaluation { object in
            let connectors = object["connectorDecisions"] as! [[String: Any]]
            object["connectorDecisions"] = connectors + [connectors[0]]
            var coverage = object["coverage"] as! [String: Any]
            coverage["connectorCount"] = 2
            object["coverage"] = coverage
        }
        XCTAssertEqual(duplicateConnector.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .duplicateIdentifier("connector"))
    }

    func testEvaluationProjectionRejectsUnknownGateStatus() throws {
        let projection = try decodeEvaluation { object in
            var gates = object["gateResults"] as! [[String: Any]]
            gates[0]["status"] = "MAYBE"
            object["gateResults"] = gates
        }
        XCTAssertEqual(projection.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .invalidGate("engineering-release"))
    }

    func testEvaluationEnterpriseClaimRemainsBlockedAfterAcceptedSingleUserPilot() throws {
        let projection = try decodeEvaluation()
        XCTAssertEqual(projection.pilot.status, "accepted")
        XCTAssertEqual(projection.pilot.disposition, "accept")
        XCTAssertEqual(projection.enterpriseClaim.status, "BLOCKED")
        XCTAssertFalse(projection.enterpriseClaim.claimAllowed)
        XCTAssertEqual(projection.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .current)
    }

    func testEvaluationProjectionRejectsProhibitedMaterial() throws {
        var object = try finalizedEvaluationObject()
        var evidence = object["evidence"] as! [[String: Any]]
        evidence[0]["safeSummary"] = "Private body at /Users/example/secret.txt"
        object["evidence"] = evidence
        object = try finalizedEvaluationObject(object)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeJSON(object, to: url)
        XCTAssertThrowsError(try EvaluationReader.load(from: url))
    }

    func testEvaluationStaleProjectionPreservesExplicitLastValidState() throws {
        let expired = try decodeEvaluation { $0["validUntil"] = "2026-09-24T11:00:00-04:00" }
        let validation = expired.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00"))
        XCTAssertEqual(EvaluationDisplayState.resolve(latest: nil, validation: validation, hasLastValid: true), .staleLastValid)
        XCTAssertEqual(EvaluationDisplayState.resolve(latest: nil, validation: validation, hasLastValid: false), .unavailable)
    }

    func testEvaluationPairingRejectsPluginWithoutCapability() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeEvaluationPluginFixture(at: root)
        XCTAssertEqual(MondayEvaluationPluginInspector.validate(pluginURL: root, appVersion: "0.4.2"), .compatible(pluginVersion: "0.1.0+codex.20260924153226"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("skills/monday-evaluation/SKILL.md"))
        guard case .upgradeRequired = MondayEvaluationPluginInspector.validate(pluginURL: root, appVersion: "0.4.2") else { return XCTFail("Missing evaluation capability must fail closed") }
        try Data("evaluation".utf8).write(to: root.appendingPathComponent("skills/monday-evaluation/SKILL.md"))
        guard case .upgradeRequired = MondayEvaluationPluginInspector.validate(pluginURL: root, appVersion: "0.4.1") else { return XCTFail("Unsupported app must fail closed") }
    }

    func testEvaluationConnectorLifecycleDoesNotImplyCoverage() throws {
        let projection = try decodeEvaluation { object in
            var connectors = object["connectorDecisions"] as! [[String: Any]]
            connectors[0]["status"] = "active"
            connectors[0]["approvalState"] = "approved"
            connectors[0]["authenticationState"] = "unknown"
            connectors[0]["coverageState"] = "unknown"
            object["connectorDecisions"] = connectors
        }
        XCTAssertEqual(projection.connectorDecisions.first?.status, "active")
        XCTAssertEqual(projection.connectorDecisions.first?.coverageState, "unknown")
        XCTAssertEqual(projection.validation(appVersion: "0.4.2", pairedPluginVersion: "0.1.0+codex.20260924153226", now: instant("2026-09-24T12:00:00-04:00")), .current)
    }

    func testRuntimeProjectionSupportsPopulatedPartialRetryingDeadLetteredAndIndeterminateState() throws {
        let projection = try decodeRuntime()
        XCTAssertEqual(projection.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertTrue(projection.workflows.contains(where: { $0.state == "retrying" }))
        XCTAssertTrue(projection.workflows.contains(where: { $0.state == "dead-lettered" }))
        XCTAssertEqual(projection.deadLetters.first?.replayEligibility, "requires-review")
        XCTAssertEqual(projection.sources.first?.status, "partial")
        XCTAssertEqual(projection.connections.first?.coverageState, "unknown")
    }

    func testRuntimeProjectionPreservesAllEightExternalActionStatesAndGuardText() throws {
        let states = ["confirmation-required", "confirmed", "attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate", "cancelled"]
        let projection = try decodeRuntime { object in
            object["externalActions"] = states.enumerated().map { runtimeAction(state: $0.element, index: $0.offset) }
            object["coverage"] = runtimeCoverage(workflows: 2, retries: 1, deadLetters: 1, actions: 8, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1, unresolved: 8)
        }
        XCTAssertEqual(projection.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertEqual(Set(projection.externalActions.map(\.state)), Set(states))
        let guardTexts = states.map(RuntimeActionPresentation.safetyText)
        XCTAssertEqual(Set(guardTexts).count, 8)
        XCTAssertTrue(RuntimeActionPresentation.safetyText("attempted").contains("not verified"))
        XCTAssertTrue(RuntimeActionPresentation.safetyText("indeterminate").contains("Never retry"))

        let nativeNoEffect = try decodeRuntime { object in
            object["externalActions"] = [runtimeAction(state: "failed-before-dispatch", index: 1, readbackStatus: "matched")]
        }
        XCTAssertEqual(nativeNoEffect.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
    }

    func testRuntimePluginPairingFailsClosedWithoutVersionedCapabilityAndSchema() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRuntimePluginFixture(at: root)
        XCTAssertEqual(MondayRuntimePluginInspector.validate(pluginURL: root, appVersion: "0.4.1"), .compatible(pluginVersion: "0.1.0+codex.20260924150027"))

        try FileManager.default.removeItem(at: root.appendingPathComponent("skills/monday-runtime/SKILL.md"))
        guard case .upgradeRequired = MondayRuntimePluginInspector.validate(pluginURL: root, appVersion: "0.4.1") else { return XCTFail("Missing runtime skill must fail closed") }
        try Data("runtime".utf8).write(to: root.appendingPathComponent("skills/monday-runtime/SKILL.md"))

        try writeJSON(["name": "monday", "version": "0.2.0"], to: root.appendingPathComponent(".codex-plugin/plugin.json"))
        guard case .upgradeRequired = MondayRuntimePluginInspector.validate(pluginURL: root, appVersion: "0.4.1") else { return XCTFail("Unsupported plugin version must fail closed") }
        try writeJSON(["name": "monday", "version": "0.1.0+codex.20260924150027"], to: root.appendingPathComponent(".codex-plugin/plugin.json"))

        try writeJSON(runtimeCompatibilityMatrix(projectionVersion: 1), to: root.appendingPathComponent("skills/monday-runtime/references/compatibility-matrix.json"))
        guard case .upgradeRequired = MondayRuntimePluginInspector.validate(pluginURL: root, appVersion: "0.4.1") else { return XCTFail("Old runtime schema must fail closed") }
    }

    func testRuntimeProjectionSupportsEmptyAndRecoveredStates() throws {
        let empty = try decodeRuntime { object in
            for key in ["workflows", "retries", "deadLetters", "externalActions", "commitments", "decisions", "sources", "connections", "migrations", "alerts", "recoveryInstructions"] {
                object[key] = []
            }
            object["coverage"] = runtimeCoverage()
        }
        XCTAssertEqual(empty.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)

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
            alert["status"] = "resolved"
            alert["resolvedAt"] = "2026-09-23T11:45:00-04:00"
            object["alerts"] = [alert]
            object["coverage"] = runtimeCoverage(workflows: 1, actions: 1, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1)
        }
        XCTAssertEqual(recovered.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertEqual(recovered.workflows.first?.state, "succeeded")
        XCTAssertEqual(recovered.alerts.first?.state, "resolved")
    }

    func testRuntimeProjectionPreservesAlertLifecycleAndRecoveryControls() throws {
        let open = try decodeRuntime()
        let openAlert = try XCTUnwrap(open.alerts.first)
        XCTAssertEqual(openAlert.status, "open")
        XCTAssertEqual(openAlert.count, 2)
        XCTAssertNotNil(openAlert.suppressedUntil)
        let recovery = try XCTUnwrap(open.recoveryInstructions.first)
        XCTAssertFalse(recovery.verificationSteps.isEmpty)
        XCTAssertFalse(recovery.rollbackSteps.isEmpty)
        XCTAssertFalse(recovery.evidenceIDs.isEmpty)

        let acknowledged = try decodeRuntime { object in
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["state"] = "acknowledged"
            alert["status"] = "acknowledged"
            alert["acknowledgedAt"] = "2026-09-23T11:50:00-04:00"
            object["alerts"] = [alert]
        }
        XCTAssertEqual(acknowledged.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertNotNil(acknowledged.alerts.first?.acknowledgedAt)

        let resolved = try decodeRuntime { object in
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["state"] = "resolved"
            alert["status"] = "resolved"
            alert["resolvedAt"] = "2026-09-23T11:55:00-04:00"
            alert["suppressedUntil"] = NSNull()
            object["alerts"] = [alert]
        }
        XCTAssertEqual(resolved.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
        XCTAssertNotNil(resolved.alerts.first?.resolvedAt)
        XCTAssertNil(resolved.alerts.first?.suppressedUntil)

        let invalid = try decodeRuntime { object in
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["count"] = 0
            object["alerts"] = [alert]
        }
        XCTAssertNotEqual(invalid.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .current)
    }

    func testRuntimeReadbackIsViewSpecificForEveryOperationalSurface() throws {
        let projection = try decodeRuntime()
        XCTAssertEqual(RuntimeOperationsReadback.allowedViewIDs.count, 8)
        for viewID in RuntimeOperationsReadback.allowedViewIDs {
            let receipt = try XCTUnwrap(projection.readback(
                viewID: viewID,
                consumer: "MONDAY Command Center",
                appVersion: "0.4.1",
                displayedAt: instant("2026-09-23T12:00:00-04:00")
            ))
            XCTAssertEqual(receipt.projectionID, projection.projectionID)
            XCTAssertEqual(receipt.viewIDs, [viewID])
            XCTAssertEqual(receipt.state, "displayed")
        }
        XCTAssertNil(projection.readback(viewID: "operations-all", consumer: "MONDAY Command Center", appVersion: "0.4.1"))
    }

    func testRuntimeProjectionRejectsFutureSchemaAndIncompatibleApp() throws {
        let old = try decodeRuntime { $0["schemaVersion"] = 1 }
        XCTAssertEqual(old.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .unsupportedSchema(1))
        let future = try decodeRuntime { $0["schemaVersion"] = 3 }
        XCTAssertEqual(future.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .unsupportedSchema(3))

        let incompatible = try decodeRuntime { object in
            var compatibility = object["compatibility"] as! [String: Any]
            compatibility["minimumAppVersion"] = "0.5.0"
            compatibility["status"] = "update-required"
            object["compatibility"] = compatibility
        }
        XCTAssertEqual(incompatible.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .incompatibleApp("0.5.0"))
        XCTAssertNil(incompatible.readback(viewID: "operations-overview", consumer: "MONDAY Command Center", appVersion: "0.4.1"))
    }

    func testRuntimeProjectionRejectsInvalidDigestAndDuplicateIdentifiers() throws {
        let digest = try decodeRuntime { $0["contentDigest"] = String(repeating: "d", count: 64) }
        XCTAssertEqual(digest.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .invalidContentDigest)

        let duplicate = try decodeRuntime { object in
            let workflows = object["workflows"] as! [[String: Any]]
            object["workflows"] = workflows + [workflows[0]]
            object["coverage"] = runtimeCoverage(workflows: 3, retries: 1, deadLetters: 1, actions: 1, commitments: 1, decisions: 1, sources: 1, connections: 1, migrations: 1, alerts: 1, recovery: 1, unresolved: 5)
        }
        XCTAssertEqual(duplicate.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .duplicateIdentifier("workflow"))
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
        XCTAssertEqual(impossible.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .invalidExternalAction("action-calendar-001"))

        let mismatch = try decodeRuntime { object in
            object["coverage"] = runtimeCoverage(workflows: 99)
        }
        XCTAssertEqual(mismatch.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .denominatorMismatch)
    }

    func testRuntimeProjectionRejectsProhibitedMaterialAndUnknownFields() throws {
        let prohibited = try decodeRuntime { object in
            var alert = (object["alerts"] as! [[String: Any]])[0]
            alert["safeSummary"] = "Inspect /Users/chris/private.txt"
            object["alerts"] = [alert]
        }
        XCTAssertEqual(prohibited.validation(appVersion: "0.4.1", now: instant("2026-09-23T12:00:00-04:00")), .prohibitedMaterial("alert-runtime-001"))

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
            "schemaVersion": 2,
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
                "state": "confirmation-required", "confirmationRequired": true, "readbackStatus": "missing", "retrySafe": false
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
                "projectionSchemaVersion": 2, "pluginVersion": "0.1.0+codex.20260924150027", "capabilityVersion": "2.0.0",
                "databaseSchemaVersion": 2, "readbackSchemaVersion": 1,
                "minimumAppVersion": "0.4.1", "maximumAppVersion": "0.5.0",
                "status": "compatible", "issueCodes": [], "upgradePolicy": "registered-forward-only",
                "downgradePolicy": "fail-closed", "rollbackPolicy": "restore-verified-backup"
            ],
            "migrations": [[
                "migrationID": "migration-runtime-001", "fromVersion": "0.9.0", "toVersion": "1.0.0", "state": "applied",
                "reversible": true, "appliedAt": "2026-09-23T10:00:00-04:00", "safeSummary": "Runtime state upgraded to the governed schema."
            ]],
            "alerts": [[
                "alertID": "alert-runtime-001", "severity": "warning", "category": "source-health", "state": "open",
                "title": "Calendar coverage is partial", "safeSummary": "One normalized item remains unresolved.",
                "raisedAt": "2026-09-23T11:30:00-04:00", "firstSeen": "2026-09-23T11:30:00-04:00",
                "lastSeen": "2026-09-23T11:40:00-04:00", "count": 2, "status": "open",
                "suppressedUntil": "2026-09-23T11:55:00-04:00", "sourceKind": "runtime-derived",
                "evidenceIDs": ["evidence-runtime-001"], "recoveryInstructionIDs": ["recovery-runtime-001"]
            ]],
            "recoveryInstructions": [[
                "instructionID": "recovery-runtime-001", "title": "Inspect the failed bounded collection",
                "steps": ["Review the privacy-reduced source diagnostic.", "Retry the bounded collection after the source is available."],
                "verificationSteps": ["Confirm a new successful bounded collection receipt."],
                "rollbackSteps": ["Restore the last verified runtime backup if migration validation fails."],
                "actionBoundary": "local-governed", "relatedIDs": ["workflow-planning-001", "outlook-calendar"],
                "evidenceIDs": ["evidence-runtime-001"]
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

    private func runtimeAction(state: String, index: Int, readbackStatus override: String? = nil) -> [String: Any] {
        var action: [String: Any] = [
            "actionID": "action-governed-\(index)", "kind": "calendar-write", "targetLabel": "Primary work calendar",
            "state": state, "confirmationRequired": ["confirmation-required", "failed-before-dispatch"].contains(state),
            "readbackStatus": override ?? (state == "verified" ? "matched" : state == "indeterminate" ? "indeterminate" : "missing"),
            "retrySafe": state == "failed-before-dispatch"
        ]
        if ["confirmed", "attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate"].contains(state) {
            action["confirmedAt"] = "2026-09-23T11:00:00-04:00"
        }
        if ["attempting", "attempted", "verified", "failed-before-dispatch", "indeterminate"].contains(state) {
            action["attemptedAt"] = "2026-09-23T11:05:00-04:00"
        }
        if state == "verified" { action["verifiedAt"] = "2026-09-23T11:10:00-04:00" }
        return action
    }

    private func writeRuntimePluginFixture(at root: URL) throws {
        let paths = [".codex-plugin", "skills/monday-runtime/references", "skills/monday-core/references"]
        for path in paths { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        try writeJSON(["name": "monday", "version": "0.1.0+codex.20260924150027"], to: root.appendingPathComponent(".codex-plugin/plugin.json"))
        try Data("runtime".utf8).write(to: root.appendingPathComponent("skills/monday-runtime/SKILL.md"))
        try writeJSON(["schemaVersion": 1, "capabilities": [["id": "monday-runtime"]]], to: root.appendingPathComponent("skills/monday-core/references/capability-registry.json"))
        try writeJSON(runtimeCompatibilityMatrix(projectionVersion: 2), to: root.appendingPathComponent("skills/monday-runtime/references/compatibility-matrix.json"))
    }

    private func runtimeCompatibilityMatrix(projectionVersion: Int) -> [String: Any] {
        [
            "schemaVersion": 2, "capabilityVersion": "2.0.0", "runtimeDatabaseVersion": 2,
            "operationsProjectionVersion": projectionVersion, "operationsReadbackVersion": 1,
            "supportedAppVersions": ["minimumInclusive": "0.4.1", "maximumExclusive": "0.5.0"]
        ]
    }

    private func decodeEvaluation(mutate: (inout [String: Any]) throws -> Void = { _ in }) throws -> EvaluationProjection {
        var object = try finalizedEvaluationObject()
        try mutate(&object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvaluationProjection.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    private func finalizedEvaluationObject(_ supplied: [String: Any]? = nil) throws -> [String: Any] {
        var object = supplied ?? evaluationObject()
        object.removeValue(forKey: "contentDigest")
        object.removeValue(forKey: "projectionID")
        let digest = try EvaluationReader.contentDigest(for: object)
        object["contentDigest"] = digest
        object["projectionID"] = "evaluation-\(digest.prefix(12))"
        return object
    }

    private func evaluationObject() -> [String: Any] {
        [
            "schemaVersion": 1,
            "projectionID": "evaluation-placeholder0000",
            "contentDigest": String(repeating: "a", count: 64),
            "generatedAt": "2026-09-24T11:45:00-04:00",
            "validUntil": "2026-09-24T13:45:00-04:00",
            "producer": "monday-evaluation",
            "audience": "Chris-private-local",
            "releaseCandidate": [
                "releaseID": "release-priority4-001", "pluginVersion": "0.1.0+codex.20260924153226", "pluginCommit": "916066b",
                "appVersion": "0.4.2", "appBuild": 17, "appCommit": "30b9cb1",
                "minimumPluginVersion": "0.1.0", "maximumPluginVersionExclusive": "0.2.0",
                "minimumAppVersion": "0.4.2", "maximumAppVersionExclusive": "0.5.0", "compatibilityStatus": "compatible"
            ],
            "suite": ["suiteID": "monday-system-priority4-v1", "suiteVersion": "1.0.0", "suiteDigest": String(repeating: "b", count: 64), "requiredCaseCount": 2],
            "caseCoverage": [
                ["caseID": "ADV-AUTH-001", "category": "external-action-authority", "severity": "critical", "result": "pass", "releaseBlocking": true, "requirementIDs": ["P3-25"], "evidenceIDs": ["evidence-tests-001"]],
                ["caseID": "PILOT-ROLLOVER-001", "category": "pilot-suitability", "severity": "high", "result": "pass", "releaseBlocking": true, "requirementIDs": ["P1-17"], "evidenceIDs": ["evidence-pilot-001"]]
            ],
            "gateResults": [
                ["gateID": "engineering-release", "status": "PASS", "evaluatedAt": "2026-09-24T11:40:00-04:00", "reasonCodes": [], "evidenceIDs": ["evidence-tests-001"]],
                ["gateID": "pilot-start", "status": "PASS", "evaluatedAt": "2026-09-24T11:40:00-04:00", "reasonCodes": [], "evidenceIDs": ["evidence-pilot-001"]],
                ["gateID": "connector-activation", "status": "BLOCKED", "evaluatedAt": "2026-09-24T11:40:00-04:00", "reasonCodes": ["CONNECTOR_APPROVAL_PENDING"], "evidenceIDs": ["evidence-tests-001"]],
                ["gateID": "enterprise-claim", "status": "BLOCKED", "evaluatedAt": "2026-09-24T11:40:00-04:00", "reasonCodes": ["REPRESENTATIVE_ENTERPRISE_PILOT_REQUIRED"], "evidenceIDs": ["evidence-pilot-001"]]
            ],
            "connectorDecisions": [[
                "connectorID": "twg-jira", "tier": 2, "status": "evaluating", "route": "twg-jira", "sourceID": "jira-workitems",
                "authenticationState": "authenticated", "coverageState": "partial", "itemCount": 10, "processedCount": 8, "unresolvedCount": 2,
                "readOnly": true, "approvalState": "pending", "evidenceIDs": ["evidence-tests-001"]
            ]],
            "pilot": [
                "pilotID": "pilot-single-user-001", "status": "accepted", "cohort": "single-user", "timezone": "America/New_York",
                "plannedBusinessDays": 5, "plannedCheckpoints": 15, "attemptedCheckpoints": 15,
                "unattendedRolloversPlanned": 5, "unattendedRolloversCompleted": 5,
                "tier1AttemptsPlanned": 75, "tier1AttemptsRecorded": 75, "manualInterventionCount": 0,
                "disposition": "accept", "evidenceIDs": ["evidence-pilot-001"]
            ],
            "enterpriseClaim": [
                "status": "BLOCKED", "claimAllowed": false, "scope": "single-user",
                "safeStatement": "Single-user bounded pilot accepted for the tested local configuration.",
                "unmetRequirementIDs": ["REPRESENTATIVE_ENTERPRISE_PILOT", "SECURITY_PRIVACY_COMPLIANCE_REVIEW"]
            ],
            "evidence": [
                ["evidenceID": "evidence-tests-001", "kind": "test", "status": "verified", "observedAt": "2026-09-24T11:30:00-04:00", "safeSummary": "Required deterministic tests passed."],
                ["evidenceID": "evidence-pilot-001", "kind": "pilot-observation", "status": "verified", "observedAt": "2026-09-24T11:35:00-04:00", "safeSummary": "Bounded single-user pilot denominator completed."]
            ],
            "coverage": [
                "caseCount": 2, "gateCount": 4, "connectorCount": 1, "evidenceCount": 2,
                "passedCaseCount": 2, "failedCaseCount": 0, "blockedCaseCount": 0, "skippedCaseCount": 0, "notRunCaseCount": 0,
                "releaseBlockingCount": 2, "releaseBlockingPassedCount": 2, "unresolvedCount": 3
            ]
        ]
    }

    private func writeEvaluationPluginFixture(at root: URL) throws {
        for path in [".codex-plugin", "skills/monday-evaluation", "skills/monday-core/references"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try writeJSON(["name": "monday", "version": "0.1.0+codex.20260924153226"], to: root.appendingPathComponent(".codex-plugin/plugin.json"))
        try Data("evaluation".utf8).write(to: root.appendingPathComponent("skills/monday-evaluation/SKILL.md"))
        try writeJSON(["schemaVersion": 1, "capabilities": [["id": "monday-evaluation"]]], to: root.appendingPathComponent("skills/monday-core/references/capability-registry.json"))
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
