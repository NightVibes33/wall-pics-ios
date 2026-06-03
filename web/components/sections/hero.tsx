import Image from "next/image";
import { Smartphone } from "lucide-react";
import { APP_NAME, APP_STORE_URL } from "@/lib/site-config";

export function Hero() {
  return (
    <div className="flex flex-col justify-center items-center min-h-[94vh] animate-up pb-2 px-8">
      <Image
        src="/assets/ios.png"
        alt={`${APP_NAME} app icon`}
        width={96}
        height={96}
        className="shadow-xl shadow-base/40 squircle pointer-events-none"
        priority
      />

      <h1 className="mt-12 w-full max-w-xl text-center text-balance leading-[0.95] text-6xl sm:text-7xl font-[1000] text-black">
        Přism for iPhone
      </h1>

      <p className="mt-6 max-w-xl text-center text-lg sm:text-xl leading-8 text-neutral-600">
        Browse wallpapers, Live Photos, matching sets, and profile pictures with a clean iOS-first experience.
      </p>

      <div className="flex flex-col sm:flex-row gap-2 mt-12">
        <a
          className="flex items-center text-lg justify-center font-semibold gap-2.5 py-2.5 px-5 rounded-xl sm:rounded-3xl transition-all flex-shrink-0 cursor-pointer mx-0.5 bg-accent hover:bg-accent-dark text-white shadow-lg shadow-accent/40 border-t-2 border-white/40"
          target="_blank"
          rel="noopener noreferrer"
          href={APP_STORE_URL}
        >
          <Smartphone className="w-5 h-5" aria-hidden="true" />
          View app
        </a>

        <a
          className="flex items-center text-lg justify-center font-semibold gap-2.5 py-2.5 px-5 rounded-xl sm:rounded-3xl transition-all flex-shrink-0 cursor-pointer mx-0.5 bg-white/60 hover:bg-white text-black border-t-2 border-white shadow-lg shadow-black/5"
          href="/privacy"
        >
          Privacy policy
        </a>
      </div>
    </div>
  );
}
