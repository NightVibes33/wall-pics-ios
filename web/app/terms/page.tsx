import type { Metadata } from "next";
import { Footer } from "@/components/sections/footer";
import { Header } from "@/components/sections/header";
import { APP_NAME, CONTACT_EMAIL, SITE_URL } from "@/lib/site-config";

export const dynamic = "force-static";

export const metadata: Metadata = {
  title: `Terms of Use | ${APP_NAME}`,
  description: `Terms of Use for ${APP_NAME}, an iPhone wallpaper app.`,
  alternates: {
    canonical: "/terms",
  },
};

const sections = [
  {
    title: "Using the app",
    body: [
      "Přism is provided for personal, non-commercial wallpaper browsing, previewing, and saving on your own devices.",
      "You agree not to misuse the app, interfere with its operation, bypass access controls, scrape or rehost the catalog, resell media, or use the service in a way that violates the rights of others.",
    ],
  },
  {
    title: "Accounts and sign-in",
    body: [
      "Some features may require sign-in with Apple, Google, or another supported provider. You are responsible for keeping your account and device secure.",
      "We may suspend or limit access if we detect abuse, fraud, security risk, or use that violates these terms.",
    ],
  },
  {
    title: "Content and rights",
    body: [
      "The app may provide access to wallpapers, Live Photos, matching sets, profile pictures, and related media for personal device customization.",
      "You are responsible for how you use saved media. Do not redistribute, sell, or claim ownership of media unless you have the legal right to do so.",
      "We may add, remove, reorder, or modify content and features at any time.",
    ],
  },
  {
    title: "Purchases and subscriptions",
    body: [
      "If paid features, subscriptions, or trials are offered, purchases are processed by Apple through your Apple ID and are subject to Apple's payment terms.",
      "Subscription cancellation, renewal, and refund handling are managed through Apple unless we state otherwise inside the app.",
    ],
  },
  {
    title: "No warranty",
    body: [
      "The app is provided as is and as available. We do not promise that the service will always be uninterrupted, error-free, or available on every device configuration.",
    ],
  },
  {
    title: "Limitation of liability",
    body: [
      "To the maximum extent allowed by law, we are not liable for indirect, incidental, special, consequential, or punitive damages arising from your use of the app.",
    ],
  },
  {
    title: "Changes to these terms",
    body: [
      "We may update these terms when the app changes. Continued use of the app after an update means you accept the updated terms.",
    ],
  },
];

export default function TermsPage() {
  return (
    <>
      <Header />
      <main className="min-h-screen bg-neutral-100 px-6 pb-20 pt-32 sm:px-8">
        <article className="mx-auto max-w-3xl">
          <p className="text-sm font-semibold uppercase text-accent">Effective June 3, 2026</p>
          <h1 className="mt-4 text-4xl font-black leading-tight text-black sm:text-5xl">
            Terms of Use
          </h1>
          <p className="mt-5 text-lg leading-8 text-neutral-600">
            These Terms of Use govern your access to and use of {APP_NAME}, including the iPhone app, website, and related services.
          </p>

          <div className="mt-12 space-y-10">
            {sections.map((section) => (
              <section key={section.title}>
                <h2 className="text-2xl font-bold text-black">{section.title}</h2>
                <div className="mt-4 space-y-4 text-base leading-8 text-neutral-700">
                  {section.body.map((paragraph) => (
                    <p key={paragraph}>{paragraph}</p>
                  ))}
                </div>
              </section>
            ))}

            <section>
              <h2 className="text-2xl font-bold text-black">Contact</h2>
              <p className="mt-4 text-base leading-8 text-neutral-700">
                Questions about these terms can be sent to <a className="font-semibold text-accent" href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
              </p>
              <p className="mt-4 text-sm leading-7 text-neutral-500">
                Canonical URL: {SITE_URL}/terms
              </p>
            </section>
          </div>
        </article>
      </main>
      <Footer />
    </>
  );
}
