import XCTest
@testable import JournalismWorkflowHub

final class WorkspaceRootResolverTests: XCTestCase {
    func testStandaloneProfileFromArgumentWins() {
        let profile = WorkspaceRootResolver.resolveProfile(
            arguments: ["JournalismWorkflowHub", "--app-profile", "standalone"],
            environment: ["JWH_APP_PROFILE": "standard"]
        )

        XCTAssertEqual(profile, .standalone)
    }

    func testCommandLineArgumentWins() {
        let resolved = WorkspaceRootResolver.resolve(
            profile: .standard,
            arguments: ["JournalismWorkflowHub", "--workspace-root", "/tmp/explicit-root"],
            environment: ["JWH_WORKSPACE_ROOT": "/tmp/from-env"],
            savedPath: "/tmp/from-defaults",
            currentDirectoryPath: "/tmp/current"
        )

        XCTAssertEqual(resolved.path, "/tmp/explicit-root")
    }

    func testEnvironmentWinsOverSavedPath() {
        let resolved = WorkspaceRootResolver.resolve(
            profile: .standard,
            arguments: ["JournalismWorkflowHub"],
            environment: ["JWH_WORKSPACE_ROOT": "/tmp/from-env"],
            savedPath: "/tmp/from-defaults",
            currentDirectoryPath: "/tmp/current"
        )

        XCTAssertEqual(resolved.path, "/tmp/from-env")
    }

    func testDiscoveryWalksUpFromRepositoryDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRoot = tmp.appendingPathComponent("coding_projects")
        let repoDirectory = workspaceRoot.appendingPathComponent("Resources/Overig/journalism_workflow_hub")

        try FileManager.default.createDirectory(
            at: workspaceRoot.appendingPathComponent("Projects"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: workspaceRoot.appendingPathComponent("Resources"),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: repoDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let resolved = WorkspaceRootResolver.resolve(
            profile: .standard,
            arguments: ["JournalismWorkflowHub"],
            environment: [:],
            savedPath: nil,
            currentDirectoryPath: repoDirectory.path
        )

        XCTAssertEqual(resolved.path, workspaceRoot.path)
    }

    func testStandaloneUsesDemoWorkspaceBeforeSavedPath() {
        let demoRoot = URL(fileURLWithPath: "/tmp/demo-workspace")

        let resolved = WorkspaceRootResolver.resolve(
            profile: .standalone,
            arguments: ["JournalismWorkflowHub"],
            environment: [:],
            savedPath: "/tmp/from-defaults",
            currentDirectoryPath: "/tmp/current",
            demoWorkspaceRoot: demoRoot
        )

        XCTAssertEqual(resolved.path, demoRoot.path)
    }

    func testFallsBackToCurrentDirectoryWithoutLegacyRoot() {
        let resolved = WorkspaceRootResolver.resolve(
            profile: .standard,
            arguments: ["JournalismWorkflowHub"],
            environment: [:],
            savedPath: nil,
            currentDirectoryPath: "/tmp/current",
            demoWorkspaceRoot: nil
        )

        XCTAssertEqual(resolved.path, "/tmp/current")
    }
}
