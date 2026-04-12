import Link from "next/link";
import { fetchGitHubReleases } from "@/lib/github-releases";
import { ALL_RELEASES_URL, GITHUB_REPO_URL } from "@/lib/site";

function formatDate(iso: string) {
  try {
    return new Intl.DateTimeFormat("en", {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export async function ReleasesSection() {
  const releases = await fetchGitHubReleases();

  return (
    <section
      id="releases"
      className="border-t border-zinc-200/70 px-6 py-20 dark:border-zinc-800/80"
      aria-labelledby="releases-downloads-heading"
    >
      <div className="mx-auto max-w-4xl">
        <div className="mb-10 text-center">
          <h2
            id="releases-downloads-heading"
            className="text-2xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50"
          >
            Downloads
          </h2>
          <p className="mt-2 text-sm text-zinc-600 dark:text-zinc-400">
            Every published release with a direct DMG link when available.
          </p>
        </div>

        {releases.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-zinc-300 bg-zinc-50/50 px-6 py-12 text-center dark:border-zinc-700 dark:bg-zinc-900/30">
            <p className="text-sm text-zinc-600 dark:text-zinc-400">
              Could not load releases from GitHub right now.
            </p>
            <Link
              href={ALL_RELEASES_URL}
              className="mt-4 inline-block text-sm font-medium text-zinc-900 underline-offset-4 hover:underline dark:text-zinc-100"
              prefetch={false}
              target="_blank"
              rel="noopener noreferrer"
            >
              Open releases on GitHub →
            </Link>
          </div>
        ) : (
          <ul className="space-y-3">
            {releases.map((r) => (
              <li
                key={r.htmlUrl}
                className="rounded-2xl border border-zinc-200/80 bg-white/50 px-5 py-4 backdrop-blur-sm dark:border-zinc-800/80 dark:bg-zinc-950/40"
              >
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-medium text-zinc-900 dark:text-zinc-100">
                        {r.name}
                      </span>
                      {r.prerelease ? (
                        <span className="rounded-full border border-zinc-300 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wider text-zinc-500 dark:border-zinc-600 dark:text-zinc-400">
                          Pre-release
                        </span>
                      ) : null}
                    </div>
                    <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-500">
                      {formatDate(r.publishedAt)}
                    </p>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    {r.dmg ? (
                      <Link
                        href={r.dmg.downloadUrl}
                        className="inline-flex items-center gap-1.5 rounded-full bg-zinc-900 px-4 py-2 text-xs font-medium text-white transition hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-white"
                        prefetch={false}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        Download .dmg
                      </Link>
                    ) : null}
                    <Link
                      href={r.htmlUrl}
                      className="inline-flex rounded-full border border-zinc-300 px-4 py-2 text-xs font-medium text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-50 dark:border-zinc-600 dark:text-zinc-300 dark:hover:border-zinc-500 dark:hover:bg-zinc-900/50"
                      prefetch={false}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Notes
                    </Link>
                    {r.otherAssets.length > 0 ? (
                      <span className="text-xs text-zinc-500">
                        +{r.otherAssets.length} file
                        {r.otherAssets.length === 1 ? "" : "s"}
                      </span>
                    ) : null}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}

        <p className="mt-8 text-center text-xs text-zinc-500">
          <Link
            href={GITHUB_REPO_URL}
            className="underline-offset-4 hover:underline"
            prefetch={false}
            target="_blank"
            rel="noopener noreferrer"
          >
            Repository on GitHub
          </Link>
        </p>
      </div>
    </section>
  );
}
