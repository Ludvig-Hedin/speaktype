"use client";

import { useState } from "react";
import type { Dictionary } from "@/i18n";
import { CHECKOUT, PAID_PLANS_OPEN, PRICES } from "@/lib/pricing";
import { FreePlan } from "./free-plan";
import { Check, buttonClass } from "./ui";

/**
 * Three open columns (no card chrome); only the Pro button carries colour.
 * Paid CTAs use the Polar checkout link when configured, else the download,
 * where the in-app trial starts.
 */
export function PricingPlans({ t, downloadHref }: { t: Dictionary["pricing"]; downloadHref: string }) {
  const [yearly, setYearly] = useState(true);
  if (!PAID_PLANS_OPEN) return <FreePlan t={t} downloadHref={downloadHref} />;
  const proCheckout = yearly ? CHECKOUT.proYearly : CHECKOUT.proMonthly;
  const anyCheckout = Boolean(CHECKOUT.proYearly || CHECKOUT.proMonthly || CHECKOUT.lifetime);

  const plans = [
    {
      key: "free",
      plan: t.plans.free,
      price: "$0",
      sub: t.forever,
      note: "",
      cta: { label: t.plans.free.cta, href: downloadHref, variant: "outline" as const },
    },
    {
      key: "pro",
      plan: t.plans.pro,
      price: `$${yearly ? PRICES.proYearly / 12 : PRICES.proMonthly}`,
      sub: t.perMonth,
      note: yearly ? t.billedYearly : t.billedMonthly,
      badge: t.plans.pro.badge,
      cta: proCheckout
        ? { label: t.plans.pro.buy, href: proCheckout, variant: "accent" as const }
        : { label: t.plans.pro.cta, href: downloadHref, variant: "accent" as const },
    },
    {
      key: "lifetime",
      plan: t.plans.lifetime,
      price: `$${PRICES.lifetime}`,
      sub: t.once,
      note: t.oneTime,
      cta: CHECKOUT.lifetime
        ? { label: t.plans.lifetime.cta, href: CHECKOUT.lifetime, variant: "outline" as const }
        : { label: t.plans.pro.cta, href: downloadHref, variant: "outline" as const },
    },
  ];

  return (
    <div>
      <div className="flex justify-center">
        <div role="radiogroup" className="inline-flex rounded-full bg-muted p-1 text-sm">
          {[
            { on: true, label: t.yearly },
            { on: false, label: t.monthly },
          ].map((o) => (
            <button
              key={o.label}
              type="button"
              role="radio"
              aria-checked={yearly === o.on}
              onClick={() => setYearly(o.on)}
              className={`flex h-8 items-center gap-2 rounded-full px-4 transition-colors ${
                yearly === o.on ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {o.label}
              {o.on && <span className="text-xs font-medium text-accent">{t.save}</span>}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-14 grid gap-12 md:grid-cols-3 md:gap-10">
        {plans.map((p) => (
          <div key={p.key} className="flex min-w-0 flex-col border-t border-border pt-8 md:border-t-0 md:pt-0">
            <div className="flex items-center gap-2">
              <h3 className="text-2xl font-semibold tracking-[-0.02em]">{p.plan.name}</h3>
              {"badge" in p && p.badge && (
                <span className="rounded-full bg-accent/10 px-2 py-0.5 text-xs font-medium text-accent">{p.badge}</span>
              )}
            </div>
            <div className="mt-3 flex items-baseline gap-1.5">
              <span className="text-4xl font-medium tracking-[-0.03em] tabular-nums">{p.price}</span>
              <span className="text-sm text-muted-foreground">{p.sub}</span>
            </div>
            <p className="mt-1 h-5 text-sm text-muted-foreground">{p.note}</p>
            <a href={p.cta.href} className={buttonClass(p.cta.variant, "lg", "mt-6 w-full")}>
              {p.cta.label}
            </a>
            <p className="mt-8 border-t border-border pt-6 text-sm font-medium">{p.plan.lead}</p>
            <ul className="mt-4 flex flex-col gap-3 text-[15px]">
              {p.plan.features.map((f) => (
                <li key={f} className="flex gap-2.5">
                  <Check className="mt-1 text-foreground/50" />
                  <span>{f}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      {!anyCheckout && <p className="mt-12 text-center text-sm text-muted-foreground">{t.trialNote}</p>}
    </div>
  );
}
