import { Features } from "@/components/landing/features";
import { Hero } from "@/components/landing/hero";
import { ReleasesSection } from "@/components/landing/releases-section";
import { SiteFooter } from "@/components/landing/site-footer";

export default function Home() {
  return (
    <div className="flex min-h-screen flex-col">
      <Hero />
      <ReleasesSection />
      <Features />
      <SiteFooter />
    </div>
  );
}
