import XCTest
@testable import speaktype

/// The updater swaps the app's contents in place and renames SpeakType.app to Taly.app.
/// Everything here runs in a throwaway temp folder, never in the real Applications folder.
final class AppUpdateInstallTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("AppUpdateInstallTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Unlock anything a test made read-only so the temp folder can be removed.
        if let items = fm.enumerator(atPath: root.path) {
            for case let item as String in items {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent(item).path)
            }
        }
        try? fm.removeItem(at: root)
    }

    private func makeApp(_ url: URL, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try version.write(to: contents.appendingPathComponent("version"), atomically: true, encoding: .utf8)
    }

    private func version(at app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/version"), encoding: .utf8)
    }

    func testUpdateRenamesOldAppAndKeepsDockLink() throws {
        let applications = root.appendingPathComponent("Applications")
        let oldApp = applications.appendingPathComponent("SpeakType.app")
        try makeApp(oldApp, version: "old")
        // The Dock keeps a bookmark like this one to each pinned app.
        let dockLink = try oldApp.bookmarkData()
        let download = root.appendingPathComponent("dmg/speaktype.app")
        try makeApp(download, version: "new")

        let installed = try UpdateService.installUpdate(from: download, over: oldApp)

        XCTAssertEqual(installed.lastPathComponent, "Taly.app")
        XCTAssertEqual(version(at: installed), "new")
        XCTAssertFalse(fm.fileExists(atPath: oldApp.path))
        var stale = false
        let resolved = try URL(resolvingBookmarkData: dockLink, bookmarkDataIsStale: &stale)
        XCTAssertEqual(resolved.lastPathComponent, "Taly.app")
        XCTAssertEqual(version(at: resolved), "new")
        // No staging or old-contents folders are left behind.
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: applications.path), ["Taly.app"])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: installed.path), ["Contents"])
    }

    func testUpdateOutsideApplicationsKeepsName() throws {
        let app = root.appendingPathComponent("Downloads/SpeakType.app")
        try makeApp(app, version: "old")
        let download = root.appendingPathComponent("dmg/speaktype.app")
        try makeApp(download, version: "new")

        let installed = try UpdateService.installUpdate(from: download, over: app)

        XCTAssertEqual(installed, app)
        XCTAssertEqual(version(at: installed), "new")
    }

    func testLowercaseOldNameIsRenamedToo() throws {
        let applications = root.appendingPathComponent("Applications")
        let oldApp = applications.appendingPathComponent("speaktype.app")
        try makeApp(oldApp, version: "old")
        let download = root.appendingPathComponent("dmg/Taly.app")
        try makeApp(download, version: "new")

        let installed = try UpdateService.installUpdate(from: download, over: oldApp)

        XCTAssertEqual(installed.lastPathComponent, "Taly.app")
        XCTAssertEqual(version(at: installed), "new")
    }

    /// Another user owns the app folder, so nothing in it can be changed. The update must
    /// fail with an error and leave the old app exactly as it was.
    func testLockedAppFolderFailsCleanlyAndKeepsOldApp() throws {
        let applications = root.appendingPathComponent("Applications")
        let oldApp = applications.appendingPathComponent("SpeakType.app")
        try makeApp(oldApp, version: "old")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: oldApp.path)
        let download = root.appendingPathComponent("dmg/Taly.app")
        try makeApp(download, version: "new")

        XCTAssertThrowsError(try UpdateService.installUpdate(from: download, over: oldApp))

        XCTAssertEqual(version(at: oldApp), "old")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: applications.path), ["SpeakType.app"])
    }

    func testInterruptedInstallLeftoversAreRemovedNextTime() throws {
        let applications = root.appendingPathComponent("Applications")
        let oldApp = applications.appendingPathComponent("Taly.app")
        try makeApp(oldApp, version: "old")
        try makeApp(applications.appendingPathComponent(".Taly-update-123.app"), version: "x")
        try makeApp(applications.appendingPathComponent(".SpeakType-update-456.app"), version: "x")
        try makeApp(applications.appendingPathComponent("Other.app"), version: "keep")
        let download = root.appendingPathComponent("dmg/Taly.app")
        try makeApp(download, version: "new")

        _ = try UpdateService.installUpdate(from: download, over: oldApp)

        XCTAssertEqual(
            try fm.contentsOfDirectory(atPath: applications.path).sorted(),
            ["Other.app", "Taly.app"]
        )
    }

    func testRenameSkipsWhenTalyAlreadyExists() throws {
        let applications = root.appendingPathComponent("Applications")
        let oldApp = applications.appendingPathComponent("SpeakType.app")
        let other = applications.appendingPathComponent("Taly.app")
        try makeApp(oldApp, version: "old")
        try makeApp(other, version: "other")

        let result = UpdateService.renamedToCurrentName(oldApp)

        XCTAssertEqual(result, oldApp)
        XCTAssertEqual(version(at: other), "other")
    }
}
