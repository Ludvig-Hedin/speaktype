import type { Dictionary } from "@/i18n";
import { Check, buttonClass } from "./ui";

/** Free-only launch: one plan, plus a plain note that Pro comes later. */
export function FreePlan({ t, downloadHref }: { t: Dictionary["pricing"]; downloadHref: string }) {
  const f = t.free;
  return (
    <div className="mx-auto grid max-w-[56rem] gap-12 md:grid-cols-2 md:gap-16">
      <div className="flex flex-col">
        <h3 className="text-2xl font-semibold tracking-[-0.02em]">{t.plans.free.name}</h3>
        <div className="mt-3 flex items-baseline gap-1.5">
          <span className="text-4xl font-medium tracking-[-0.03em] tabular-nums">{f.price}</span>
          <span className="text-sm text-muted-foreground">{t.forever}</span>
        </div>
        <a href={downloadHref} className={buttonClass("primary", "lg", "mt-6 w-full")}>
          {f.cta}
        </a>
        <p className="mt-8 border-t border-border pt-6 text-sm font-medium">{f.lead}</p>
        <ul className="mt-4 flex flex-col gap-3 text-[15px]">
          {f.features.map((feature) => (
            <li key={feature} className="flex gap-2.5">
              <Check className="mt-1 text-foreground/50" />
              <span>{feature}</span>
            </li>
          ))}
        </ul>
      </div>
      <div className="self-start rounded-2xl bg-surface p-7">
        <h3 className="text-lg font-semibold tracking-[-0.01em]">{f.laterTitle}</h3>
        <p className="mt-2 text-[15px] leading-relaxed text-foreground/70">{f.laterBody}</p>
      </div>
    </div>
  );
}
