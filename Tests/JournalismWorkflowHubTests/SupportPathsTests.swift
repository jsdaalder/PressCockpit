import XCTest
@testable import JournalismWorkflowHub

final class SupportPathsTests: XCTestCase {
    func testBundledDemoWorkspaceExists() {
        let root = bundledDemoWorkspaceRoot()

        XCTAssertNotNil(root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root?.appendingPathComponent("Projects/2026/demo_story/README.md").path ?? ""))
    }

    func testCaptureDirectoryHelperCreatesSubdirectory() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureDirectory = journalismWorkflowHubCaptureDirectory(supportDirectory: tmp)

        XCTAssertEqual(captureDirectory.lastPathComponent, "capture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: captureDirectory.path))
    }

    func testBundledKnowledgeOpsScriptsExist() {
        let root = bundledKnowledgeOpsScriptsRoot()

        XCTAssertNotNil(root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root?.appendingPathComponent("scaffold_project.py").path ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root?.appendingPathComponent("refresh_knowledge_ops.py").path ?? ""))
    }
}
