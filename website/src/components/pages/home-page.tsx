import Link from "next/link";
import { getDictionary, type Locale } from "@/i18n";
import { href } from "@/i18n/routes";
import { CompareTable } from "@/components/site/compare-table";
import { DictationDemo } from "@/components/site/dictation-demo";
import { Faq } from "@/components/site/faq";
import { PricingPlans } from "@/components/site/pricing-plans";
import { Reveal } from "@/components/site/reveal";
import { AppleIcon, ButtonLink, SectionTitle } from "@/components/site/ui";
import { PAID_PLANS_OPEN, visibleRows } from "@/lib/pricing";

export function HomePage({ locale, downloadHref }: { locale: Locale; downloadHref: string }) {
  const t = getDictionary(locale);

  return (
    <main>
      {/* Hero: copy left, live demo right. */}
      <section className="container-page grid items-center gap-14 pb-16 pt-12 sm:pt-20 lg:grid-cols-[1fr_1.1fr] lg:gap-16 lg:pb-24 lg:pt-24">
        <div>
          <Reveal trigger="load" as="h1" className="display max-w-[16ch] text-[clamp(2.6rem,5.2vw,4.4rem)] leading-[1.02]">
            {t.hero.title}
          </Reveal>
          <Reveal trigger="load" delayMs={120} as="p" className="copy mt-6 max-w-[34rem] text-[clamp(1.0625rem,1.4vw,1.1875rem)]">
            {t.hero.body}
          </Reveal>
          <Reveal trigger="load" delayMs={220} className="mt-9 flex flex-wrap items-center gap-3">
            <ButtonLink href={downloadHref} size="lg">
              <AppleIcon className="size-[18px]" />
              {t.cta.download}
            </ButtonLink>
            <Link href={href(locale, "pricing")} className="h-12 px-4 text-[15px] leading-[3rem] text-muted-foreground transition-colors hover:text-foreground">
              {t.cta.seePricing} →
            </Link>
          </Reveal>
          <Reveal trigger="load" delayMs={280} as="p" className="mt-4 text-[13px] text-muted-foreground">
            {t.cta.free} · {t.cta.requirements}
          </Reveal>
        </div>
        <Reveal trigger="load" delayMs={160}>
          <DictationDemo copy={t.demo} />
        </Reveal>
      </section>

      {/* How it works */}
      <section className="section">
        <div className="container-page">
          <Reveal>
            <SectionTitle>{t.steps.title}</SectionTitle>
          </Reveal>
          <ol className="mt-14 grid gap-10 md:grid-cols-3 md:gap-8">
            {t.steps.items.map((s, i) => (
              <Reveal key={s.title} as="li" delayMs={i * 60} className="border-t border-border pt-6">
                <span className="text-sm tabular-nums text-muted-foreground">0{i + 1}</span>
                <h3 className="mt-3 text-xl font-medium tracking-[-0.02em]">{s.title}</h3>
                <p className="copy mt-2">{s.body}</p>
              </Reveal>
            ))}
          </ol>
        </div>
      </section>

      {/* Privacy: the one dark panel on the page. */}
      <section className="container-page">
        <Reveal className="rounded-[28px] bg-ink px-6 py-14 text-white sm:px-12 sm:py-20">
          <div className="grid gap-12 lg:grid-cols-[1fr_1.4fr] lg:gap-16">
            <div>
              <SectionTitle className="max-w-[14ch]">{t.privacy.title}</SectionTitle>
              <p className="mt-5 max-w-[30rem] text-[17px] leading-relaxed text-white/65">{t.privacy.body}</p>
            </div>
            <ul className="grid gap-x-10 gap-y-8 sm:grid-cols-2">
              {t.privacy.items.map((item) => (
                <li key={item.title} className="border-t border-white/12 pt-5">
                  <h3 className="font-medium">{item.title}</h3>
                  <p className="mt-1.5 text-[15px] leading-relaxed text-white/60">{item.body}</p>
                </li>
              ))}
            </ul>
          </div>
        </Reveal>
      </section>

      {/* Smarter: before/after */}
      <section className="section">
        <div className="container-page grid gap-12 lg:grid-cols-[1fr_1.4fr] lg:gap-16">
          <Reveal>
            <SectionTitle className="max-w-[16ch]">{t.smart.title}</SectionTitle>
            <p className="copy mt-5 max-w-[30rem]">{t.smart.body}</p>
            <p className="mt-6 max-w-[30rem] text-sm leading-relaxed text-muted-foreground">{t.smart.note}</p>
          </Reveal>
          <div className="flex flex-col gap-4">
            {t.smart.examples.map((ex, i) => (
              <Reveal key={ex.style} delayMs={i * 80} className="grid gap-px overflow-hidden rounded-2xl bg-border ring-1 ring-border sm:grid-cols-2">
                <div className="bg-surface p-6">
                  <p className="text-xs text-muted-foreground">{t.smart.beforeLabel}</p>
                  <p className="mt-3 text-[15px] italic leading-relaxed text-foreground/55">“{ex.before}”</p>
                </div>
                <div className="bg-background p-6">
                  <p className="text-xs text-muted-foreground">
                    {t.smart.afterLabel} · <span className="text-accent">{ex.style}</span>
                  </p>
                  <p className="mt-3 whitespace-pre-line text-[15px] leading-relaxed">{ex.after}</p>
                </div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* Customizable */}
      <section className="section pt-0">
        <div className="container-page">
          <Reveal>
            <SectionTitle>{t.custom.title}</SectionTitle>
            <p className="copy mt-4">{t.custom.body}</p>
          </Reveal>
          <ul className="mt-12 grid gap-x-8 gap-y-10 sm:grid-cols-2 lg:grid-cols-3">
            {t.custom.items.map((item, i) => (
              <Reveal key={item.title} as="li" delayMs={Math.min(i, 5) * 50} className="border-t border-border pt-5">
                <h3 className="font-medium tracking-[-0.01em]">{item.title}</h3>
                <p className="mt-1.5 text-[15px] leading-relaxed text-muted-foreground">{item.body}</p>
              </Reveal>
            ))}
          </ul>
        </div>
      </section>

      {/* Compare teaser */}
      <section className="section bg-surface">
        <div className="container-page grid gap-12 lg:grid-cols-[1fr_1.4fr] lg:gap-16">
          <Reveal>
            <SectionTitle className="max-w-[14ch]">{t.compareTeaser.title}</SectionTitle>
            <p className="copy mt-5 max-w-[28rem]">{t.compareTeaser.body}</p>
            <Link href={href(locale, "compare")} className="mt-6 inline-block text-[15px] font-medium underline-offset-4 hover:underline">
              {t.compareTeaser.link} →
            </Link>
          </Reveal>
          <Reveal delayMs={80}>
            <CompareTable t={t.compare} rows={visibleRows(t.compare.rows).slice(0, 6)} />
          </Reveal>
        </div>
      </section>

      {/* Pricing */}
      <section className="section" id="pricing">
        <div className="container-page">
          <Reveal className="mx-auto max-w-[40rem] text-center">
            <SectionTitle className="mx-auto">{PAID_PLANS_OPEN ? t.pricing.title : t.pricing.free.title}</SectionTitle>
            <p className="copy mt-5">{PAID_PLANS_OPEN ? t.pricing.body : t.pricing.free.body}</p>
          </Reveal>
          <Reveal delayMs={80} className="mt-12">
            <PricingPlans t={t.pricing} downloadHref={downloadHref} />
          </Reveal>
        </div>
      </section>

      <Faq t={t.faq} />

      <FinalCta locale={locale} downloadHref={downloadHref} />
    </main>
  );
}

export function FinalCta({ locale, downloadHref }: { locale: Locale; downloadHref: string }) {
  const t = getDictionary(locale);
  return (
    <section className="container-page">
      <Reveal className="flex flex-col items-center rounded-[28px] bg-surface px-6 py-16 text-center sm:py-20">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/app-icon.png" alt="" width={72} height={72} className="size-[72px] rounded-[18px] shadow-[0_12px_32px_-12px_rgba(30,28,41,0.35)]" />
        <h2 className="display mt-8 text-[clamp(1.875rem,3.4vw,2.875rem)] leading-[1.08]">{t.final.title}</h2>
        <p className="copy mt-4 max-w-[30rem]">{t.final.body}</p>
        <ButtonLink href={downloadHref} size="lg" className="mt-8">
          <AppleIcon className="size-[18px]" />
          {t.cta.download}
        </ButtonLink>
        <p className="mt-4 text-[13px] text-muted-foreground">{t.cta.requirements}</p>
      </Reveal>
    </section>
  );
}
