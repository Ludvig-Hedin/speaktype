import Foundation

/// GitHub `owner/repo` for API and release pages. Override in Info.plist (`GitHubUpdatesRepository`).
enum UpdateConfiguration {
    private static let infoPlistKey = "GitHubUpdatesRepository"

    static var githubRepository: String {
        let fromPlist =
            Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        let trimmed = fromPlist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return "Ludvig-Hedin/speaktype"
    }

    static var latestReleaseAPIURL: URL {
        URL(
            string:
                "https://api.github.com/repos/\(githubRepository)/releases/latest")!
    }

    /// Browser page listing all releases (DMGs and notes).
    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(githubRepository)/releases")!
    }
}
