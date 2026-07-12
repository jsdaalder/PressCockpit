import XCTest
@testable import JournalismWorkflowHub

final class OnboardingSupportTests: XCTestCase {
    func testWorkspaceValidatorFlagsMissingRequiredDirectories() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Projects"), withIntermediateDirectories: true, attributes: nil)

        let report = WorkspaceStructureValidator.validateExistingWorkspace(at: tmp)

        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.blockingIssues.contains(where: { $0.message.contains("Resources") }))
    }

    func testWorkspaceBootstrapperCreatesBaseStructure() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try WorkspaceBootstrapper(workspaceRoot: tmp).createBaseStructure()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Projects").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Areas").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Resources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Archives").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("AGENTS.md").path))
    }
}
