import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { APP_STORE_URL } from "@/lib/site-config";

export function FutureSection() {
  return (
    <section id="future" className="relative overflow-hidden py-20 sm:py-24">
      <div className="absolute inset-0 bg-gradient-to-r from-accent/10 via-transparent to-accent/5" />
      <div className="relative mx-auto w-full max-w-6xl px-4 sm:px-6 lg:px-8">
        <article className="rounded-3xl border border-accent/25 bg-base-800/75 p-8 sm:p-10">
          <Badge>Coming next</Badge>
          <h2 className="mt-4 text-balance text-3xl font-bold tracking-tight text-white sm:text-4xl">
            Přism is ready for iPhone
          </h2>
          <p className="mt-4 max-w-3xl text-base leading-relaxed text-white/75">
            Přism is evolving toward even more polished personalization tools, smarter
            discovery, and expanded platform support. We are building carefully so each
            step stays polished.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <Button href={APP_STORE_URL}>View app</Button>
          </div>
        </article>
      </div>
    </section>
  );
}
