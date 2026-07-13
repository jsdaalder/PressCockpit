import XCTest
@testable import JournalismWorkflowHub

@MainActor
final class AppStoreNavigationTests: XCTestCase {
    func testBackAndForwardTrackVisitedPages() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        XCTAssertEqual(store.selection, .overview)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.select(.workspace(project.id))
        store.select(.publication)

        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.goBack()

        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)

        store.goBack()

        XCTAssertEqual(store.selection, .overview)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)

        store.goForward()
        XCTAssertEqual(store.selection, .workspace(project.id))

        store.goForward()
        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
    }

    func testSelectingNewPageClearsForwardHistory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        store.select(.workspace(project.id))
        store.select(.publication)
        store.goBack()

        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertTrue(store.canNavigateForward)

        store.select(.overview)

        XCTAssertEqual(store.selection, .overview)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.goForward()
        XCTAssertEqual(store.selection, .overview)
    }

    func testCaptureSelectionParticipatesInNavigationHistory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        )

        store.select(.capture)
        store.select(.publication)

        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)

        store.goBack()
        XCTAssertEqual(store.selection, .capture)

        store.goBack()
        XCTAssertEqual(store.selection, .overview)
    }

    func testAppStoreInitializesEmptyCaptureShell() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        XCTAssertTrue(store.captureRecords.isEmpty)
        XCTAssertEqual(captureStore.load()?.records, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: captureStore.storageDirectory.path))
    }

    func testReusingExistingScaffoldProjectRoutesIntoPostCreateState() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .now
        )

        let postCreateState = try XCTUnwrap(store.scaffoldPostCreateState)
        XCTAssertEqual(postCreateState.mode, .reused)
        XCTAssertEqual(postCreateState.projectRoot, project.path)
        XCTAssertTrue(postCreateState.shouldAutoPromptForDocuments)
        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertEqual(store.statusMessage, "Using existing project. Add documents now.")
    }

    func testReusingExistingScaffoldProjectWithoutImmediateDocumentsKeepsPromptDisabled() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .later
        )

        let postCreateState = try XCTUnwrap(store.scaffoldPostCreateState)
        XCTAssertEqual(postCreateState.mode, .reused)
        XCTAssertFalse(postCreateState.shouldAutoPromptForDocuments)
        XCTAssertEqual(store.statusMessage, "Using existing project")
    }

    func testCompleteOnboardingStartNewProjectSelectsScaffoldWorkflow() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .createWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.createBaseStructure = true
        draft.confirmedSeparateWorkspaceCreation = true
        draft.firstAction = .startNewProject

        try store.completeOnboarding(using: draft)

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.selection, .workflow("scaffold-project"))
        XCTAssertEqual(store.statusMessage, "Workspace ready")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("Projects").path))
    }

    func testReopenOnboardingResetsCompletionState() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .existingWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.firstAction = .openOverview

        try store.completeOnboarding(using: draft)
        XCTAssertTrue(store.hasCompletedOnboarding)

        store.reopenOnboarding()

        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testImportCaptureItemsCopiesFilesAndMarksThemForReview() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let firstFile = incomingRoot.appendingPathComponent("source_story.pdf")
        let secondFile = incomingRoot.appendingPathComponent("interview_notes.md")
        try Data("pdf".utf8).write(to: firstFile)
        try Data("# Notes".utf8).write(to: secondFile)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [firstFile, secondFile])
        }

        XCTAssertEqual(store.captureRecords.count, 2)
        XCTAssertTrue(store.captureRecords.allSatisfy { $0.state == .needsReview })
        XCTAssertEqual(Set(store.captureRecords.compactMap(\.originalSourcePath)), Set([firstFile.path, secondFile.path]))

        for record in store.captureRecords {
            let importedPath = try XCTUnwrap(record.importedStoragePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: importedPath))
        }

        let persisted = try XCTUnwrap(captureStore.loadRecords())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy { $0.state == .needsReview })
    }

    func testImportCaptureFolderPreservesFolderTypeAndCopiesDirectory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderURL = incomingRoot.appendingPathComponent("bauer_interview")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        try "Transcript".write(to: folderURL.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [folderURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.captureType, .folder)
        XCTAssertEqual(record.state, .needsReview)

        let importedPath = try XCTUnwrap(record.importedStoragePath)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: importedPath).appendingPathComponent("transcript.txt").path))
    }

    func testSaveQuickCaptureNoteCreatesMarkdownRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("Check whether this source has KNMI data access.")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.captureType, .note)
        XCTAssertEqual(record.state, .needsReview)
        XCTAssertEqual(record.displayName, "Check whether this source has KNMI data access.")

        let notePath = try XCTUnwrap(record.importedStoragePath)
        XCTAssertTrue(notePath.hasSuffix(".md"))
        let noteContents = try String(contentsOfFile: notePath)
        XCTAssertEqual(noteContents, "Check whether this source has KNMI data access.")
    }

    func testFailedCaptureImportRemainsVisibleInQueue() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.pdf")

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [missingFile])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.state, .failed)
        XCTAssertNil(record.importedStoragePath)
        XCTAssertNotNil(record.failureDescription)
    }

    func testSetCaptureUserNotePersistsOnRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("A short note")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        store.setCaptureUserNote("Important context for filing", for: record.id)

        let updated = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(updated.userNote, "Important context for filing")
        XCTAssertEqual(captureStore.loadRecords()?.first?.userNote, "Important context for filing")
    }

    func testAssignCaptureRecordCopiesFileIntoProjectDocsAndMarksAssigned() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let fileURL = incomingRoot.appendingPathComponent("source_story.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [fileURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let project = try XCTUnwrap(store.captureAssignableProjects.first)

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: project, note: "Useful for the main story.")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        XCTAssertEqual(assigned.userNote, "Useful for the main story.")
        XCTAssertEqual(assigned.assignedProjectPath, project.path)
        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(destinationPath.contains("/docs/"))
        XCTAssertEqual(store.captureQueueRecords.count, 0)
        XCTAssertEqual(store.captureAssignedRecords.count, 1)
    }

    func testAssignCaptureRecordCopiesFolderIntoProjectDocs() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderURL = incomingRoot.appendingPathComponent("bauer_interview")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        try "Transcript".write(to: folderURL.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [folderURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let project = try XCTUnwrap(store.captureAssignableProjects.first)

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: project, note: "")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: destinationPath).appendingPathComponent("transcript.txt").path))
    }

    func testDefaultOnboardingDraftUsesPersistedDocumentMode() {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let defaults = UserDefaults.standard
        defaults.set(OnboardingDocumentMode.googleDocs.rawValue, forKey: OnboardingPreferences.documentModeKey)

        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            demoWorkspaceRoot: nil
        ))

        XCTAssertEqual(store.defaultOnboardingDraft.documentMode, .googleDocs)
    }

    private func waitForCaptureAsyncWork(_ operation: @escaping @MainActor () async -> Void) {
        let expectation = expectation(description: "async capture work")
        Task {
            await operation()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    private func makeWorkspaceRoot() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        status: active
        project_type: journalism
        started: 2026-07-06
        deliverable: Story
        ---

        # Demo Story

        A project used to test app navigation history.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        # AGENTS

        Keep this project local-first during tests.
        """.write(to: project.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        return tmp
    }
}
