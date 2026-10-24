import type { Metadata } from "next";
import { alternates, getDictionary, type Locale, type PageKey } from "@/i18n";
import { PAID_PLANS_OPEN } from "./pricing";

const KEYS: Record<PageKey, ["homeTitle" | "pricingTitle" | "compareTitle" | "downloadsTitle", "homeDescription" | "pricingDescription" | "compareDescription" | "downloadsDescription"]> = {
  home: ["homeTitle", "homeDescription"],
  pricing: ["pricingTitle", "pricingDescription"],
  compare: ["compareTitle", "compareDescription"],
  downloads: ["downloadsTitle", "downloadsDescription"],
};

export function pageMetadata(locale: Locale, page: PageKey): Metadata {
  const m = getDictionary(locale).meta;
  const [titleKey, descKey] = KEYS[page];
  const title = m[titleKey];
  const description =
    page === "pricing" && !PAID_PLANS_OPEN ? m.pricingDescriptionFree : m[descKey];
  return {
    title,
    description,
    alternates: alternates(locale, page),
    openGraph: {
      title,
      description,
      type: "website",
      siteName: "SpeakType",
      locale: locale === "sv" ? "sv_SE" : "en_US",
      images: [{ url: "/app-icon.png", width: 512, height: 512 }],
    },
    twitter: { card: "summary", title, description },
  };
}

export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL?.trim() || "http://localhost:3000";
