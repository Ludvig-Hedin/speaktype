"use client";

import { useEffect, useState } from "react";

const PHRASES = [
  "Press the hotkey, speak…",
  "Your words become text—instantly.",
  "Works in any app, any field.",
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
      }, 42 + Math.random() * 38);
      return () => window.clearTimeout(t);
    }

    const hold = window.setTimeout(() => {
      setDisplay("");
      setPhraseIndex((i) => (i + 1) % PHRASES.length);
    }, 2200);
    return () => window.clearTimeout(hold);
  }, [display, phrase]);

  return (
    <p
      className="mt-8 min-h-[1.75rem] font-mono text-sm tracking-tight text-zinc-500 dark:text-zinc-400"
      aria-live="polite"
    >
      <span className="text-zinc-800 dark:text-zinc-200">{display}</span>
      <span
        className={`ml-0.5 inline-block w-2 translate-y-px border-l border-current ${
          isTyping ? "animate-caret-blink" : "opacity-40"
        }`}
        aria-hidden
      />
    </p>
  );
}
