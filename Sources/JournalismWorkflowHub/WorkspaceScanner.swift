import Foundation

struct WorkspaceScanner {
    let workspaceRoot: URL

    private let ignoredDirectories: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        ".venv",
        ".pytest_cache",
        "__pycache__",
        "node_modules",
        ".next",
        "dist",
        "build",
        ".DS_Store"
    ]

    private let documentExtensions: Set<String> = [
        "md", "txt", "pdf", "srt", "rtf", "docx", "html", "ics", "gdoc", "csv", "xls", "xlsx"
    ]

    func scan() -> WorkspaceSnapshot {
        let items = discoverItems()
        let publication = PublicationStore(workspaceRoot: workspaceRoot).load()
        return WorkspaceSnapshot(scannedAt: .now, items: items, publication: publication)
    }

    private func discoverItems() -> [WorkspaceItem] {
        let fm = FileManager.default
        let roots: [(WorkspaceSection, URL)] = [
            (.projects, workspaceRoot.appendingPathComponent("Projects")),
            (.areas, workspaceRoot.appendingPathComponent("Areas")),
            (.resources, workspaceRoot.appendingPathComponent("Resources")),
            (.archives, workspaceRoot.appendingPathComponent("Archives"))
        ]

        var items: [WorkspaceItem] = []
        for (section, root) in roots where fm.fileExists(atPath: root.path) {
            items.append(contentsOf: discoverItems(in: root, section: section, depth: 0))
        }

        return items.sorted {
            if $0.section.rawValue != $1.section.rawValue {
                return $0.section.rawValue < $1.section.rawValue
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func discoverItems(in directory: URL, section: WorkspaceSection, depth: Int) -> [WorkspaceItem] {
        let fm = FileManager.default
        guard depth <= 6 else { return [] }

        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [WorkspaceItem] = []
        if let item = makeItem(for: directory, section: section) {
            items.append(item)
        }

        for child in children {
            if shouldIgnore(child) {
                continue
            }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            items.append(contentsOf: discoverItems(in: child, section: section, depth: depth + 1))
        }

        return items
    }

    private func shouldIgnore(_ url: URL) -> Bool {
        ignoredDirectories.contains(url.lastPathComponent)
    }

    private func makeItem(for directory: URL, section: WorkspaceSection) -> WorkspaceItem? {
        let fm = FileManager.default
        let readmeURL = directory.appendingPathComponent("README.md")
        guard fm.fileExists(atPath: readmeURL.path) else {
            return nil
        }
        let agentsURL = directory.appendingPathComponent("AGENTS.md")

        let readmeText = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
        let agentsText = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""
        let (frontmatter, body) = parseFrontmatter(readmeText)
        let title = extractTitle(from: frontmatter, body: body, fallback: directory.lastPathComponent)
        let summary = extractSummary(from: body)
        let agentsSummary = extractAgentsSummary(from: agentsText)
        let projectType = classifyProjectType(
            section: section,
            directory: directory,
            frontmatter: frontmatter,
            readmeBody: body,
            agentsText: agentsText
        )
        let displayStateLabel = inferLifecycleStage(section: section, frontmatter: frontmatter, readmeBody: body)
        let safetyPosture = inferSafetyPosture(
            section: section,
            projectType: projectType,
            frontmatter: frontmatter,
            directory: directory,
            readmeBody: body,
            agentsText: agentsText
        )
        let counts = countDirectChildren(at: directory)
        let documents = discoverDocuments(in: directory)

        return WorkspaceItem(
            id: directory.path,
            section: section,
            path: directory.path,
            readmePath: readmeURL.path,
            agentsPath: fm.fileExists(atPath: agentsURL.path) ? agentsURL.path : nil,
            title: title,
            summary: summary,
            agentsSummary: agentsSummary,
            frontmatter: frontmatter,
            googleDriveFolderURL: extractGoogleDriveFolderURL(from: frontmatter, body: body),
            projectType: projectType,
            displayStateLabel: displayStateLabel,
            safetyPosture: safetyPosture,
            directFileCount: counts.fileCount,
            directFolderCount: counts.folderCount,
            markdownFiles: counts.markdownCount,
            pdfFiles: counts.pdfCount,
            gdocFiles: counts.gdocCount,
            csvFiles: counts.csvCount,
            xlsxFiles: counts.xlsxCount,
            documents: documents
        )
    }

    private func discoverDocuments(in directory: URL) -> [WorkspaceDocument] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            if shouldIgnore(child) || child.lastPathComponent == "README.md" || child.lastPathComponent == "AGENTS.md" {
                return nil
            }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return nil
            }

            let fileExtension = child.pathExtension.lowercased()
            guard documentExtensions.contains(fileExtension) else {
                return nil
            }

            if fileExtension == "gdoc" {
                return parseGDocDocument(at: child, projectRoot: directory)
            }

            return WorkspaceDocument(
                id: child.path,
                path: child.path,
                title: child.deletingPathExtension().lastPathComponent,
                fileExtension: fileExtension,
                provider: .localFile,
                role: inferDocumentRole(from: child.deletingPathExtension().lastPathComponent),
                cacheState: .localFile,
                externalURL: nil,
                docID: nil,
                cachePath: nil,
                cachedOn: nil
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func countDirectChildren(at directory: URL) -> (
        fileCount: Int,
        folderCount: Int,
        markdownCount: Int,
        pdfCount: Int,
        gdocCount: Int,
        csvCount: Int,
        xlsxCount: Int
    ) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, 0, 0, 0, 0, 0)
        }

        var fileCount = 0
        var folderCount = 0
        var markdownCount = 0
        var pdfCount = 0
        var gdocCount = 0
        var csvCount = 0
        var xlsxCount = 0

        for child in children {
            if shouldIgnore(child) {
                continue
            }
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                folderCount += 1
                continue
            }
            fileCount += 1
            switch child.pathExtension.lowercased() {
            case "md":
                markdownCount += 1
            case "pdf":
                pdfCount += 1
            case "gdoc":
                gdocCount += 1
            case "csv":
                csvCount += 1
            case "xlsx", "xls":
                xlsxCount += 1
            default:
                break
            }
        }

        return (fileCount, folderCount, markdownCount, pdfCount, gdocCount, csvCount, xlsxCount)
    }

    private func parseGDocDocument(at url: URL, projectRoot: URL) -> WorkspaceDocument {
        let pointerText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let data = (try? JSONSerialization.jsonObject(with: Data(pointerText.utf8))) as? [String: Any] ?? [:]
        let docID = (data["doc_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cacheURL = projectRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("_derived")
            .appendingPathComponent("google_docs")
            .appendingPathComponent("\(sanitizeFilename(url.deletingPathExtension().lastPathComponent)).md")
        let cacheText = (try? String(contentsOf: cacheURL, encoding: .utf8)) ?? ""
        let (cacheMetadata, _) = parseFrontmatter(cacheText)
        let cacheState = inferGDocCacheState(from: cacheMetadata, cacheText: cacheText, cacheExists: FileManager.default.fileExists(atPath: cacheURL.path))
        let cachedOn = cacheMetadata["cached_on"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalURL = docID.isEmpty ? nil : "https://docs.google.com/document/d/\(docID)/edit"

        return WorkspaceDocument(
            id: url.path,
            path: url.path,
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: inferDocumentRole(from: url.deletingPathExtension().lastPathComponent),
            cacheState: cacheState,
            externalURL: externalURL,
            docID: docID.isEmpty ? nil : docID,
            cachePath: FileManager.default.fileExists(atPath: cacheURL.path) ? cacheURL.path : nil,
            cachedOn: cachedOn?.isEmpty == true ? nil : cachedOn
        )
    }

    private func inferGDocCacheState(from metadata: [String: String], cacheText: String, cacheExists: Bool) -> WorkspaceDocumentCacheState {
        guard cacheExists else { return .notCached }
        let mode = metadata["cache_mode"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch mode {
        case "fetched_body":
            return .cachedText
        case "structured_summary":
            return .cachedSummary
        case "title_stub":
            return .titleStub
        case "placeholder":
            return .placeholder
        case "":
            if cacheText.contains("Replace this placeholder with fetched Google Doc content.") {
                return .placeholder
            }
            return cacheText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unknown : .cachedText
        default:
            return .unknown
        }
    }

    private func inferDocumentRole(from title: String) -> WorkspaceDocumentRole {
        let normalized = title
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        if normalized.contains("pitch") {
            return .pitch
        }
        if normalized.contains("draft") || normalized.contains("artikel") || normalized.contains("story") || normalized.contains("tekst") {
            return .draft
        }
        if normalized.contains("research") || normalized.contains("onderzoek") || normalized.contains("timeline") || normalized.contains("tijdlijn") {
            return .research
        }
        if normalized.contains("interview") || normalized.contains("wederhoor") || normalized.contains("gesprek") {
            return .interviews
        }
        if normalized.contains("transcript") || normalized.contains("verslag") {
            return .transcript
        }
        if normalized.contains("note") || normalized.contains("notitie") || normalized.contains("notes") || normalized.contains("aantekening") {
            return .notes
        }
        if normalized.contains("source") || normalized.contains("bron") || normalized.contains("bronnen") {
            return .source
        }
        if normalized.contains("data") || normalized.contains("sheet") || normalized.contains("dataset") {
            return .data
        }
        if normalized.contains("reference") || normalized.contains("memo") || normalized.contains("brief") {
            return .reference
        }
        return .general
    }

    private func sanitizeFilename(_ text: String) -> String {
        let normalized = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let mappedScalars = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(mappedScalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "untitled" : collapsed
    }

    private func parseFrontmatter(_ text: String) -> ([String: String], String) {
        let lines = text.components(separatedBy: .newlines)
        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return ([:], text)
        }
        var frontmatter: [String: String] = [:]
        var endIndex: Int?

        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                endIndex = index
                break
            }
            guard let colon = lines[index].firstIndex(of: ":") else { continue }
            let key = lines[index][..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[index][lines[index].index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            frontmatter[key] = value
        }

        guard let endIndex else { return ([:], text) }
        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (frontmatter, body)
    }

    private func extractTitle(from frontmatter: [String: String], body: String, fallback: String) -> String {
        if let project = frontmatter["project"]?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
            return presentableTitle(project)
        }

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let heading = markdownHeadingText(from: trimmed) {
                return presentableTitle(heading)
            }
            if !trimmed.isEmpty, !trimmed.hasPrefix("-"), !trimmed.hasPrefix(">") {
                return presentableTitle(trimmed)
            }
        }
        return humanizeSlug(fallback)
    }

    private func extractSummary(from body: String) -> String {
        let sanitizedBody = removingHTMLComments(from: body)
        var paragraphLines: [String] = []

        for line in sanitizedBody.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "---" {
                if let paragraph = summarizedParagraph(from: paragraphLines) {
                    return paragraph
                }
                paragraphLines.removeAll()
                continue
            }

            guard isSummaryCandidateLine(trimmed) else {
                if let paragraph = summarizedParagraph(from: paragraphLines) {
                    return paragraph
                }
                paragraphLines.removeAll()
                continue
            }

            paragraphLines.append(trimmed)
        }

        return summarizedParagraph(from: paragraphLines) ?? ""
    }

    private func summarizedParagraph(from lines: [String]) -> String? {
        let paragraph = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return paragraph.count >= 24 ? paragraph : nil
    }

    private func isSummaryCandidateLine(_ line: String) -> Bool {
        if markdownHeadingText(from: line) != nil {
            return false
        }

        if line.hasPrefix("-")
            || line.hasPrefix("*")
            || line.hasPrefix("+")
            || line.hasPrefix(">")
            || line.hasPrefix("```")
            || line.hasPrefix("![](")
            || line.hasPrefix("|") {
            return false
        }

        if line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            return false
        }

        if line.range(of: #"^`[^`]+`$"#, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private func removingHTMLComments(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func markdownHeadingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(prefixCount) else {
            return nil
        }

        let remainder = trimmed.dropFirst(prefixCount)
        guard remainder.first?.isWhitespace == true else {
            return nil
        }

        let heading = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? nil : heading
    }

    private func presentableTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if looksLikeSlug(trimmed) {
            return humanizeSlug(trimmed)
        }
        return trimmed
    }

    private func looksLikeSlug(_ text: String) -> Bool {
        let hasSeparator = text.contains("_") || (!text.contains(" ") && text.contains("-"))
        guard hasSeparator else {
            return false
        }

        return text == text.lowercased()
    }

    private func extractGoogleDriveFolderURL(from frontmatter: [String: String], body: String) -> String? {
        let preferredKeys = [
            "google_drive_folder_url",
            "google_drive_folder",
            "drive_folder_url",
            "drive_folder",
            "google_drive_url",
            "drive_url",
            "folder_url"
        ]

        let normalizedFrontmatter = Dictionary(uniqueKeysWithValues: frontmatter.map { key, value in
            (
                key
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: " ", with: "_"),
                value
            )
        })

        for key in preferredKeys {
            if let candidate = normalizedFrontmatter[key], let normalized = normalizeGoogleDriveFolderURL(candidate) {
                return normalized
            }
        }

        guard let regex = try? NSRegularExpression(pattern: #"https://drive\.google\.com/[^\s\)]+"#) else {
            return nil
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, range: range),
              let matchRange = Range(match.range, in: body) else {
            return nil
        }
        return normalizeGoogleDriveFolderURL(String(body[matchRange]))
    }

    private func normalizeGoogleDriveFolderURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("drive.google.com") else { return nil }
        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()<>.,"))
    }

    private func extractAgentsSummary(from text: String) -> String {
        guard !text.isEmpty else { return "" }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "---" || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("-") {
                continue
            }
            if trimmed.count >= 20 {
                return trimmed
            }
        }
        return ""
    }

    private func classifyProjectType(
        section: WorkspaceSection,
        directory: URL,
        frontmatter: [String: String],
        readmeBody: String,
        agentsText: String
    ) -> WorkspaceProjectType {
        if let explicit = explicitProjectType(from: frontmatter, section: section) {
            return explicit
        }

        switch section {
        case .areas:
            return .area
        case .resources:
            return .resource
        case .archives:
            return .archive
        case .projects:
            break
        }

        let corpus = ([directory.lastPathComponent] + frontmatter.values + [readmeBody, agentsText])
            .joined(separator: "\n")
            .lowercased()

        if corpus.contains("data-journalism") || corpus.contains("data journalism") {
            return .dataJournalism
        }

        if corpus.contains("tooling or personal projects")
            || corpus.contains("tooling project")
            || corpus.contains("prototype")
            || corpus.contains("swiftui")
            || corpus.contains("launcher")
            || corpus.contains("cli")
            || corpus.contains("automation")
            || corpus.contains("app code")
            || corpus.contains("macos app")
            || corpus.contains("event-scanner") {
            return .tooling
        }

        if corpus.contains("journalism project")
            || corpus.contains("reporting workspace")
            || frontmatter["deliverable"]?.isEmpty == false
            || frontmatter["type"] == "project" {
            return .journalism
        }

        return .general
    }

    private func inferLifecycleStage(
        section: WorkspaceSection,
        frontmatter: [String: String],
        readmeBody: String
    ) -> String {
        if let projectState = ProjectState.from(frontmatter: frontmatter, isArchivedStorage: section == .archives) {
            return projectState.detailLabel
        }

        if let status = frontmatter["status"], !status.isEmpty {
            return humanizeStatus(status)
        }

        switch section {
        case .archives:
            return "Archived"
        case .areas:
            return "Ongoing"
        case .resources:
            return "Reusable"
        case .projects:
            let lowered = readmeBody.lowercased()
            if lowered.contains("roadmap") || lowered.contains("backlog") {
                return "Planning"
            }
            return "Active"
        }
    }

    private func inferSafetyPosture(
        section: WorkspaceSection,
        projectType: WorkspaceProjectType,
        frontmatter: [String: String],
        directory: URL,
        readmeBody: String,
        agentsText: String
    ) -> WorkspaceSafetyPosture {
        if let explicit = explicitSafetyPosture(from: frontmatter, section: section) {
            return explicit
        }

        if section == .archives {
            return .archival
        }

        let corpus = [directory.lastPathComponent, readmeBody, agentsText]
            .joined(separator: "\n")
            .lowercased()

        if corpus.contains("privacy-sensitive")
            || corpus.contains("privacy sensitive")
            || corpus.contains("local-first")
            || corpus.contains("local only")
            || corpus.contains("publishability")
            || corpus.contains("personal exports")
            || corpus.contains("redaction") {
            return .localSensitive
        }

        switch projectType {
        case .tooling, .resource, .area, .general:
            return .internalOnly
        case .archive:
            return .archival
        case .journalism, .dataJournalism:
            return .unknown
        }
    }

    private func explicitProjectType(
        from frontmatter: [String: String],
        section: WorkspaceSection
    ) -> WorkspaceProjectType? {
        if let rawType = normalizedToken(frontmatter["type"]) {
            switch rawType {
            case "area":
                return .area
            case "resource":
                return .resource
            case "archive":
                return .archive
            default:
                break
            }
        }

        guard section == .projects else { return nil }
        guard let rawValue = normalizedProjectType(frontmatter["project_type"]),
              !rawValue.isEmpty else {
            return nil
        }

        switch rawValue {
        case WorkspaceProjectType.journalism.rawValue:
            return .journalism
        case WorkspaceProjectType.dataJournalism.rawValue:
            return .dataJournalism
        case WorkspaceProjectType.tooling.rawValue:
            return .tooling
        case WorkspaceProjectType.general.rawValue:
            return .general
        default:
            return nil
        }
    }

    private func explicitSafetyPosture(
        from frontmatter: [String: String],
        section: WorkspaceSection
    ) -> WorkspaceSafetyPosture? {
        if section == .archives, frontmatter["safety"] == nil {
            return .archival
        }

        guard let rawValue = normalizedSafetyValue(frontmatter["safety"]),
              !rawValue.isEmpty else {
            return nil
        }

        switch rawValue {
        case WorkspaceSafetyPosture.unknown.rawValue:
            return .unknown
        case WorkspaceSafetyPosture.internalOnly.rawValue:
            return .internalOnly
        case WorkspaceSafetyPosture.localSensitive.rawValue:
            return .localSensitive
        case WorkspaceSafetyPosture.publishableReviewed.rawValue:
            return .publishableReviewed
        case WorkspaceSafetyPosture.archival.rawValue:
            return .archival
        default:
            return nil
        }
    }

    private func normalizedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizedProjectType(_ value: String?) -> String? {
        guard let normalized = normalizedToken(value)?
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") else {
            return nil
        }

        switch normalized {
        case "datajournalism":
            return WorkspaceProjectType.dataJournalism.rawValue
        default:
            return normalized
        }
    }

    private func normalizedSafetyValue(_ value: String?) -> String? {
        guard let normalized = normalizedToken(value)?
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") else {
            return nil
        }

        switch normalized {
        case "publishable":
            return WorkspaceSafetyPosture.publishableReviewed.rawValue
        case "internalonly", "internal_only":
            return WorkspaceSafetyPosture.internalOnly.rawValue
        case "localsensitive":
            return WorkspaceSafetyPosture.localSensitive.rawValue
        case "archive", "archived":
            return WorkspaceSafetyPosture.archival.rawValue
        default:
            return normalized
        }
    }
}

func humanizeSlug(_ slug: String) -> String {
    let tokens = slug
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { String($0).lowercased() }

    guard let first = tokens.first else {
        return ""
    }

    let firstWord = first.prefix(1).uppercased() + String(first.dropFirst())
    return ([firstWord] + Array(tokens.dropFirst()))
        .joined(separator: " ")
}

private func humanizeStatus(_ status: String) -> String {
    status
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { token in
            token.lowercased() == "qa" ? "QA" : token.capitalized
        }
        .joined(separator: " ")
}
