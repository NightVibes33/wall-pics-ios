import Image from "next/image";
import { APP_NAME, CONTACT_EMAIL } from "@/lib/site-config";

export function Footer() {
  const year = new Date().getFullYear();

  return (
    <div className="w-full rounded-t-4xl sm:rounded-t-[100px] flex flex-col gap-32 items-center justify-center bg-white/60 border-t-4 border-white pt-10 sm:pt-20 px-8 sm:px-12 overflow-hidden">
      <div className="flex sm:flex-row flex-col sm:justify-between justify-start sm:gap-0 gap-10 w-full max-w-7xl relative z-10">
        <div className="flex flex-col gap-8">
          <Image
            src="/assets/ios.png"
            alt={`${APP_NAME} icon`}
            width={48}
            height={48}
            className="squircle"
          />
          <p className="text-neutral-400">© {year} {APP_NAME}.</p>
        </div>

        <div className="flex gap-16 sm:gap-24">
          <div className="flex flex-col gap-2">
            <h3 className="mb-1 text-base font-semibold text-black">Legal</h3>
            <a href="/privacy" className="text-neutral-400 hover:text-black transition-all">
              Privacy
            </a>
            <a href="/terms" className="text-neutral-400 hover:text-black transition-all">
              Terms
            </a>
          </div>

          <div className="flex flex-col gap-2">
            <h3 className="mb-1 text-base font-semibold text-black">Contact</h3>
            <a
              href={`mailto:${CONTACT_EMAIL}`}
              className="text-neutral-400 hover:text-black transition-all break-all"
            >
              Support
            </a>
          </div>
        </div>
      </div>

      <h3
        className="whitespace-nowrap text-neutral-300/50 -ml-20 sm:-ml-40 font-black select-none"
        style={{
          fontSize: "clamp(5rem, 55vw, 120vw)",
          lineHeight: "0.5",
        }}
      >
        Přism
      </h3>
    </div>
  );
}
