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
