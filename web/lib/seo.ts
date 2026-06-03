import { APP_NAME, APP_STORE_URL, SITE_URL } from "@/lib/site-config";

export function getSoftwareApplicationSchema() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: APP_NAME,
    applicationCategory: "MultimediaApplication",
    operatingSystem: "iOS",
    description:
      "Browse high-quality wallpapers, Live Photos, matching sets, and profile pictures for iPhone.",
    downloadUrl: APP_STORE_URL,
    installUrl: APP_STORE_URL,
    url: SITE_URL,
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
  };
}
