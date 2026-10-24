import { DownloadsPage } from "@/components/pages/other-pages";
import { Shell } from "@/components/site/shell";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { pageMetadata } from "@/lib/page-meta";

export const metadata = pageMetadata("sv", "downloads");
export const revalidate = 300;

export default async function Page() {
  const downloadHref = await resolveLatestMacDownloadHref();
  return (
    <Shell locale="sv" page="downloads" downloadHref={downloadHref}>
      <DownloadsPage locale="sv" downloadHref={downloadHref} />
    </Shell>
  );
}
