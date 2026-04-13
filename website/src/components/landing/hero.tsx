import Link from "next/link";
import { LATEST_DMG_DOWNLOAD_URL } from "@/lib/site";
import { AppleIcon } from "./apple-icon";
import { TranscribeCaption } from "./transcribe-caption";
import { WaveformVisual } from "./waveform-visual";

type HeroProps = {
  /** Latest DMG URL (e.g. from `resolveLatestMacDownloadHref`). */
  downloadHref?: string;
};

export function Hero({ downloadHref = LATEST_DMG_DOWNLOAD_URL }: HeroProps) {
  return (
    <header className="relative px-6 pb-24 pt-28 sm:pt-36">
      <div
        className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(ellipse_85%_55%_at_50%_-15%,rgba(24,24,27,0.09),transparent)] dark:bg-[radial-gradient(ellipse_85%_55%_at_50%_-15%,rgba(250,250,250,0.08),transparent)]"
        aria-hidden
      />
      <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <p className="mb-5 text-[11px] font-medium uppercase tracking-[0.22em] text-zinc-500 dark:text-zinc-400">
          Dictation for your Mac
        </p>
        <h1 className="text-balance text-4xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50 sm:text-5xl sm:leading-[1.08]">
          Say it out loud.
          <span className="block text-zinc-600 dark:text-zinc-300">
            Watch it turn into text.
          </span>
        </h1>
        <p className="mt-6 max-w-lg text-pretty text-base leading-relaxed text-zinc-600 dark:text-zinc-400 sm:text-lg">
          Stop typing long messages by hand. SpeakType listens, then drops your
          words right where your cursor is—email, notes, chat, anywhere. Nothing
          is sent to the cloud; it stays on your computer.
        </p>

        <a
          href={downloadHref}
          className="group mt-10 inline-flex items-center gap-2.5 rounded-full bg-zinc-900 px-7 py-3.5 text-sm font-medium text-white shadow-[0_1px_0_rgba(255,255,255,0.06)_inset] transition hover:bg-zinc-800 active:scale-[0.98] dark:bg-zinc-100 dark:text-zinc-900 dark:shadow-[0_1px_0_rgba(0,0,0,0.06)_inset] dark:hover:bg-white"
          target="_blank"
          rel="noopener noreferrer"
        >
          <AppleIcon className="h-[18px] w-[18px] opacity-90 transition group-hover:opacity-100" />
          Download for Mac
        </a>
        <p className="mt-3 text-xs text-zinc-500 dark:text-zinc-500">
          Works on recent Macs ·{" "}
          <Link
            href="/downloads"
            className="text-zinc-600 underline-offset-2 hover:text-zinc-900 hover:underline dark:text-zinc-400 dark:hover:text-zinc-200"
          >
            Other versions
          </Link>
        </p>

        <TranscribeCaption />
        <WaveformVisual />
      </div>
    </header>
  );
}
