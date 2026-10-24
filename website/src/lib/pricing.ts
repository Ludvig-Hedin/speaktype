/**
 * Plan prices and checkout links, in one place.
 *
 * Prices are the owner-approved proposal of 2026-10-24 (free local + Pro,
 * monthly/yearly or one-time). Checkout links come from env so the site can
 * go live before Polar products exist: without a link, a paid CTA falls back
 * to the free download, where the 14-day Pro trial starts.
 */
export const PRICES = {
  proMonthly: 6,
  proYearly: 48,
  lifetime: 89,
  lifetimeMacs: 3,
  trialDays: 14,
  /** Wispr Flow Pro, for comparisons (wisprflow.ai/pricing, 2026-10-24). */
  wisprYearly: 144,
  wisprMonthly: 15,
  wisprFreeWordsPerWeek: 2000,
} as const;

export const CHECKOUT = {
  proMonthly: process.env.NEXT_PUBLIC_CHECKOUT_PRO_MONTHLY?.trim() || null,
  proYearly: process.env.NEXT_PUBLIC_CHECKOUT_PRO_YEARLY?.trim() || null,
  lifetime: process.env.NEXT_PUBLIC_CHECKOUT_LIFETIME?.trim() || null,
};

/**
 * Owner decision 2026-10-24: launch free only. Paid plans stay hidden until
 * Polar checkout exists; set NEXT_PUBLIC_PAID_PLANS_OPEN=1 to show them.
 */
export const PAID_PLANS_OPEN = process.env.NEXT_PUBLIC_PAID_PLANS_OPEN?.trim() === "1";

/** Comparison rows for the current mode (price rows differ free vs paid). */
export function visibleRows<T extends { freeOnly?: boolean; paidOnly?: boolean }>(rows: T[]): T[] {
  return rows.filter((r) => (PAID_PLANS_OPEN ? !r.freeOnly : !r.paidOnly));
}

/** FAQ answer for the current mode. */
export function faqAnswer(item: { a: string; aFree?: string }): string {
  return !PAID_PLANS_OPEN && item.aFree ? item.aFree : item.a;
}
