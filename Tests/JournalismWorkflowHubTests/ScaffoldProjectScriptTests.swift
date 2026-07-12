import XCTest

final class ScaffoldProjectScriptTests: XCTestCase {
    func testScaffoldScriptAcceptsAndWritesProjectTypeField() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/knowledge_ops/scripts/scaffold_project.py")

        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), scriptURL.path)
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("--project-type"))
        XCTAssertTrue(contents.contains("--section-answer-1"))
        XCTAssertTrue(contents.contains("--section-answer-2"))
        XCTAssertTrue(contents.contains("--section-answer-3"))
        XCTAssertTrue(contents.contains("project_type: {project_type}"))
        XCTAssertTrue(contents.contains("Main reporting question:"))
        XCTAssertTrue(contents.contains("Expected pattern or claim:"))
        XCTAssertTrue(contents.contains("What this tool should unblock:"))
    }
}
