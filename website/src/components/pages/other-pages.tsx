import { getDictionary, type Locale } from "@/i18n";
import { CompareTable } from "@/components/site/compare-table";
import { Faq } from "@/components/site/faq";
import { PricingPlans } from "@/components/site/pricing-plans";
import { Reveal } from "@/components/site/reveal";
import { AppleIcon, ButtonLink, SectionTitle } from "@/components/site/ui";
import { fetchGitHubReleases } from "@/lib/github-releases";
import { ALL_RELEASES_URL } from "@/lib/site";
import { FinalCta } from "./home-page";

function PageHero({ title, body }: { title: string; body: string }) {
  return (
    <section className="container-page pb-6 pt-16 text-center sm:pt-24">
      <Reveal trigger="load" as="h1" className="display mx-auto max-w-[18ch] text-[clamp(2.4rem,4.6vw,3.75rem)] leading-[1.04]">
        {title}
      </Reveal>
      <Reveal trigger="load" delayMs={120} as="p" className="copy mx-auto mt-5 max-w-[38rem]">
        {body}
      </Reveal>
    </section>
  );
}

export function PricingPage({ locale, downloadHref }: { locale: Locale; downloadHref: string }) {
  const t = getDictionary(locale);
  return (
    <main>
      <PageHero title={t.pricing.title} body={t.pricing.body} />
      <section className="container-page pb-8 pt-10">
        <Reveal trigger="load" delayMs={200}>
          <PricingPlans t={t.pricing} downloadHref={downloadHref} />
        </Reveal>
      </section>
      <Faq t={t.faq} />
      <FinalCta locale={locale} downloadHref={downloadHref} />
    </main>
  );
}

export function ComparePage({ locale, downloadHref }: { locale: Locale; downloadHref: string }) {
  const t = getDictionary(locale);
  const c = t.compare;
  return (
    <main>
      <PageHero title={c.title} body={c.body} />
      <section className="container-page flex justify-center pt-4">
        <ButtonLink href={downloadHref} size="lg">
          <AppleIcon className="size-[18px]" />
          {t.cta.download}
        </ButtonLink>
      </section>

      <section className="section">
        <div className="mx-auto max-w-[var(--container-narrow)] px-6">
          <Reveal>
            <CompareTable t={c} rows={c.rows} />
            <p className="mt-6 text-sm text-muted-foreground">
              {c.sourcesNote}{" "}
              <a href="https://wisprflow.ai/pricing" className="underline underline-offset-2" target="_blank" rel="noopener noreferrer">
                wisprflow.ai/pricing
              </a>
            </p>
          </Reveal>
        </div>
      </section>

      <section className="section pt-0">
        <div className="container-page grid gap-14 lg:grid-cols-2">
          <Reveal>
            <SectionTitle className="text-[clamp(1.6rem,2.6vw,2.25rem)]">{c.honestTitle}</SectionTitle>
            <p className="copy mt-3">{c.honestBody}</p>
            <ul className="mt-8 flex flex-col">
              {c.honest.map((line) => (
                <li key={line} className="border-t border-border py-4 text-[15px] leading-relaxed">
                  {line}
                </li>
              ))}
            </ul>
          </Reveal>
          <Reveal delayMs={80}>
            <SectionTitle className="text-[clamp(1.6rem,2.6vw,2.25rem)]">{c.switchTitle}</SectionTitle>
            <ol className="mt-8 flex flex-col">
              {c.switchSteps.map((step, i) => (
                <li key={step} className="flex gap-4 border-t border-border py-4 text-[15px] leading-relaxed">
                  <span className="w-5 shrink-0 tabular-nums text-muted-foreground">{i + 1}</span>
                  {step}
                </li>
              ))}
            </ol>
          </Reveal>
        </div>
      </section>

      <Faq t={t.faq} />
      <FinalCta locale={locale} downloadHref={downloadHref} />
    </main>
  );
}

export async function DownloadsPage({ locale, downloadHref }: { locale: Locale; downloadHref: string }) {
  const t = getDictionary(locale);
  const d = t.downloads;
  const releases = await fetchGitHubReleases().catch(() => []);
  const fmt = new Intl.DateTimeFormat(locale === "sv" ? "sv-SE" : "en", { dateStyle: "medium" });

  return (
    <main>
      <PageHero title={d.title} body={d.body} />
      <section className="container-page flex flex-col items-center pt-4">
        <ButtonLink href={downloadHref} size="lg">
          <AppleIcon className="size-[18px]" />
          {t.cta.download}
        </ButtonLink>
        <p className="mt-4 text-[13px] text-muted-foreground">{t.cta.requirements}</p>
      </section>

      <section className="section">
        <div className="mx-auto max-w-[var(--container-narrow)] px-6">
          <h2 className="text-xl font-semibold tracking-[-0.02em]">{d.older}</h2>
          {releases.length === 0 ? (
            <p className="mt-6 text-muted-foreground">
              {d.none}{" "}
              <a href={ALL_RELEASES_URL} className="underline underline-offset-2" target="_blank" rel="noopener noreferrer">
                {d.viewOnGitHub}
              </a>
            </p>
          ) : (
            <ul className="mt-6 border-b border-border">
              {releases.map((r, i) => (
                <li key={r.htmlUrl} className="flex flex-wrap items-center justify-between gap-3 border-t border-border py-4">
                  <div className="flex items-baseline gap-3">
                    <span className="font-medium tabular-nums">{r.tag}</span>
                    <span className="text-sm text-muted-foreground">{fmt.format(new Date(r.publishedAt))}</span>
                    {i === 0 && !r.prerelease && <span className="text-xs font-medium text-accent">{d.latest}</span>}
                    {r.prerelease && <span className="text-xs text-muted-foreground">{d.prerelease}</span>}
                  </div>
                  <div className="flex items-center gap-4 text-sm">
                    {r.dmg && (
                      <a href={r.dmg.downloadUrl} className="font-medium underline-offset-4 hover:underline">
                        {r.dmg.name}
                      </a>
                    )}
                    <a href={r.htmlUrl} className="text-muted-foreground hover:text-foreground" target="_blank" rel="noopener noreferrer">
                      {d.viewOnGitHub}
                    </a>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>
    </main>
  );
}
