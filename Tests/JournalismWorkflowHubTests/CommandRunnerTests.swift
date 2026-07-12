import XCTest
@testable import JournalismWorkflowHub

final class CommandRunnerTests: XCTestCase {
    func testResolveExecutableURLFindsExecutableOnPath() throws {
        let url = try CommandRunner.resolveExecutableURL(
            for: "sh",
            environment: ["PATH": "/bin:/usr/bin"]
        )

        XCTAssertEqual(url.lastPathComponent, "sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
    }

    func testResolveExecutableURLThrowsForMissingExecutable() {
        XCTAssertThrowsError(
            try CommandRunner.resolveExecutableURL(
                for: "definitely-not-a-real-executable",
                environment: ["PATH": "/bin:/usr/bin"]
            )
        )
    }
}
