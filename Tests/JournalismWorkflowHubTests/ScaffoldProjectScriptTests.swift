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
        XCTAssertTrue(contents.contains("--activity-state"))
        XCTAssertTrue(contents.contains("--workflow-stage"))
        XCTAssertTrue(contents.contains("--inactive-reason"))
        XCTAssertTrue(contents.contains("--section-answer-1"))
        XCTAssertTrue(contents.contains("--section-answer-2"))
        XCTAssertTrue(contents.contains("--section-answer-3"))
        XCTAssertTrue(contents.contains("activity_state: {activity_state}"))
        XCTAssertTrue(contents.contains("workflow_stage: {workflow_stage}"))
        XCTAssertTrue(contents.contains("project_type: {project_type}"))
        XCTAssertTrue(contents.contains("Main reporting question:"))
        XCTAssertTrue(contents.contains("Expected pattern or claim:"))
        XCTAssertTrue(contents.contains("What this tool should unblock:"))
        XCTAssertTrue(contents.contains("scaffold-doc-summaries:start"))
    }

    func testScaffoldScriptAcceptsExplicitCanonicalProjectState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/scaffold_project.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/foi_waiting")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            scriptURL.path,
            "--project-root", projectRoot.path,
            "--title", "FOI Waiting",
            "--owner", "Jan",
            "--activity-state", "inactive",
            "--workflow-stage", "feasibility_study",
            "--inactive-reason", "waiting",
            "--project-type", "journalism",
            "--started", "2026-07-14",
            "--deliverable", "Waiting for records."
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let readme = try String(contentsOf: projectRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("activity_state: inactive"))
        XCTAssertTrue(readme.contains("workflow_stage: feasibility_study"))
        XCTAssertTrue(readme.contains("inactive_reason: waiting"))
        XCTAssertTrue(readme.contains("status: on_hold"))
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

    func testScaffoldScriptWritesUnindentedFrontmatterAndDocsOverview() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/scaffold_project.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/unindented_story")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            scriptURL.path,
            "--project-root", projectRoot.path,
            "--title", "Unindented Story",
            "--owner", "Jan",
            "--activity-state", "active",
            "--workflow-stage", "lead",
            "--project-type", "journalism",
            "--started", "2026-07-14",
            "--deliverable", "A short summary."
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let readme = try String(contentsOf: projectRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.hasPrefix("---\n"))
        XCTAssertFalse(readme.hasPrefix("        ---"))

        let overview = try String(
            contentsOf: projectRoot.appendingPathComponent("docs/docs_overview.md"),
            encoding: .utf8
        )
        XCTAssertTrue(overview.hasPrefix("# Docs Overview\n"))
        XCTAssertFalse(overview.hasPrefix("        # Docs Overview"))
    }

    func testBuildProjectReadmePreservesTrustedFrontmatterFields() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/build_project_readme.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        activity_state: inactive
        workflow_stage: feasibility_study
        inactive_reason: waiting
        status: on_hold
        project_type: data_journalism
        dossier: voedselcrisis_2027
        safety: local_sensitive
        google_drive_folder_url: https://drive.google.com/drive/folders/demo
        owner: Jan
        started: 2026-07-01
        topics: ["food"]
        entities: ["WFP"]
        deliverable: A sharp story
        ---

        # Demo Story

        Existing README body.
        """.write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            scriptURL.path,
            "--project-root", projectRoot.path,
            "--write-readme",
            "--overwrite",
            "--skip-placeholder-cache"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let updatedReadme = try String(contentsOf: projectRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(updatedReadme.contains("project_type: data_journalism"))
        XCTAssertTrue(updatedReadme.contains("dossier: voedselcrisis_2027"))
        XCTAssertTrue(updatedReadme.contains("safety: local_sensitive"))
        XCTAssertTrue(updatedReadme.contains("google_drive_folder_url: https://drive.google.com/drive/folders/demo"))
        XCTAssertTrue(updatedReadme.contains("activity_state: inactive"))
        XCTAssertTrue(updatedReadme.contains("workflow_stage: feasibility_study"))
        XCTAssertTrue(updatedReadme.contains("inactive_reason: waiting"))
        XCTAssertTrue(updatedReadme.contains("status: on_hold"))
    }

    func testBuildProjectReadmeRecomputesLegacyStatusFromCanonicalProjectState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/build_project_readme.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/recomputed_status_story")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Recomputed Status Story
        activity_state: inactive
        workflow_stage: feasibility_study
        inactive_reason: waiting
        status: active
        project_type: journalism
        safety: unknown
        owner: Jan
        started: 2026-07-01
        topics: []
        entities: []
        deliverable: Waiting for records
        ---

        # Recomputed Status Story

        Existing README body.
        """.write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            scriptURL.path,
            "--project-root", projectRoot.path,
            "--write-readme",
            "--overwrite",
            "--skip-placeholder-cache"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let updatedReadme = try String(contentsOf: projectRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(updatedReadme.contains("activity_state: inactive"))
        XCTAssertTrue(updatedReadme.contains("workflow_stage: feasibility_study"))
        XCTAssertTrue(updatedReadme.contains("inactive_reason: waiting"))
        XCTAssertTrue(updatedReadme.contains("status: on_hold"))
        XCTAssertFalse(updatedReadme.contains("status: active"))
    }

    func testSummarizeScaffoldDocsParsesLocalModelJSONWithLiteralControlCharacters() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/summarize_scaffold_docs.py")

        let snippet = #"""
        import importlib.util
        import json
        import pathlib
        import sys

        script_path = pathlib.Path(sys.argv[1])
        spec = importlib.util.spec_from_file_location("summarize_scaffold_docs", script_path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)

        payload = """{
          "title": "Imported notes",
          "summary": "First line
        Second line\tTabbed",
          "project_relevance": "Relevant to the working hypothesis.",
          "research_questions": ["What needs verification next?"],
          "follow_up": ["Compare against the README assumptions."],
          "cautions": "Treat as a working note."
        }"""
        parsed = module.parse_summary_payload(payload)
        assert parsed["summary"] == "First line\nSecond line\tTabbed"
        print(json.dumps(parsed))
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", snippet, scriptURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(stdout.contains("\\n"))
        XCTAssertTrue(stdout.contains("\\t"))
    }

    func testScaffoldSummaryScriptSanitizesAnsiSequencesBeforeWritingOverview() throws {
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

        let importedURL = docsRoot.appendingPathComponent("research_notes.md")
        let pollutedLead = "Tata Steel levert ruim een tiende\u{001B}[4D\u{001B}[K aan de Verenigde Staten."
        try """
        \(pollutedLead)

        Supporting detail with a form-feed character \u{000C} that should not leak through.
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
        XCTAssertTrue(overview.contains("Working summary from research_notes.md: Tata Steel levert ruim een tiende aan de Verenigde Staten."))
        XCTAssertFalse(overview.contains("\u{001B}"))
        XCTAssertFalse(overview.contains("[4D"))
        XCTAssertFalse(overview.contains("\u{000C}"))
    }

    func testScaffoldSummaryScriptWritesPerFileNotesFromJSON() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = root
            .appendingPathComponent("Sources/JournalismWorkflowHub/Resources/knowledge_ops/scripts/summarize_scaffold_docs.py")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectRoot = tmp.appendingPathComponent("Projects/2026/review_notes_story")
        let docsRoot = projectRoot.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        # Review Notes Story

        This README explains the project direction.
        """.write(to: projectRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let importedURL = docsRoot.appendingPathComponent("research_notes.md")
        try """
        Lead finding from the imported note.
        """.write(to: importedURL, atomically: true, encoding: .utf8)

        let reviewNotesURL = tmp.appendingPathComponent("review_notes.json")
        let payload = [
            importedURL.path: "Pull this figure into facts after manual verification."
        ]
        let reviewNotesData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try reviewNotesData.write(to: reviewNotesURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            scriptURL.path,
            "--project-root", projectRoot.path,
            "--imported-path", importedURL.path,
            "--review-notes-file", reviewNotesURL.path
        ]

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
        XCTAssertTrue(overview.contains("- Note: Pull this figure into facts after manual verification."))
    }
}
