import Foundation

enum WorkspaceRootResolver {
    static let argumentName = "--workspace-root"
    static let profileArgumentName = "--app-profile"
    static let environmentKey = "JWH_WORKSPACE_ROOT"
    static let profileEnvironmentKey = "JWH_APP_PROFILE"
    static let userDefaultsKey = "workspaceRootPath"
    static let profileDefaultsKey = "appProfile"

    static func resolve(
        profile: AppProfile = .standard,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        savedPath: String? = UserDefaults.standard.string(forKey: userDefaultsKey),
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        demoWorkspaceRoot: URL? = bundledDemoWorkspaceRoot()
    ) -> URL {
        if let argumentRoot = rootFromArguments(arguments) {
            return normalize(argumentRoot)
        }

        if let environmentRoot = nonEmpty(environment[environmentKey]) {
            return normalize(environmentRoot)
        }

        if profile == .standalone, let demoWorkspaceRoot {
            return demoWorkspaceRoot.standardizedFileURL
        }

        if let savedRoot = nonEmpty(savedPath), profile == .standard {
            return normalize(savedRoot)
        }

        if let discovered = discoverWorkspaceRoot(startingAt: URL(fileURLWithPath: currentDirectoryPath)) {
            return discovered
        }

        return URL(fileURLWithPath: currentDirectoryPath).standardizedFileURL
    }

    static func resolveProfile(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppProfile {
        if let rawArgument = profileFromArguments(arguments),
           let profile = AppProfile(rawValue: rawArgument) {
            return profile
        }

        if let rawEnvironment = nonEmpty(environment[profileEnvironmentKey]),
           let profile = AppProfile(rawValue: rawEnvironment) {
            return profile
        }

        if let rawSaved = nonEmpty(UserDefaults.standard.string(forKey: profileDefaultsKey)),
           let profile = AppProfile(rawValue: rawSaved) {
            return profile
        }

        return .standard
    }

    static func persist(_ workspaceRoot: URL) {
        UserDefaults.standard.set(workspaceRoot.path, forKey: userDefaultsKey)
    }

    static func persistProfile(_ profile: AppProfile) {
        UserDefaults.standard.set(profile.rawValue, forKey: profileDefaultsKey)
    }

    static func rootFromArguments(_ arguments: [String]) -> String? {
        guard let argumentIndex = arguments.firstIndex(of: argumentName) else {
            return nil
        }

        let nextIndex = arguments.index(after: argumentIndex)
        guard nextIndex < arguments.endIndex else {
            return nil
        }

        return nonEmpty(arguments[nextIndex])
    }

    static func profileFromArguments(_ arguments: [String]) -> String? {
        guard let argumentIndex = arguments.firstIndex(of: profileArgumentName) else {
            return nil
        }

        let nextIndex = arguments.index(after: argumentIndex)
        guard nextIndex < arguments.endIndex else {
            return nil
        }

        return nonEmpty(arguments[nextIndex])?.lowercased()
    }

    private static func discoverWorkspaceRoot(startingAt startURL: URL) -> URL? {
        var candidate = startURL.standardizedFileURL

        while true {
            if looksLikeWorkspaceRoot(candidate) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private static func looksLikeWorkspaceRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        let requiredDirectories = ["Projects", "Resources"]
        return requiredDirectories.allSatisfy { name in
            var isDirectory: ObjCBool = false
            let path = url.appendingPathComponent(name, isDirectory: true).path
            return fm.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func normalize(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AppDefaults {
    static var profile: AppProfile {
        WorkspaceRootResolver.resolveProfile()
    }

    static var workspaceRoot: URL {
        WorkspaceRootResolver.resolve(profile: profile)
    }

    static var configuration: AppConfiguration {
        let profile = self.profile
        let demoWorkspaceRoot = bundledDemoWorkspaceRoot()
        let workspaceRoot = WorkspaceRootResolver.resolve(
            profile: profile,
            demoWorkspaceRoot: demoWorkspaceRoot
        )
        return AppConfiguration(
            profile: profile,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: demoWorkspaceRoot
        )
    }
}
