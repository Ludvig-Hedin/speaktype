import { ComparePage } from "@/components/pages/other-pages";
import { Shell } from "@/components/site/shell";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { pageMetadata } from "@/lib/page-meta";

export const metadata = pageMetadata("sv", "compare");
export const revalidate = 300;

export default async function Page() {
  const downloadHref = await resolveLatestMacDownloadHref();
  return (
    <Shell locale="sv" page="compare" downloadHref={downloadHref}>
      <ComparePage locale="sv" downloadHref={downloadHref} />
    </Shell>
  );
}
