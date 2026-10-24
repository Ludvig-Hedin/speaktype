import { en, type Dictionary } from "./en";
import { sv } from "./sv";
import type { Locale } from "./routes";

export type { Dictionary } from "./en";
export type { Locale, PageKey } from "./routes";
export { href, alternates } from "./routes";

export function getDictionary(locale: Locale): Dictionary {
  return locale === "sv" ? sv : en;
}
