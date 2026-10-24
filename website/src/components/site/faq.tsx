import type { Dictionary } from "@/i18n";
import { faqAnswer } from "@/lib/pricing";
import { SectionTitle } from "./ui";

export function Faq({ t }: { t: Dictionary["faq"] }) {
  return (
    <section className="section">
      <div className="container-page grid gap-10 lg:grid-cols-[1fr_2fr]">
        <SectionTitle>{t.title}</SectionTitle>
        <div className="divide-y divide-border border-y border-border">
          {t.items.map((item) => (
            <details key={item.q} className="group">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 text-[17px] font-medium tracking-[-0.01em] [&::-webkit-details-marker]:hidden">
                {item.q}
                <span
                  className="relative size-4 shrink-0 text-muted-foreground transition-transform duration-300 group-open:rotate-45"
                  aria-hidden
                >
                  <span className="absolute left-0 top-1/2 h-px w-4 -translate-y-1/2 bg-current" />
                  <span className="absolute left-1/2 top-0 h-4 w-px -translate-x-1/2 bg-current" />
                </span>
              </summary>
              <p className="copy max-w-[60ch] pb-6 pr-10">{faqAnswer(item)}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
