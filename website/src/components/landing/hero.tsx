import Link from "next/link";
import { RELEASES_URL } from "@/lib/site";
import { AppleIcon } from "./apple-icon";
import { TranscribeCaption } from "./transcribe-caption";
import { WaveformVisual } from "./waveform-visual";

export function Hero() {
  return (
    <header className="relative px-6 pb-20 pt-28 sm:pt-36">
      <div
        className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(ellipse_85%_55%_at_50%_-15%,rgba(24,24,27,0.09),transparent)] dark:bg-[radial-gradient(ellipse_85%_55%_at_50%_-15%,rgba(250,250,250,0.08),transparent)]"
        aria-hidden
      />
      <div className="mx-auto flex max-w-2xl flex-col items-center text-center">
        <p className="mb-5 text-[11px] font-medium uppercase tracking-[0.22em] text-zinc-500 dark:text-zinc-400">
          macOS · Offline · Open source
        </p>
        <h1 className="text-balance text-4xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50 sm:text-5xl sm:leading-[1.08]">
          Voice to text,
          <span className="block text-zinc-600 dark:text-zinc-300">
            right where you type.
          </span>
        </h1>
        <p className="mt-6 max-w-lg text-pretty text-base leading-relaxed text-zinc-600 dark:text-zinc-400 sm:text-lg">
          SpeakType runs Whisper locally on your Mac—no cloud, no tracking.
          Press a hotkey, dictate, and paste into any app.
        </p>

        <Link
          href={RELEASES_URL}
          className="group mt-10 inline-flex items-center gap-2.5 rounded-full bg-zinc-900 px-7 py-3.5 text-sm font-medium text-white shadow-[0_1px_0_rgba(255,255,255,0.06)_inset] transition hover:bg-zinc-800 active:scale-[0.98] dark:bg-zinc-100 dark:text-zinc-900 dark:shadow-[0_1px_0_rgba(0,0,0,0.06)_inset] dark:hover:bg-white"
          prefetch={false}
          target="_blank"
          rel="noopener noreferrer"
        >
          <AppleIcon className="h-[18px] w-[18px] opacity-90 transition group-hover:opacity-100" />
          Download for Mac
        </Link>
        <p className="mt-3 text-xs text-zinc-500 dark:text-zinc-500">
          macOS 13+ · Apple Silicon recommended ·{" "}
          <Link
            href="/#releases"
            className="text-zinc-600 underline-offset-2 hover:text-zinc-900 hover:underline dark:text-zinc-400 dark:hover:text-zinc-200"
          >
            All versions
          </Link>
        </p>

        <TranscribeCaption />
        <WaveformVisual />
      </div>
    </header>
  );
}
