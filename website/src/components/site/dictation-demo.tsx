"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export type DemoStyle = { id: string; label: string; text: string };

export type DictationDemoCopy = {
  windowTitle: string;
  to: string;
  subject: string;
  spoken: string;
  listening: string;
  polishing: string;
  onDevice: string;
  replay: string;
  styleLabel: string;
  styles: DemoStyle[];
};

type Phase = "idle" | "listening" | "polishing" | "done";

const WORD_MS = 115;

/**
 * Hero demo: a compose window where raw speech streams in under the floating
 * recorder pill, then gets rewritten in the chosen style. Visitors can pick a
 * style; that stops the loop so the text they chose stays put.
 */
export function DictationDemo({ copy }: { copy: DictationDemoCopy }) {
  const words = copy.spoken.split(" ");
  const [phase, setPhase] = useState<Phase>("idle");
  const [count, setCount] = useState(0);
  const [styleId, setStyleId] = useState(copy.styles[0]?.id ?? "");
  const [auto, setAuto] = useState(true);
  const timers = useRef<number[]>([]);

  const clear = () => {
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
  };
  const later = (fn: () => void, ms: number) => {
    timers.current.push(window.setTimeout(fn, ms));
  };

  const run = useCallback(() => {
    clear();
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setCount(words.length);
      setPhase("done");
      return;
    }
    setPhase("idle");
    setCount(0);
    later(() => setPhase("listening"), 700);
    words.forEach((_, i) => later(() => setCount(i + 1), 900 + i * WORD_MS));
    const spokenEnd = 900 + words.length * WORD_MS + 350;
    later(() => setPhase("polishing"), spokenEnd);
    later(() => setPhase("done"), spokenEnd + 900);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [copy.spoken]);

  useEffect(() => {
    run();
    return clear;
  }, [run]);

  // Cycle styles while nobody has touched the demo, then replay.
  useEffect(() => {
    if (!auto || phase !== "done") return;
    const idx = copy.styles.findIndex((s) => s.id === styleId);
    const t = window.setTimeout(() => {
      if (idx < copy.styles.length - 1) setStyleId(copy.styles[idx + 1].id);
      else {
        setStyleId(copy.styles[0].id);
        run();
      }
    }, 3200);
    return () => window.clearTimeout(t);
  }, [auto, phase, styleId, copy.styles, run]);

  const pick = (id: string) => {
    setAuto(false);
    clear();
    setStyleId(id);
    setCount(words.length);
    setPhase("done");
  };

  const replay = () => {
    setAuto(true);
    setStyleId(copy.styles[0].id);
    run();
  };

  const style = copy.styles.find((s) => s.id === styleId) ?? copy.styles[0];
  const recording = phase === "listening" || phase === "polishing";

  return (
    <div className="relative">
      <div className="overflow-hidden rounded-[14px] bg-white shadow-[0_1px_0_rgba(0,0,0,0.04),0_24px_60px_-28px_rgba(30,28,41,0.35)] ring-1 ring-black/[0.06]">
        <div className="flex h-10 items-center gap-2 border-b border-black/[0.06] bg-[#f6f5f3] px-4">
          <span className="size-3 rounded-full bg-[#ff5f57]" />
          <span className="size-3 rounded-full bg-[#febc2e]" />
          <span className="size-3 rounded-full bg-[#28c840]" />
          <span className="ml-3 text-[13px] font-medium text-foreground/60">{copy.windowTitle}</span>
        </div>
        <div className="divide-y divide-black/[0.05] px-5 text-[14px]">
          <div className="py-2.5 text-foreground/50">{copy.to}</div>
          <div className="py-2.5 font-medium text-foreground/80">{copy.subject}</div>
        </div>
        <div
          className="min-h-[13.5rem] px-5 pb-20 pt-4 text-[15px] leading-relaxed text-foreground sm:min-h-[12rem]"
          aria-live="polite"
        >
          {phase === "done" ? (
            <p key={style.id} className="whitespace-pre-line animate-[fadein_400ms_ease-out]">
              {style.text}
            </p>
          ) : (
            <p className={phase === "polishing" ? "text-foreground/45 transition-colors" : ""}>
              {words.slice(0, count).join(" ")}
              {phase === "listening" && <span className="caret ml-0.5 inline-block h-[1.05em] w-[2px] translate-y-[3px] bg-accent" />}
            </p>
          )}
        </div>
      </div>

      {/* Floating recorder pill, like the app's HUD. */}
      <div
        className={`absolute bottom-5 left-1/2 flex -translate-x-1/2 items-center gap-3 rounded-full bg-ink/90 py-2 pl-3 pr-4 text-[13px] text-white shadow-[0_12px_32px_-12px_rgba(0,0,0,0.5)] backdrop-blur transition-all duration-300 ${
          recording ? "translate-y-0 opacity-100" : "pointer-events-none translate-y-2 opacity-0"
        }`}
        aria-hidden
      >
        <span className="flex h-4 items-end gap-[3px]">
          {[0, 1, 2, 3, 4].map((i) => (
            <span
              key={i}
              className={`w-[3px] rounded-full bg-white ${phase === "listening" ? "level-bar" : "opacity-50"}`}
              style={{ height: 16, animationDelay: `${i * 120}ms` }}
            />
          ))}
        </span>
        <span>{phase === "polishing" ? copy.polishing : copy.listening}</span>
        <span className="text-white/45">· {copy.onDevice}</span>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-1.5">
        <span className="mr-1 text-[13px] text-muted-foreground">{copy.styleLabel}</span>
        {copy.styles.map((s) => (
          <button
            key={s.id}
            type="button"
            onClick={() => pick(s.id)}
            aria-pressed={phase === "done" && s.id === style.id}
            className={`h-8 rounded-full px-3 text-[13px] transition-colors ${
              phase === "done" && s.id === style.id
                ? "bg-foreground text-background"
                : "text-foreground/70 hover:bg-control-plate hover:text-foreground"
            }`}
          >
            {s.label}
          </button>
        ))}
        <button
          type="button"
          onClick={replay}
          className="ml-auto h-8 rounded-full px-3 text-[13px] text-muted-foreground transition-colors hover:bg-control-plate hover:text-foreground"
        >
          {copy.replay}
        </button>
      </div>
    </div>
  );
}
