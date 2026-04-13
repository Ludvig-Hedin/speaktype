import { Features } from "@/components/landing/features";
import { Hero } from "@/components/landing/hero";
import { SiteFooter } from "@/components/landing/site-footer";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";

export default async function Home() {
  const macDownloadHref = await resolveLatestMacDownloadHref();
  return (
    <div className="flex min-h-screen flex-col">
      <Hero downloadHref={macDownloadHref} />
      <Features />
      <SiteFooter macDownloadHref={macDownloadHref} />
    </div>
  );
}
