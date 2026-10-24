export type Locale = "en" | "sv";

export type PageKey = "home" | "pricing" | "compare" | "downloads";

const PATHS: Record<Locale, Record<PageKey, string>> = {
  en: {
    home: "/",
    pricing: "/pricing",
    compare: "/wispr-flow-alternative",
    downloads: "/downloads",
  },
  sv: {
    home: "/sv",
    pricing: "/sv/priser",
    compare: "/sv/wispr-flow-alternativ",
    downloads: "/sv/nedladdningar",
  },
};

export function href(locale: Locale, page: PageKey): string {
  return PATHS[locale][page];
}

/** hreflang alternates for a page, for Next metadata. */
export function alternates(locale: Locale, page: PageKey) {
  return {
    canonical: PATHS[locale][page],
    languages: { en: PATHS.en[page], sv: PATHS.sv[page] },
  };
}
