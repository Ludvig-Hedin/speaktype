import { HomePage } from "@/components/pages/home-page";
import { Shell } from "@/components/site/shell";
import { resolveLatestMacDownloadHref } from "@/lib/github-releases";
import { pageMetadata } from "@/lib/page-meta";

export const metadata = pageMetadata("sv", "home");
export const revalidate = 300;

export default async function Page() {
  const downloadHref = await resolveLatestMacDownloadHref();
  return (
    <Shell locale="sv" page="home" downloadHref={downloadHref}>
      <HomePage locale="sv" downloadHref={downloadHref} />
    </Shell>
  );
}
