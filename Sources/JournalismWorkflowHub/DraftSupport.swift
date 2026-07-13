import AppKit
import Foundation

enum DraftSupport {
    static let defaultGoogleDraftPointerFilename = "Draft.gdoc"
    private static let maxDraftTitleLength = 72

    static func localDraftFilename(projectTitle: String) -> String {
        let cleanedTitle = truncatedDraftTitle(cleanedProjectTitle(projectTitle))
        if cleanedTitle.isEmpty {
            return "Draft.docx"
        }
        return "Draft - \(cleanedTitle).docx"
    }

    static func preferredGoogleDraftPointerURL(for item: WorkspaceItem) -> URL {
        if let existingPointer = item.documents.first(where: { $0.provider == .googleDocPointer && $0.role == .draft }) {
            return existingPointer.url
        }
        return item.url.appendingPathComponent(defaultGoogleDraftPointerFilename)
    }

    static func extractGoogleDocID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = trimmed.range(of: #"/document/d/([a-zA-Z0-9\-_]+)"#, options: .regularExpression) {
            let fragment = String(trimmed[match])
            return fragment
                .replacingOccurrences(of: "/document/d/", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        if trimmed.range(of: #"^[a-zA-Z0-9\-_]{20,}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        return nil
    }

    static func googleDraftPointerContents(docID: String) -> String {
        """
        {"doc_id":"\(docID)","resource_key":"","email":""}
        """
    }

    static func scaffoldDraftData(projectTitle: String) throws -> Data {
        let document = NSMutableAttributedString()

        if !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendParagraph(
                projectTitle,
                to: document,
                font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                spacingBefore: 0,
                spacingAfter: 18
            )
        }

        appendSection(
            "[Nieuwsbrief]",
            body: ["Schrijf hier een korte nieuwsbriefsamenvatting."],
            to: document
        )
        appendSection(
            "[Socials]",
            body: ["Schrijf hier korte social copy."],
            to: document
        )
        appendSection(
            "[Kopsuggesties]",
            bullets: ["Kopsuggestie 1"],
            to: document
        )
        appendSection(
            "[Lead]",
            body: ["Schrijf hier de lead."],
            to: document
        )
        appendSection(
            "[Speedread]",
            body: [
                "Wat is het nieuws?",
                "Waarom is dit belangrijk?",
                "Hoe hebben we dit onderzocht?"
            ],
            bulletGroups: [
                ["Kernpunt"],
                ["Belang"],
                ["Onderzoeksmethode"]
            ],
            to: document
        )
        appendSection(
            "[Auteurs]",
            body: [NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Auteur" : NSFullUserName()],
            to: document
        )
        appendSection(
            "[Dossier]",
            body: ["Vul hier het dossier in."],
            to: document
        )
        appendSection(
            "[Tags]",
            body: ["Vul hier tags in."],
            to: document
        )
        appendSection(
            "[Gerelateerde artikelen]",
            bullets: ["Artikel 1", "Artikel 2", "Artikel 3"],
            to: document,
            addDivider: true
        )

        return try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
    }

    private static func cleanedProjectTitle(_ projectTitle: String) -> String {
        let pieces = projectTitle
            .components(separatedBy: CharacterSet(charactersIn: "/:\n\r\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = pieces.joined(separator: " - ")
        return joined.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncatedDraftTitle(_ title: String) -> String {
        guard title.count > maxDraftTitleLength else {
            return title
        }

        let prefix = String(title.prefix(maxDraftTitleLength))
        let candidate: String
        if let split = prefix.lastIndex(of: " "), split > prefix.startIndex {
            candidate = String(prefix[..<split])
        } else {
            candidate = prefix
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(title.prefix(maxDraftTitleLength)) : "\(trimmed)..."
    }

    private static func appendSection(
        _ heading: String,
        body: [String] = [],
        bullets: [String] = [],
        bulletGroups: [[String]] = [],
        to document: NSMutableAttributedString,
        addDivider: Bool = false
    ) {
        appendParagraph(
            heading,
            to: document,
            font: NSFont.systemFont(ofSize: 14, weight: .bold),
            spacingBefore: document.length == 0 ? 0 : 14,
            spacingAfter: 8
        )

        for (index, paragraph) in body.enumerated() {
            appendParagraph(
                paragraph,
                to: document,
                font: NSFont.systemFont(ofSize: 11),
                spacingBefore: 0,
                spacingAfter: (index == body.count - 1 && bullets.isEmpty && bulletGroups.isEmpty) ? 12 : 6
            )

            if index < bulletGroups.count {
                for bullet in bulletGroups[index] {
                    appendBullet(bullet, to: document)
                }
                appendSpacer(to: document, spacingAfter: 8)
            }
        }

        if body.count < bulletGroups.count {
            for group in bulletGroups.dropFirst(body.count) {
                for bullet in group {
                    appendBullet(bullet, to: document)
                }
                appendSpacer(to: document, spacingAfter: 8)
            }
        }

        for bullet in bullets {
            appendBullet(bullet, to: document)
        }

        if !bullets.isEmpty {
            appendSpacer(to: document, spacingAfter: 12)
        } else if body.isEmpty && bulletGroups.isEmpty {
            appendSpacer(to: document, spacingAfter: 12)
        }

        if addDivider {
            appendDivider(to: document)
        }
    }

    private static func appendParagraph(
        _ text: String,
        to document: NSMutableAttributedString,
        font: NSFont,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = spacingBefore
        paragraphStyle.paragraphSpacing = spacingAfter
        paragraphStyle.lineSpacing = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        document.append(NSAttributedString(string: text + "\n", attributes: attributes))
    }

    private static func appendBullet(_ text: String, to document: NSMutableAttributedString) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 18
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.paragraphSpacing = 6
        paragraphStyle.lineSpacing = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle
        ]
        document.append(NSAttributedString(string: "•\t\(text)\n", attributes: attributes))
    }

    private static func appendSpacer(to document: NSMutableAttributedString, spacingAfter: CGFloat) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = spacingAfter
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle
        ]
        document.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    private static func appendDivider(to document: NSMutableAttributedString) {
        appendParagraph(
            String(repeating: "_", count: 48),
            to: document,
            font: NSFont.systemFont(ofSize: 11),
            spacingBefore: 0,
            spacingAfter: 12
        )
    }
}
