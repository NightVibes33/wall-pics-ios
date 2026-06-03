import { Button } from "@/components/ui/button";
import { APP_STORE_URL } from "@/lib/site-config";

export function FinalCtaSection() {
  return (
    <section className="py-20 sm:py-24">
      <div className="mx-auto w-full max-w-6xl px-4 sm:px-6 lg:px-8">
        <article className="rounded-3xl border border-white/10 bg-gradient-to-r from-base-800 to-base-850 p-8 sm:p-12">
          <h2 className="text-balance text-3xl font-bold tracking-tight text-white sm:text-4xl">
            Ready to upgrade your phone&apos;s look?
          </h2>
          <p className="mt-4 max-w-2xl text-base leading-relaxed text-white/75">
            View Přism on the App Store and discover a cleaner, richer, and
            more intentional personalization flow.
          </p>

          <div className="mt-7 flex flex-wrap gap-3">
            <Button href={APP_STORE_URL}>View app</Button>
          </div>
        </article>
      </div>
    </section>
  );
}
