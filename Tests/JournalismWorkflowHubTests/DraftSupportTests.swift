import XCTest
@testable import JournalismWorkflowHub

final class DraftSupportTests: XCTestCase {
    func testLocalDraftFilenameUsesReadableProjectTitle() {
        XCTAssertEqual(
            DraftSupport.localDraftFilename(projectTitle: "Climate Story"),
            "Draft - Climate Story.docx"
        )
    }

    func testLocalDraftFilenameFallsBackWhenTitleIsEmpty() {
        XCTAssertEqual(
            DraftSupport.localDraftFilename(projectTitle: "   "),
            "Draft.docx"
        )
    }

    func testLocalDraftFilenameTruncatesVeryLongTitles() {
        let filename = DraftSupport.localDraftFilename(
            projectTitle: "De rechtbank weigert controlerende taak uit te voeren en gooit het op een akkoordje met de inspectie"
        )

        XCTAssertTrue(filename.hasPrefix("Draft - De rechtbank weigert controlerende taak uit te voeren en gooit"))
        XCTAssertTrue(filename.hasSuffix("....docx") || filename.hasSuffix("...docx"))
        XCTAssertLessThanOrEqual(filename.count, 90)
    }

    func testExtractGoogleDocIDFromFullURL() {
        XCTAssertEqual(
            DraftSupport.extractGoogleDocID(from: "https://docs.google.com/document/d/abcDEF_123/edit?usp=sharing"),
            "abcDEF_123"
        )
    }

    func testExtractGoogleDocIDFromRawValue() {
        XCTAssertEqual(
            DraftSupport.extractGoogleDocID(from: "abcDEF_1234567890_zyx"),
            "abcDEF_1234567890_zyx"
        )
    }

    func testExtractGoogleDocIDRejectsInvalidInput() {
        XCTAssertNil(DraftSupport.extractGoogleDocID(from: "not a google doc"))
    }

    func testDraftTemplatePreferencesRoundTripSavedURL() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil)
        let templateURL = tmp.appendingPathComponent("Template nieuw artikel.docx")
        try Data("draft".utf8).write(to: templateURL)

        DraftTemplatePreferences.persist(templateURL, defaults: defaults)

        XCTAssertEqual(
            DraftTemplatePreferences.savedURL(defaults: defaults)?.standardizedFileURL,
            templateURL.standardizedFileURL
        )
    }

    func testDraftTemplatePreferencesDoNotAutoReuseLegacyPathWithoutBookmark() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: nil)
        let templateURL = tmp.appendingPathComponent("Template nieuw artikel.docx")
        try Data("draft".utf8).write(to: templateURL)

        defaults.set(templateURL.path, forKey: DraftTemplatePreferences.scaffoldDraftTemplatePathKey)

        XCTAssertNil(DraftTemplatePreferences.savedURL(defaults: defaults))
        XCTAssertEqual(
            DraftTemplatePreferences.legacySavedURL(defaults: defaults)?.standardizedFileURL,
            templateURL.standardizedFileURL
        )
    }
}
