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
