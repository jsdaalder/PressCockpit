import XCTest
@testable import JournalismWorkflowHub

final class SupportPathsTests: XCTestCase {
    func testBundledDemoWorkspaceExists() {
        let root = bundledDemoWorkspaceRoot()

        XCTAssertNotNil(root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root?.appendingPathComponent("Projects/2026/demo_story/README.md").path ?? ""))
    }
}
