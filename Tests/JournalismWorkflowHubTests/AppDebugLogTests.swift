import XCTest
@testable import JournalismWorkflowHub

final class AppDebugLogTests: XCTestCase {
    func testRecordSkipsWritesWhenDisabled() {
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportRoot)

        AppDebugLog.record(
            "should not be written",
            enabled: false,
            supportDirectory: supportRoot
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testRecordRotatesWhenLogExceedsMaximumSize() throws {
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportRoot)
        let previousLogURL = logURL.deletingLastPathComponent().appendingPathComponent("app.previous.log")

        AppDebugLog.record(
            "first entry",
            enabled: true,
            supportDirectory: supportRoot,
            maximumFileSizeBytes: 80
        )
        AppDebugLog.record(
            String(repeating: "x", count: 120),
            enabled: true,
            supportDirectory: supportRoot,
            maximumFileSizeBytes: 80
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: previousLogURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))

        let previousContents = try String(contentsOf: previousLogURL, encoding: .utf8)
        let currentContents = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(previousContents.contains("first entry"))
        XCTAssertTrue(currentContents.contains(String(repeating: "x", count: 120)))
    }

    func testRecordNormalizesMultilineMessages() throws {
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportRoot)

        AppDebugLog.record(
            "first line\nsecond line\tthird",
            enabled: true,
            supportDirectory: supportRoot
        )

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("first line second line third"))
        XCTAssertFalse(contents.contains("\nsecond line"))
    }
}
