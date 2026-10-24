"use client";

import { useEffect, useRef, useState, type ElementType, type ReactNode } from "react";

/**
 * One-shot fade/rise/de-blur. `load` animates on mount (above the fold);
 * `scroll` waits for the element to enter the viewport. Hidden documents and
 * reduced-motion visitors see content immediately (CSS handles the latter).
 */
export function Reveal({
  children,
  className,
  delayMs = 0,
  trigger = "scroll",
  as: Tag = "div",
}: {
  children: ReactNode;
  className?: string;
  delayMs?: number;
  trigger?: "scroll" | "load";
  as?: ElementType;
}) {
  const ref = useRef<HTMLElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || document.hidden || typeof IntersectionObserver === "undefined") {
      setShown(true);
      return;
    }
    if (trigger === "load") {
      let second = 0;
      const first = requestAnimationFrame(() => {
        second = requestAnimationFrame(() => setShown(true));
      });
      return () => {
        cancelAnimationFrame(first);
        cancelAnimationFrame(second);
      };
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setShown(true);
          io.disconnect();
        }
      },
      { rootMargin: "0px 0px -5% 0px", threshold: 0.05 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [trigger]);

  return (
    <Tag
      ref={ref}
      data-shown={shown}
      className={`reveal ${className ?? ""}`}
      style={delayMs ? { transitionDelay: `${delayMs}ms` } : undefined}
    >
      {children}
    </Tag>
  );
}
