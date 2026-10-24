"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { Dictionary, Locale, PageKey } from "@/i18n";
import { href } from "@/i18n/routes";
import { buttonClass } from "./ui";

export function Header({
  locale,
  page,
  t,
  downloadHref,
}: {
  locale: Locale;
  page: PageKey;
  t: Dictionary["nav"];
  downloadHref: string;
}) {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const other: Locale = locale === "en" ? "sv" : "en";

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const links = [
    { key: "pricing" as const, label: t.pricing },
    { key: "compare" as const, label: t.compare },
    { key: "downloads" as const, label: t.downloads },
  ];

  const linkClass = (active: boolean) =>
    `flex h-9 items-center rounded-lg px-3 text-sm transition-colors ${
      active ? "text-foreground" : "text-muted-foreground hover:bg-muted hover:text-foreground"
    }`;

  return (
    <header
      className={`sticky top-0 z-40 bg-background/85 backdrop-blur-md transition-shadow ${
        scrolled ? "shadow-[0_1px_0_var(--border)]" : ""
      }`}
    >
      <div className="container-page flex h-16 items-center">
        <div className="flex flex-1 basis-0">
          <Link href={href(locale, "home")} className="flex items-center gap-2.5 font-semibold tracking-[-0.02em]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/app-icon.png" alt="" width={28} height={28} className="size-7 rounded-[7px]" />
            SpeakType
          </Link>
        </div>

        <nav aria-label="Main" className="hidden items-center gap-1 md:flex">
          {links.map((l) => (
            <Link key={l.key} href={href(locale, l.key)} className={linkClass(page === l.key)}>
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="flex flex-1 basis-0 items-center justify-end gap-1">
          <Link
            href={href(other, page)}
            hrefLang={other}
            className="hidden h-9 items-center rounded-lg px-3 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground sm:flex"
          >
            {t.language}
          </Link>
          <a href={downloadHref} className={buttonClass("primary", "sm", "hidden sm:inline-flex")}>
            {t.download}
          </a>
          <button
            type="button"
            className="flex size-9 items-center justify-center rounded-lg hover:bg-muted md:hidden"
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={t.menu}
            onClick={() => setOpen((v) => !v)}
          >
            <svg viewBox="0 0 20 20" className="size-5" fill="none" aria-hidden>
              {open ? (
                <path d="M5 5l10 10M15 5L5 15" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              ) : (
                <path d="M3 7h14M3 13h14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              )}
            </svg>
          </button>
        </div>
      </div>

      {open && (
        <nav id="mobile-nav" aria-label="Mobile" className="container-page flex flex-col gap-1 pb-5 md:hidden">
          {links.map((l) => (
            <Link key={l.key} href={href(locale, l.key)} className={linkClass(page === l.key)} onClick={() => setOpen(false)}>
              {l.label}
            </Link>
          ))}
          <Link href={href(other, page)} hrefLang={other} className={linkClass(false)}>
            {t.language}
          </Link>
          <a href={downloadHref} className={buttonClass("primary", "lg", "mt-2")}>
            {t.download}
          </a>
        </nav>
      )}
    </header>
  );
}
