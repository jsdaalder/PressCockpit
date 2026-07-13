import AppKit
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

    func testScaffoldDraftDataContainsTemplateSections() throws {
        let data = try DraftSupport.scaffoldDraftData(projectTitle: "Climate Story")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: tmp)

        let document = try NSAttributedString(
            url: tmp,
            options: [:],
            documentAttributes: nil
        )
        let text = document.string

        XCTAssertTrue(text.contains("Climate Story"))
        XCTAssertTrue(text.contains("[Nieuwsbrief]"))
        XCTAssertTrue(text.contains("[Socials]"))
        XCTAssertTrue(text.contains("[Kopsuggesties]"))
        XCTAssertTrue(text.contains("[Lead]"))
        XCTAssertTrue(text.contains("[Speedread]"))
        XCTAssertTrue(text.contains("Wat is het nieuws?"))
        XCTAssertTrue(text.contains("Waarom is dit belangrijk?"))
        XCTAssertTrue(text.contains("Hoe hebben we dit onderzocht?"))
        XCTAssertTrue(text.contains("[Auteurs]"))
        XCTAssertTrue(text.contains("[Dossier]"))
        XCTAssertTrue(text.contains("[Tags]"))
        XCTAssertTrue(text.contains("[Gerelateerde artikelen]"))
    }
}
