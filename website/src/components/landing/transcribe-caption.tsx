"use client";

import { useEffect, useState } from "react";

const PHRASES = [
  "Hold your shortcut, say what you mean…",
  "Your sentence appears—ready to send or edit.",
  "Same flow in every app you use.",
];

export function TranscribeCaption() {
  const [phraseIndex, setPhraseIndex] = useState(0);
  const [display, setDisplay] = useState("");
  const phrase = PHRASES[phraseIndex % PHRASES.length];
  const isTyping = display.length < phrase.length;

  useEffect(() => {
    if (display.length < phrase.length) {
      const t = window.setTimeout(() => {
        setDisplay(phrase.slice(0, display.length + 1));
      }, 78 + Math.random() * 55);
      return () => window.clearTimeout(t);
    }

    const hold = window.setTimeout(() => {
      setDisplay("");
      setPhraseIndex((i) => (i + 1) % PHRASES.length);
    }, 3600);
    return () => window.clearTimeout(hold);
  }, [display, phrase]);

  return (
    <p
      className="mt-10 min-h-[2rem] text-sm font-normal tracking-tight text-zinc-500 dark:text-zinc-500 sm:text-base"
      aria-live="polite"
    >
      <span className="text-zinc-700 dark:text-zinc-300">{display}</span>
      <span
        className={`ml-0.5 inline-block h-4 w-px translate-y-0.5 bg-current ${
          isTyping ? "animate-caret-blink" : "opacity-35"
        }`}
        aria-hidden
      />
    </p>
  );
}
