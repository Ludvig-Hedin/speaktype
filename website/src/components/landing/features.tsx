import type { ReactNode } from "react";

function FeatureCard({
  title,
  body,
  icon,
}: {
  title: string;
  body: string;
  icon: ReactNode;
}) {
  return (
    <article className="group relative overflow-hidden rounded-2xl border border-zinc-200/80 bg-white/40 p-8 shadow-[0_1px_0_rgba(0,0,0,0.04)] backdrop-blur-sm transition hover:border-zinc-300/90 dark:border-zinc-800/80 dark:bg-zinc-950/40 dark:shadow-[0_1px_0_rgba(255,255,255,0.04)] dark:hover:border-zinc-700/90">
      <div
        className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-zinc-100/80 opacity-0 blur-2xl transition group-hover:opacity-100 dark:bg-zinc-800/50"
        aria-hidden
      />
      <div className="relative flex flex-col gap-4">
        <div className="flex h-11 w-11 items-center justify-center rounded-xl border border-zinc-200/90 bg-zinc-50 text-zinc-700 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-200">
          {icon}
        </div>
        <h2 className="text-lg font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">
          {title}
        </h2>
        <p className="text-sm leading-relaxed text-zinc-600 dark:text-zinc-400">
          {body}
        </p>
      </div>
    </article>
  );
}

function IconShield() {
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      <path d="m9 12 2 2 4-4" />
    </svg>
  );
}

function IconZap() {
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z" />
    </svg>
  );
}

export function Features() {
  return (
    <section
      className="border-t border-zinc-200/70 bg-zinc-50/50 px-6 py-20 dark:border-zinc-800/80 dark:bg-zinc-950/50"
      aria-labelledby="features-heading"
    >
      <div className="mx-auto max-w-4xl">
        <h2
          id="features-heading"
          className="sr-only"
        >
          Features
        </h2>
        <div className="grid gap-6 md:grid-cols-2 md:gap-8">
          <FeatureCard
            title="Private by design"
            body="Transcription stays on your machine. No accounts, no servers, and no audio leaves your Mac—ideal for sensitive notes, code, and everyday dictation."
            icon={<IconShield />}
          />
          <FeatureCard
            title="Fast, fluid workflow"
            body="Optimized for Apple Silicon with WhisperKit. Trigger dictation from a global hotkey, then drop text into Mail, Slack, Xcode, or the browser—wherever the cursor is."
            icon={<IconZap />}
          />
        </div>
      </div>
    </section>
  );
}
