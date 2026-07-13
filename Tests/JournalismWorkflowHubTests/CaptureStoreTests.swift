import XCTest
@testable import JournalismWorkflowHub

final class CaptureStoreTests: XCTestCase {
    func testCaptureStoreRoundTripsRecords() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRoot = tmp.appendingPathComponent("workspace")
        let supportRoot = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true, attributes: nil)

        let record = CaptureRecord(
            id: "capture-1",
            displayName: "Story note",
            originalSourcePath: "/tmp/incoming/story.md",
            importedStoragePath: "/tmp/support/capture/story.md",
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            captureType: .file,
            state: .needsReview,
            failureDescription: nil,
            userNote: "Why this matters",
            assignedTargetPath: nil,
            assignedAt: nil,
            assignedDestinationPath: nil
        )

        let store = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        store.replace(with: [record])

        let catalog = try XCTUnwrap(store.load())
        XCTAssertEqual(catalog.version, 1)
        XCTAssertEqual(catalog.workspaceRootPath, workspaceRoot.path)
        XCTAssertEqual(catalog.records, [record])
    }

    func testCaptureStoreIgnoresMismatchedWorkspaceRoot() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRootA = tmp.appendingPathComponent("workspace-a")
        let workspaceRootB = tmp.appendingPathComponent("workspace-b")
        let supportRoot = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: workspaceRootA, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: workspaceRootB, withIntermediateDirectories: true, attributes: nil)

        let importedPath = try makeStoredCaptureItem(
            supportRoot: supportRoot,
            recordID: "capture-1",
            filename: "story-note.md",
            contents: "Recovered note"
        )
        let record = CaptureRecord(
            id: "capture-1",
            displayName: "Story note",
            originalSourcePath: "/tmp/incoming/story-note.md",
            importedStoragePath: importedPath,
            capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
            captureType: .note,
            state: .assigned,
            failureDescription: nil,
            userNote: "Why this matters",
            assignedTargetPath: "/tmp/workspace-a/Projects/2026/story",
            assignedAt: Date(timeIntervalSince1970: 1_720_000_100),
            assignedDestinationPath: "/tmp/workspace-a/Projects/2026/story/docs/story-note.md"
        )

        let storeA = CaptureStore(workspaceRoot: workspaceRootA, supportDirectory: supportRoot)
        storeA.replace(with: [record])

        let storeB = CaptureStore(workspaceRoot: workspaceRootB, supportDirectory: supportRoot)
        XCTAssertNil(storeB.load())
        XCTAssertNil(storeB.loadRecords())

        let recoveredRecord = try XCTUnwrap(storeB.recoverRecordsFromStorage(excluding: []).first)
        XCTAssertEqual(recoveredRecord.id, record.id)
        XCTAssertEqual(recoveredRecord.displayName, record.displayName)
        XCTAssertEqual(recoveredRecord.originalSourcePath, record.originalSourcePath)
        let recoveredPath = try XCTUnwrap(recoveredRecord.importedStoragePath)
        XCTAssertEqual(URL(fileURLWithPath: recoveredPath).lastPathComponent, URL(fileURLWithPath: importedPath).lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredPath))
        XCTAssertEqual(recoveredRecord.captureType, .note)
        XCTAssertEqual(recoveredRecord.state, .needsReview)
        XCTAssertEqual(recoveredRecord.userNote, record.userNote)
        XCTAssertNil(recoveredRecord.assignedTargetPath)
        XCTAssertNil(recoveredRecord.assignedDestinationPath)
    }

    func testCaptureStoreReportsWorkspaceMismatchFromCatalogLoad() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRootA = tmp.appendingPathComponent("workspace-a")
        let workspaceRootB = tmp.appendingPathComponent("workspace-b")
        let supportRoot = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: workspaceRootA, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: workspaceRootB, withIntermediateDirectories: true, attributes: nil)

        let storeA = CaptureStore(workspaceRoot: workspaceRootA, supportDirectory: supportRoot)
        storeA.replace(with: [])

        let storeB = CaptureStore(workspaceRoot: workspaceRootB, supportDirectory: supportRoot)
        guard case .workspaceMismatch(let catalog) = storeB.loadCatalog() else {
            return XCTFail("Expected a workspace mismatch load result.")
        }

        XCTAssertEqual(catalog.workspaceRootPath, workspaceRootA.path)
    }

    func testCaptureRecordDecodesLegacyAssignedProjectPathKey() throws {
        let data = Data(
            """
            {
              "id" : "capture-legacy",
              "displayName" : "Legacy note",
              "originalSourcePath" : "/tmp/incoming/legacy.md",
              "importedStoragePath" : "/tmp/support/capture/legacy.md",
              "capturedAt" : "2024-07-03T09:46:40Z",
              "captureType" : "note",
              "state" : "assigned",
              "failureDescription" : null,
              "userNote" : "Historic assignment",
              "assignedProjectPath" : "/tmp/workspace-a/Areas/food_watch",
              "assignedAt" : "2024-07-03T09:48:20Z",
              "assignedDestinationPath" : "/tmp/workspace-a/Areas/food_watch/docs/legacy.md"
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(CaptureRecord.self, from: data)

        XCTAssertEqual(record.assignedTargetPath, "/tmp/workspace-a/Areas/food_watch")
        XCTAssertEqual(record.assignedDestinationPath, "/tmp/workspace-a/Areas/food_watch/docs/legacy.md")
    }

    func testCaptureStoreRecoversOrphanedRecordsFromStorage() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRoot = tmp.appendingPathComponent("workspace")
        let supportRoot = tmp.appendingPathComponent("support")
        let captureRoot = supportRoot.appendingPathComponent("capture/items/orphaned-record", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: captureRoot, withIntermediateDirectories: true, attributes: nil)
        let storedFile = captureRoot.appendingPathComponent("orphaned.pdf")
        try Data("pdf".utf8).write(to: storedFile)

        let store = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let recoveredRecords = store.recoverRecordsFromStorage(excluding: [])

        let recovered = try XCTUnwrap(recoveredRecords.first)
        XCTAssertEqual(recovered.id, "orphaned-record")
        let recoveredPath = try XCTUnwrap(recovered.importedStoragePath)
        XCTAssertEqual(normalizedPath(recoveredPath), normalizedPath(storedFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredPath))
        XCTAssertEqual(recovered.captureType, .file)
        XCTAssertEqual(recovered.state, .needsReview)
    }

    private func makeStoredCaptureItem(
        supportRoot: URL,
        recordID: String,
        filename: String,
        contents: String
    ) throws -> String {
        let captureRoot = supportRoot.appendingPathComponent("capture/items/\(recordID)", isDirectory: true)
        try FileManager.default.createDirectory(at: captureRoot, withIntermediateDirectories: true, attributes: nil)
        let storedFile = captureRoot.appendingPathComponent(filename)
        try Data(contents.utf8).write(to: storedFile)
        return storedFile.path
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
