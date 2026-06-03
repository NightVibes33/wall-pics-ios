import type { Metadata } from "next";
import { Manrope } from "next/font/google";
import "./globals.css";
import { APP_NAME, SITE_URL } from "@/lib/site-config";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: `${APP_NAME} - iPhone Wallpaper App`,
  description:
    "Přism is an iPhone wallpaper app for browsing high-quality wallpapers, Live Photos, matching sets, and profile pictures.",
  alternates: {
    canonical: "/",
  },
  icons: {
    icon: "/assets/ios.png",
    shortcut: "/assets/ios.png",
    apple: "/assets/ios.png",
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    title: `${APP_NAME} - iPhone Wallpaper App`,
    description:
      "Browse high-quality wallpapers, Live Photos, matching sets, and profile pictures for iPhone.",
    siteName: APP_NAME,
    images: [
      {
        url: "/assets/screenshots/screen1.jpg",
        width: 390,
        height: 844,
        alt: "Přism app screenshot",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: `${APP_NAME} - iPhone Wallpaper App`,
    description:
      "Browse high-quality wallpapers, Live Photos, matching sets, and profile pictures for iPhone.",
    images: ["/assets/screenshots/screen1.jpg"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="bg-neutral-100">
      <body className={`${manrope.variable} bg-neutral-100 text-black antialiased min-h-screen overflow-x-hidden`}>
        {children}
      </body>
    </html>
  );
}
