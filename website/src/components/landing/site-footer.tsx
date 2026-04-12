import Link from "next/link";
import { GITHUB_REPO_URL, RELEASES_URL } from "@/lib/site";

export function SiteFooter() {
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-zinc-200/70 px-6 py-12 dark:border-zinc-800/80">
      <div className="mx-auto flex max-w-4xl flex-col items-center justify-between gap-6 text-center text-sm text-zinc-500 dark:text-zinc-500 sm:flex-row sm:text-left">
        <p className="order-2 sm:order-1">
          © {year} SpeakType ·{" "}
          <span className="text-zinc-400 dark:text-zinc-600">MIT License</span>
        </p>
        <nav
          className="order-1 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 sm:order-2 sm:justify-end"
          aria-label="Footer"
        >
          <Link
            href="/#releases"
            className="text-zinc-700 underline-offset-4 transition hover:text-zinc-950 hover:underline dark:text-zinc-300 dark:hover:text-zinc-50"
          >
            All versions
          </Link>
          <Link
            href={RELEASES_URL}
            className="text-zinc-700 underline-offset-4 transition hover:text-zinc-950 hover:underline dark:text-zinc-300 dark:hover:text-zinc-50"
            prefetch={false}
            target="_blank"
            rel="noopener noreferrer"
          >
            Latest on GitHub
          </Link>
          <Link
            href={GITHUB_REPO_URL}
            className="text-zinc-700 underline-offset-4 transition hover:text-zinc-950 hover:underline dark:text-zinc-300 dark:hover:text-zinc-50"
            prefetch={false}
            target="_blank"
            rel="noopener noreferrer"
          >
            Source on GitHub
          </Link>
        </nav>
      </div>
    </footer>
  );
}
