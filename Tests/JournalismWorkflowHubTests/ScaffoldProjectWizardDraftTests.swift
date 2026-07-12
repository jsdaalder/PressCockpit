import XCTest
@testable import JournalismWorkflowHub

final class ScaffoldProjectWizardDraftTests: XCTestCase {
    func testSyncAdvancedDefaultsDoesNotPreseedPlaceholderPathBeforeTitleExists() {
        var draft = ScaffoldProjectWizardDraft()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")

        draft.syncAdvancedDefaults(workspaceRoot: workspaceRoot)

        XCTAssertEqual(draft.folderNameOverride, "")
        XCTAssertEqual(draft.projectRootOverride, "")
    }

    func testUpdatingWorkingTitleRefreshesDerivedFolderAndProjectRoot() {
        var draft = ScaffoldProjectWizardDraft()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")

        draft.updateWorkingTitle("Climate Story", workspaceRoot: workspaceRoot)

        XCTAssertEqual(draft.workingTitle, "Climate Story")
        XCTAssertEqual(draft.folderNameOverride, "climate_story")
        XCTAssertEqual(
            draft.projectRootOverride,
            workspaceRoot
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent(currentYearString(), isDirectory: true)
                .appendingPathComponent("climate_story", isDirectory: true)
                .path
        )
    }

    private func currentYearString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy"
        return formatter.string(from: .now)
    }
}
