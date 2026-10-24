import Link from "next/link";
import type { Dictionary, Locale } from "@/i18n";
import { href } from "@/i18n/routes";
import { ALL_RELEASES_URL, GITHUB_REPO_URL } from "@/lib/site";

export function Footer({ locale, t }: { locale: Locale; t: Dictionary }) {
  const year = new Date().getFullYear();
  const linkClass = "text-muted-foreground transition-colors hover:text-foreground";
  return (
    <footer className="mt-auto pb-12 pt-20">
      <div className="container-page">
      <div className="grid gap-10 border-t border-border pt-10 text-sm sm:grid-cols-[2fr_1fr_1fr]">
        <div>
          <div className="flex items-center gap-2.5 font-semibold tracking-[-0.02em]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/app-icon.png" alt="" width={24} height={24} className="size-6 rounded-[6px]" />
            SpeakType
          </div>
          <p className="mt-3 text-muted-foreground">{t.footer.tagline}</p>
          <p className="mt-8 text-muted-foreground">
            © {year} SpeakType · {t.footer.rights}
          </p>
        </div>
        <nav aria-label={t.footer.product} className="flex flex-col gap-2.5">
          <p className="font-medium">{t.footer.product}</p>
          <Link href={href(locale, "pricing")} className={linkClass}>{t.nav.pricing}</Link>
          <Link href={href(locale, "compare")} className={linkClass}>{t.nav.compare}</Link>
          <Link href={href(locale, "downloads")} className={linkClass}>{t.nav.downloads}</Link>
        </nav>
        <nav aria-label={t.footer.resources} className="flex flex-col gap-2.5">
          <p className="font-medium">{t.footer.resources}</p>
          <a href={GITHUB_REPO_URL} className={linkClass} target="_blank" rel="noopener noreferrer">{t.footer.source}</a>
          <a href={ALL_RELEASES_URL} className={linkClass} target="_blank" rel="noopener noreferrer">{t.footer.releases}</a>
          <Link href={href(locale === "en" ? "sv" : "en", "home")} className={linkClass}>{t.nav.language}</Link>
        </nav>
      </div>
      </div>
    </footer>
  );
}
