import { PricingPage } from "@/components/pages/other-pages";
import { Shell } from "@/components/site/shell";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { pageMetadata } from "@/lib/page-meta";

export const metadata = pageMetadata("en", "pricing");
export const revalidate = 300;

export default async function Page() {
  const downloadHref = await resolveLatestMacDownloadHref();
  return (
    <Shell locale="en" page="pricing" downloadHref={downloadHref}>
      <PricingPage locale="en" downloadHref={downloadHref} />
    </Shell>
  );
}
