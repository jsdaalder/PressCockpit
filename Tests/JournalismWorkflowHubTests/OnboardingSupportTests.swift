import XCTest
@testable import JournalismWorkflowHub

final class OnboardingSupportTests: XCTestCase {
    func testSwitchWorkspaceLaunchModeStartsAtWorkspaceSelectionStep() {
        XCTAssertEqual(OnboardingLaunchMode.switchWorkspace.initialStep, .workspaceLocation)
        XCTAssertEqual(OnboardingLaunchMode.switchWorkspace.steps, [.workspaceLocation, .workspaceSetup, .finish])
    }

    func testCreateWorkspaceDraftRequiresExplicitConfirmationWhenAnotherValidWorkspaceExists() {
        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: "/tmp/new-workspace")
        draft.startMode = .createWorkspace

        XCTAssertTrue(
            draft.needsSeparateWorkspaceConfirmation(
                configuredWorkspacePath: "/tmp/existing-workspace",
                configuredWorkspaceLooksValid: true
            )
        )
        XCTAssertFalse(
            draft.canProceedWithNewWorkspaceCreation(
                selectedPathAlreadyLooksLikeWorkspace: false,
                needsExtraConfirmation: true
            )
        )

        draft.confirmedSeparateWorkspaceCreation = true

        XCTAssertTrue(
            draft.canProceedWithNewWorkspaceCreation(
                selectedPathAlreadyLooksLikeWorkspace: false,
                needsExtraConfirmation: true
            )
        )
    }

    func testCreateWorkspaceDraftBlocksWhenSelectedPathAlreadyLooksLikeWorkspace() {
        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: "/tmp/existing-workspace")
        draft.startMode = .createWorkspace
        draft.createBaseStructure = true
        draft.confirmedSeparateWorkspaceCreation = true

        XCTAssertFalse(
            draft.canProceedWithNewWorkspaceCreation(
                selectedPathAlreadyLooksLikeWorkspace: true,
                needsExtraConfirmation: false
            )
        )
    }

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

    func testWorkspaceValidatorCanRecognizeExistingWorkspaceShape() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try WorkspaceBootstrapper(workspaceRoot: tmp).createBaseStructure()

        XCTAssertTrue(WorkspaceStructureValidator.looksLikeExistingWorkspace(at: tmp))
    }

    func testOnboardingPreferencesPersistAndReadDocumentMode() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: "/tmp/workspace")
        draft.documentMode = .googleDocs

        OnboardingPreferences.persist(draft: draft, defaults: defaults)

        XCTAssertEqual(OnboardingPreferences.documentMode(defaults: defaults), .googleDocs)
    }

    func testOnboardingPreferencesDefaultDiagnosticsLoggingEnabled() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(OnboardingPreferences.diagnosticsLoggingEnabled(defaults: defaults))
    }

    func testOnboardingPreferencesPersistAndReadDiagnosticsLoggingChoice() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: "/tmp/workspace")
        draft.diagnosticsLoggingEnabled = true

        OnboardingPreferences.persist(draft: draft, defaults: defaults)

        XCTAssertTrue(OnboardingPreferences.diagnosticsLoggingEnabled(defaults: defaults))
    }

    func testOnboardingPreferencesDefaultToSystemAppearance() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(OnboardingPreferences.appAppearancePreference(defaults: defaults), .system)
    }

    func testOnboardingPreferencesPersistAndReadAppearancePreference() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        OnboardingPreferences.setAppAppearancePreference(.dark, defaults: defaults)

        XCTAssertEqual(OnboardingPreferences.appAppearancePreference(defaults: defaults), .dark)
    }
}
