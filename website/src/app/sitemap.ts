import type { MetadataRoute } from "next";
import { href, type PageKey } from "@/i18n/routes";
import { SITE_URL } from "@/lib/page-meta";

const PAGES: PageKey[] = ["home", "pricing", "compare", "downloads"];

export default function sitemap(): MetadataRoute.Sitemap {
  return PAGES.flatMap((page) =>
    (["en", "sv"] as const).map((locale) => ({
      url: new URL(href(locale, page), SITE_URL).toString(),
      alternates: {
        languages: {
          en: new URL(href("en", page), SITE_URL).toString(),
          sv: new URL(href("sv", page), SITE_URL).toString(),
        },
      },
    })),
  );
}
