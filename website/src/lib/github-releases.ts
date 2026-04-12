import { getGitHubRepoSlug } from "@/lib/site";

export type ReleaseAsset = {
  name: string;
  downloadUrl: string;
};

export type ReleaseForWeb = {
  tag: string;
  name: string;
  publishedAt: string;
  htmlUrl: string;
  prerelease: boolean;
  /** First .dmg asset, if any */
  dmg: ReleaseAsset | null;
  otherAssets: ReleaseAsset[];
};

type GitHubReleaseApi = {
  tag_name: string;
  name: string | null;
  body: string | null;
  published_at: string;
  html_url: string;
  draft: boolean;
  prerelease: boolean;
  assets: { name: string; browser_download_url: string }[];
};

function mapRelease(r: GitHubReleaseApi): ReleaseForWeb | null {
  if (r.draft) return null;
  const dmgAssets = r.assets.filter((a) => a.name.toLowerCase().endsWith(".dmg"));
  const dmg = dmgAssets[0]
    ? { name: dmgAssets[0].name, downloadUrl: dmgAssets[0].browser_download_url }
    : null;
  const otherAssets = r.assets
    .filter((a) => !a.name.toLowerCase().endsWith(".dmg"))
    .map((a) => ({ name: a.name, downloadUrl: a.browser_download_url }));

  const tag = r.tag_name.replace(/^v/i, "");
  return {
    tag: r.tag_name.startsWith("v") ? r.tag_name : `v${tag}`,
    name: (r.name?.trim() || r.tag_name).trim(),
    publishedAt: r.published_at,
    htmlUrl: r.html_url,
    prerelease: r.prerelease,
    dmg,
    otherAssets,
  };
}

/**
 * Fetches public releases from the GitHub API (server-side).
 * Set GITHUB_TOKEN in Vercel for higher rate limits (optional).
 */
export async function fetchGitHubReleases(): Promise<ReleaseForWeb[]> {
  const slug = getGitHubRepoSlug();
  const url = `https://api.github.com/repos/${slug}/releases?per_page=30`;

  const headers: HeadersInit = {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "SpeakType-Website",
  };
  const token = process.env.GITHUB_TOKEN;
  if (token) {
    (headers as Record<string, string>).Authorization = `Bearer ${token}`;
  }

  const res = await fetch(url, {
    headers,
    next: { revalidate: 300 },
  });

  if (!res.ok) {
    console.error("GitHub releases fetch failed:", res.status, await res.text());
    return [];
  }

  const raw = (await res.json()) as GitHubReleaseApi[];
  return raw.map(mapRelease).filter((x): x is ReleaseForWeb => x !== null);
}
