/** Normalize "owner/repo" from env or full GitHub URL (with or without .git). */
export function getGitHubRepoSlug(): string {
  const explicit = process.env.NEXT_PUBLIC_GITHUB_REPOSITORY?.trim();
  if (explicit) {
    return explicit.replace(/^\/+|\/+$/g, "");
  }
  const fromUrl =
    process.env.NEXT_PUBLIC_GITHUB_REPO_URL ??
    process.env.NEXT_PUBLIC_GITHUB_REPO;
  const parsed = parseRepoFromGitHubUrl(fromUrl);
  if (parsed) return parsed;
  return "Ludvig-Hedin/speaktype";
}

function parseRepoFromGitHubUrl(url: string | undefined): string | null {
  if (!url?.trim()) return null;
  const cleaned = url.trim().replace(/\.git$/i, "");
  const m = cleaned.match(/github\.com\/([^/]+\/[^/]+)\/?$/i);
  return m ? m[1] : null;
}

/** Canonical web URL for the repo (no .git). */
export const GITHUB_REPO_URL =
  process.env.NEXT_PUBLIC_GITHUB_REPO_URL?.replace(/\.git$/i, "").trim() ||
  `https://github.com/${getGitHubRepoSlug()}`;

/** Latest release shortcut (GitHub redirects to newest). */
export const RELEASES_URL =
  process.env.NEXT_PUBLIC_RELEASES_URL?.trim() ||
  `${GITHUB_REPO_URL}/releases/latest`;

/** All releases page (browser). */
export const ALL_RELEASES_URL = `${GITHUB_REPO_URL}/releases`;

/** DMG filename attached to each GitHub release (for /releases/latest/download/...). */
export const DMG_ASSET_NAME =
  process.env.NEXT_PUBLIC_DMG_FILENAME?.trim() || "SpeakType.dmg";

/**
 * Direct download of the latest release asset — GitHub redirects to the file.
 * Override if your asset name differs or you mirror the file elsewhere.
 */
export const LATEST_DMG_DOWNLOAD_URL =
  process.env.NEXT_PUBLIC_LATEST_DMG_URL?.trim() ||
  `${GITHUB_REPO_URL}/releases/latest/download/${encodeURIComponent(DMG_ASSET_NAME)}`;
