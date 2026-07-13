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
            assignedProjectPath: nil,
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

        let storeA = CaptureStore(workspaceRoot: workspaceRootA, supportDirectory: supportRoot)
        storeA.replace(with: [])

        let storeB = CaptureStore(workspaceRoot: workspaceRootB, supportDirectory: supportRoot)
        XCTAssertNil(storeB.load())
        XCTAssertNil(storeB.loadRecords())
    }
}
