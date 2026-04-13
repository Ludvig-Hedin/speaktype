import type { Metadata } from "next";
import Link from "next/link";
import { DownloadsReleases } from "@/components/landing/downloads-releases";
import { SiteFooter } from "@/components/landing/site-footer";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { LATEST_DMG_DOWNLOAD_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Downloads — SpeakType",
  description:
    "Download SpeakType for Mac. Choose the latest version or an older release.",
};

export default async function DownloadsPage() {
  let macDownloadHref: string;
  try {
    macDownloadHref = await resolveLatestMacDownloadHref();
  } catch (error) {
    console.error(
      "DownloadsPage: failed to resolve latest Mac download URL, using static fallback",
      error,
    );
    macDownloadHref = LATEST_DMG_DOWNLOAD_URL;
  }
  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-zinc-200/70 px-6 py-5 dark:border-zinc-800/80">
        <div className="mx-auto flex max-w-4xl flex-wrap items-center justify-between gap-4">
          <Link
            href="/"
            className="text-sm font-medium text-zinc-600 transition hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-zinc-50"
          >
            ← Back to home
          </Link>
          <a
            href={macDownloadHref}
            className="rounded-full bg-zinc-900 px-4 py-2 text-xs font-medium text-white transition hover:bg-zinc-800 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-white"
            target="_blank"
            rel="noopener noreferrer"
          >
            Download latest Mac app
          </a>
        </div>
      </header>
      <DownloadsReleases />
      <SiteFooter macDownloadHref={macDownloadHref} />
    </div>
  );
}
