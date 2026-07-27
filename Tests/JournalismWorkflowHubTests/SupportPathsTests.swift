import XCTest
@testable import JournalismWorkflowHub

final class SupportPathsTests: XCTestCase {
    func testSupportDirectoryUsesTemporaryRootDuringTests() {
        let supportDirectory = journalismWorkflowHubSupportDirectory()

        XCTAssertTrue(supportDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue(supportDirectory.path.contains("JournalismWorkflowHubTests"))
    }

    func testLogsDirectoryLivesUnderSupportRoot() {
        let supportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logsDirectory = journalismWorkflowHubLogsDirectory(supportDirectory: supportDirectory)

        XCTAssertEqual(logsDirectory.path, supportDirectory.appendingPathComponent("logs").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsDirectory.path))
    }

    func testLogFileURLLivesUnderLogsDirectory() {
        let supportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logFileURL = journalismWorkflowHubLogFileURL(supportDirectory: supportDirectory)

        XCTAssertEqual(logFileURL.path, supportDirectory.appendingPathComponent("logs/app.log").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFileURL.deletingLastPathComponent().path))
    }

    func testCreateWorkflowWriteBackupsCopiesExistingWorkspaceFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRoot = tmp.appendingPathComponent("workspace")
        let supportRoot = tmp.appendingPathComponent("support")
        let readmeURL = workspaceRoot.appendingPathComponent("Projects/2026/demo/README.md")

        try FileManager.default.createDirectory(
            at: readmeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try """
        ---
        type: project
        ---
        """.write(to: readmeURL, atomically: true, encoding: .utf8)

        let backups = try createWorkflowWriteBackups(
            paths: [readmeURL.path, "", readmeURL.path],
            workspaceRoot: workspaceRoot,
            supportDirectory: supportRoot,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(backups.count, 1)
        let backupPath = try XCTUnwrap(backups.first)
        let backupURL = URL(fileURLWithPath: backupPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(backupURL.path.contains("workflow_backups/19700101_000000/Projects/2026/demo/README.md"))

        let backupContents = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertTrue(backupContents.contains("type: project"))
    }
}
