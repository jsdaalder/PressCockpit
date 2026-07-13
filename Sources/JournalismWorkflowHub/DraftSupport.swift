import Foundation

enum DraftSupport {
    static let defaultGoogleDraftPointerFilename = "Draft.gdoc"
    private static let suggestedTemplateRelativePath = "Downloads/Template nieuw artikel.docx"
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

    static func suggestedTemplateURL(fileManager: FileManager = .default) -> URL? {
        let candidate = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(suggestedTemplateRelativePath)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
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
}

struct DraftTemplatePreferences {
    static let scaffoldDraftTemplatePathKey = "scaffoldDraftTemplatePath"
    static let scaffoldDraftTemplateBookmarkKey = "scaffoldDraftTemplateBookmark"

    static func savedURL(defaults: UserDefaults = .standard, fileManager: FileManager = .default) -> URL? {
        if let bookmarkData = defaults.data(forKey: scaffoldDraftTemplateBookmarkKey) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    persist(resolvedURL, defaults: defaults)
                }
                let standardizedURL = resolvedURL.standardizedFileURL
                if fileManager.fileExists(atPath: standardizedURL.path) {
                    return standardizedURL
                }
            }

            defaults.removeObject(forKey: scaffoldDraftTemplateBookmarkKey)
        }

        return nil
    }

    static func legacySavedURL(defaults: UserDefaults = .standard, fileManager: FileManager = .default) -> URL? {
        guard let savedPath = defaults.string(forKey: scaffoldDraftTemplatePathKey),
              !savedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let standardizedURL = URL(fileURLWithPath: savedPath).standardizedFileURL
        return fileManager.fileExists(atPath: standardizedURL.path) ? standardizedURL : nil
    }

    static func persist(_ url: URL, defaults: UserDefaults = .standard) {
        let standardizedURL = url.standardizedFileURL
        defaults.set(standardizedURL.path, forKey: scaffoldDraftTemplatePathKey)

        if let bookmarkData = try? standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmarkData, forKey: scaffoldDraftTemplateBookmarkKey)
        } else {
            defaults.removeObject(forKey: scaffoldDraftTemplateBookmarkKey)
        }
    }
}
