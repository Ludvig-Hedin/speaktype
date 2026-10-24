import { DownloadsPage } from "@/components/pages/other-pages";
import { Shell } from "@/components/site/shell";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { pageMetadata } from "@/lib/page-meta";

export const metadata = pageMetadata("en", "downloads");
export const revalidate = 300;

export default async function Page() {
  const downloadHref = await resolveLatestMacDownloadHref();
  return (
    <Shell locale="en" page="downloads" downloadHref={downloadHref}>
      <DownloadsPage locale="en" downloadHref={downloadHref} />
    </Shell>
  );
}
