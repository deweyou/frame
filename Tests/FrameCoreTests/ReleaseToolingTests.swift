import Foundation
import XCTest

final class ReleaseToolingTests: XCTestCase {
    func testBumpVersionUpdatesVersionAssertionsAndChangelog() throws {
        let fixture = try ReleaseToolingFixture()

        let result = try run(
            ["bash", repositoryRoot.appendingPathComponent("scripts/bump-version.sh").path, "0.2.0", "2"],
            environment: fixture.environment
                .merging(["FRAME_TODAY": "2026-07-02"]) { _, new in new }
        )

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
        XCTAssertEqual(
            try String(contentsOf: fixture.versionSource),
            #"""
            public enum FrameVersion {
                public static let shortVersion = "0.2.0"
                public static let build = "2"

                public static var displayName: String {
                    "\(shortVersion) (\(build))"
                }
            }
            """#
        )
        XCTAssertTrue(
            try String(contentsOf: fixture.versionTestSource).contains(
                """
                XCTAssert(FrameVersion.shortVersion == "0.2.0")
                        XCTAssert(FrameVersion.build == "2")
                        XCTAssert(FrameVersion.displayName == "0.2.0 (2)")
                """
            )
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.changelogSource),
            """
            # Changelog

            ## Unreleased

            - Add release notes here before the next version bump.

            ## 0.2.0 - 2026-07-02

            - Add beta packaging workflow.

            ## 0.1.0 - 2026-06-01

            - Initial local screenshot loop.
            """
        )
    }

    func testBumpVersionRejectsNonIncreasingBuildNumber() throws {
        let fixture = try ReleaseToolingFixture(currentBuild: "2")

        let result = try run(
            ["bash", repositoryRoot.appendingPathComponent("scripts/bump-version.sh").path, "0.2.1", "2"],
            environment: fixture.environment
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.diagnosticOutput.contains("greater than current build 2"), result.diagnosticOutput)
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let build = \"2\""))
    }

    func testBumpVersionRejectsMissingUnreleasedSectionBeforeMutatingSources() throws {
        let fixture = try ReleaseToolingFixture()
        try """
        # Changelog

        ## 0.1.0 - 2026-06-01

        - Initial local screenshot loop.
        """.write(to: fixture.changelogSource, atomically: true, encoding: .utf8)

        let result = try run(
            ["bash", repositoryRoot.appendingPathComponent("scripts/bump-version.sh").path, "0.2.0", "2"],
            environment: fixture.environment
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.diagnosticOutput.contains("Unable to find CHANGELOG.md Unreleased section"), result.diagnosticOutput)
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let shortVersion = \"0.1.0\""))
        XCTAssertTrue(try String(contentsOf: fixture.versionTestSource).contains("XCTAssert(FrameVersion.displayName == \"0.1.0 (1)\")"))
    }

    func testPrepareReleaseVersionAppliesPatchMinorAndMajorBumps() throws {
        try assertPreparedReleaseVersion(mode: "patch", currentVersion: "1.2.3", currentBuild: "7", expectedVersion: "1.2.4")
        try assertPreparedReleaseVersion(mode: "minor", currentVersion: "1.2.3", currentBuild: "7", expectedVersion: "1.3.0")
        try assertPreparedReleaseVersion(mode: "major", currentVersion: "1.2.3", currentBuild: "7", expectedVersion: "2.0.0")
    }

    func testPrepareReleaseVersionAppliesCustomVersion() throws {
        try assertPreparedReleaseVersion(mode: "custom", currentVersion: "1.2.3", currentBuild: "7", customVersion: "2.0.0", expectedVersion: "2.0.0")
    }

    func testPrepareReleaseVersionRejectsCustomVersionThatDoesNotIncrease() throws {
        let fixture = try ReleaseToolingFixture(currentVersion: "1.2.3", currentBuild: "7")

        let result = try run(
            ["bash", repositoryRoot.appendingPathComponent("scripts/prepare-release-version.sh").path, "custom", "1.2.3"],
            environment: fixture.environment
                .merging(["FRAME_TODAY": "2026-07-02"]) { _, new in new }
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.diagnosticOutput.contains("Custom version must be greater than current version 1.2.3"), result.diagnosticOutput)
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let shortVersion = \"1.2.3\""))
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let build = \"7\""))
    }

    func testReleaseScriptHasValidShellSyntax() throws {
        let result = try run([
            "bash",
            "-c",
            """
            for script in scripts/package-release.sh scripts/prepare-release-version.sh; do
                bash -n "$script" || exit 1
            done
            """,
        ])

        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
    }

    func testManualReleaseWorkflowExposesVersionBumpChoices() throws {
        let workflow = try String(contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/release.yml"))

        XCTAssertTrue(workflow.contains("workflow_dispatch:"), workflow)
        XCTAssertTrue(workflow.contains("type: choice"), workflow)
        XCTAssertTrue(workflow.contains("- patch"), workflow)
        XCTAssertTrue(workflow.contains("- minor"), workflow)
        XCTAssertTrue(workflow.contains("- major"), workflow)
        XCTAssertTrue(workflow.contains("- custom"), workflow)
        XCTAssertTrue(workflow.contains("scripts/prepare-release-version.sh"), workflow)
        XCTAssertTrue(workflow.contains("scripts/package-release.sh"), workflow)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ arguments: [String], environment: [String: String] = [:]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func assertPreparedReleaseVersion(
        mode: String,
        currentVersion: String,
        currentBuild: String,
        customVersion: String? = nil,
        expectedVersion: String
    ) throws {
        let fixture = try ReleaseToolingFixture(currentVersion: currentVersion, currentBuild: currentBuild)
        var arguments = [
            "bash",
            repositoryRoot.appendingPathComponent("scripts/prepare-release-version.sh").path,
            mode,
        ]
        if let customVersion {
            arguments.append(customVersion)
        }

        let result = try run(
            arguments,
            environment: fixture.environment
                .merging(["FRAME_TODAY": "2026-07-02"]) { _, new in new }
        )

        let expectedBuild = String((Int(currentBuild) ?? 0) + 1)
        XCTAssertEqual(result.exitCode, 0, result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_RELEASE_VERSION=\(expectedVersion)"), result.diagnosticOutput)
        XCTAssertTrue(result.stdout.contains("FRAME_RELEASE_BUILD=\(expectedBuild)"), result.diagnosticOutput)
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let shortVersion = \"\(expectedVersion)\""))
        XCTAssertTrue(try String(contentsOf: fixture.versionSource).contains("public static let build = \"\(expectedBuild)\""))
        XCTAssertTrue(try String(contentsOf: fixture.versionTestSource).contains("XCTAssert(FrameVersion.displayName == \"\(expectedVersion) (\(expectedBuild))\")"))
        XCTAssertTrue(try String(contentsOf: fixture.changelogSource).contains("## \(expectedVersion) - 2026-07-02"))
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var diagnosticOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private struct ReleaseToolingFixture {
    let root: URL
    let versionSource: URL
    let versionTestSource: URL
    let changelogSource: URL

    var environment: [String: String] {
        [
            "FRAME_VERSION_SOURCE": versionSource.path,
            "FRAME_VERSION_TEST_SOURCE": versionTestSource.path,
            "FRAME_CHANGELOG_SOURCE": changelogSource.path,
        ]
    }

    init(currentVersion: String = "0.1.0", currentBuild: String = "1") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        versionSource = root.appendingPathComponent("Sources/FrameCore/FrameVersion.swift")
        versionTestSource = root.appendingPathComponent("Tests/FrameCoreTests/FrameCoreTests.swift")
        changelogSource = root.appendingPathComponent("CHANGELOG.md")

        try FileManager.default.createDirectory(
            at: versionSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: versionTestSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try #"""
        public enum FrameVersion {
            public static let shortVersion = "\#(currentVersion)"
            public static let build = "\#(currentBuild)"

            public static var displayName: String {
                "\(shortVersion) (\(build))"
            }
        }
        """#.write(to: versionSource, atomically: true, encoding: .utf8)

        try """
        import XCTest
        import FrameCore

        final class ZFrameCoreTests: XCTestCase {
            func testFrameVersionConstants() {
                XCTAssert(FrameVersion.shortVersion == "\(currentVersion)")
                XCTAssert(FrameVersion.build == "\(currentBuild)")
                XCTAssert(FrameVersion.displayName == "\(currentVersion) (\(currentBuild))")
            }
        }
        """.write(to: versionTestSource, atomically: true, encoding: .utf8)

        try """
        # Changelog

        ## Unreleased

        - Add beta packaging workflow.

        ## 0.1.0 - 2026-06-01

        - Initial local screenshot loop.
        """.write(to: changelogSource, atomically: true, encoding: .utf8)
    }
}
