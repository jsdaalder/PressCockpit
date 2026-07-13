import XCTest

final class ScaffoldProjectScriptTests: XCTestCase {
    func testScaffoldScriptAcceptsAndWritesProjectTypeField() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/scaffold_project.py")

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
        XCTAssertTrue(contents.contains("scaffold-doc-summaries:start"))
    }

    func testBundledKnowledgeOpsScriptsDoNotHardcodeJanWorkspacePath() throws {
        let scriptsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts")

        let scriptPaths = try FileManager.default.contentsOfDirectory(
            at: scriptsRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "py" }

        XCTAssertFalse(scriptPaths.isEmpty)
        for scriptPath in scriptPaths {
            let contents = try String(contentsOf: scriptPath, encoding: .utf8)
            XCTAssertFalse(contents.contains("/Users/jandaalder/My Drive/coding_projects"), scriptPath.lastPathComponent)
        }
    }

    func testScaffoldSummaryScriptUpdatesManagedDocsOverviewSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/summarize_scaffold_docs.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/demo_story")
        let docsRoot = projectRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        # Demo Story

        This README explains the project direction.
        """.write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        Draft context that should also be read before imported files are summarized.
        """.write(to: projectRoot.appendingPathComponent("Draft.md"), atomically: true, encoding: .utf8)

        try """
        Pitch context that sharpens the research question.
        """.write(to: projectRoot.appendingPathComponent("Pitch.md"), atomically: true, encoding: .utf8)

        try """
        # Docs Overview

        ## Imported document synthesis

        <!-- scaffold-doc-summaries:start -->
        _Old placeholder._
        <!-- scaffold-doc-summaries:end -->

        ## Next steps

        - Keep going.
        """.write(to: docsRoot.appendingPathComponent("docs_overview.md"), atomically: true, encoding: .utf8)

        let importedURL = docsRoot.appendingPathComponent("research_notes.md")
        try """
        Lead finding from the imported note.

        Supporting detail that should appear in a working summary.
        """.write(to: importedURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path, "--project-root", projectRoot.path, "--imported-path", importedURL.path]

        var environment = ProcessInfo.processInfo.environment
        environment["JWH_SCAFFOLD_SUMMARY_FAKE"] = "1"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let overview = try String(contentsOf: docsRoot.appendingPathComponent("docs_overview.md"), encoding: .utf8)
        XCTAssertTrue(overview.contains("### Context used"))
        XCTAssertTrue(overview.contains("README: `README.md`"))
        XCTAssertTrue(overview.contains("Draft: `Draft.md`"))
        XCTAssertTrue(overview.contains("Pitch: `Pitch.md`"))
        XCTAssertTrue(overview.contains("Working summary from research_notes.md"))
        XCTAssertFalse(overview.contains("_Old placeholder._"))
    }
}
