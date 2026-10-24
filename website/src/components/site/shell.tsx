import type { ReactNode } from "react";
import { getDictionary, type Locale, type PageKey } from "@/i18n";
import { Footer } from "./footer";
import { Header } from "./header";

export function Shell({
  locale,
  page,
  downloadHref,
  children,
}: {
  locale: Locale;
  page: PageKey;
  downloadHref: string;
  children: ReactNode;
}) {
  const t = getDictionary(locale);
  return (
    <div className="flex min-h-screen flex-col">
      <Header locale={locale} page={page} t={t.nav} downloadHref={downloadHref} />
      {children}
      <Footer locale={locale} t={t} />
    </div>
  );
}
