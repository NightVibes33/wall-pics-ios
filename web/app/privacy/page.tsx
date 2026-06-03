import type { Metadata } from "next";
import { Footer } from "@/components/sections/footer";
import { Header } from "@/components/sections/header";
import { APP_NAME, CONTACT_EMAIL, SITE_URL } from "@/lib/site-config";

export const dynamic = "force-static";

export const metadata: Metadata = {
  title: `Privacy Policy | ${APP_NAME}`,
  description: `Privacy Policy for ${APP_NAME}, an iPhone wallpaper app.`,
  alternates: {
    canonical: "/privacy",
  },
};

const sections = [
  {
    title: "Information we collect",
    body: [
      "When you sign in, we may receive account information such as your name, email address, provider user ID, and authentication provider details from Apple or Google.",
      "We may store app data needed to run the product, including preferences, favorites, saved items, download history, search activity, settings, and support messages you send us.",
      "We may collect diagnostics, crash logs, device type, operating system version, app version, and basic analytics so we can improve performance and fix bugs.",
    ],
  },
  {
    title: "Photos and media",
    body: [
      "Přism requests photo library access only when needed to save selected media or when you choose media from your device.",
      "We do not scan your full photo library. We only handle the specific media actions you start inside the app.",
    ],
  },
  {
    title: "How we use information",
    body: [
      "We use information to authenticate users, operate the app, save preferences, provide downloads, improve search and browsing, diagnose problems, prevent abuse, and respond to support requests.",
      "If purchases or subscriptions are enabled, purchase status is used only to unlock the relevant app features and support account or billing questions.",
    ],
  },
  {
    title: "Service providers",
    body: [
      "We may use trusted service providers for authentication, hosting, analytics, crash reporting, purchase handling, email support, and app infrastructure.",
      "These providers process information only as needed to provide their services to us and are not allowed to use it for unrelated purposes.",
    ],
  },
  {
    title: "Data retention and deletion",
    body: [
      "We keep information only as long as needed to provide the app, comply with legal obligations, resolve disputes, and protect the service.",
      "You can request account deletion or data access by contacting us at the email below. Some records may remain where required for security, legal, or accounting reasons.",
    ],
  },
  {
    title: "Children",
    body: [
      "Přism is not directed to children under 13, and we do not knowingly collect personal information from children under 13.",
    ],
  },
  {
    title: "Changes",
    body: [
      "We may update this policy when the app or our practices change. The effective date above shows the latest version.",
    ],
  },
];

export default function PrivacyPage() {
  return (
    <>
      <Header />
      <main className="min-h-screen bg-neutral-100 px-6 pb-20 pt-32 sm:px-8">
        <article className="mx-auto max-w-3xl">
          <p className="text-sm font-semibold uppercase text-accent">Effective June 3, 2026</p>
          <h1 className="mt-4 text-4xl font-black leading-tight text-black sm:text-5xl">
            Privacy Policy
          </h1>
          <p className="mt-5 text-lg leading-8 text-neutral-600">
            This Privacy Policy explains how {APP_NAME} handles information when you use the iPhone app, website, and related services.
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
                Questions or deletion requests can be sent to <a className="font-semibold text-accent" href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
              </p>
              <p className="mt-4 text-sm leading-7 text-neutral-500">
                Canonical URL: {SITE_URL}/privacy
              </p>
            </section>
          </div>
        </article>
      </main>
      <Footer />
    </>
  );
}
