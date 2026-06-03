import { APP_NAME } from "@/lib/site-config";

export type SeoRouteContent = {
  slug: "4k-wallpapers" | "amoled-wallpapers" | "home-screen-setups" | "collections";
  navLabel: string;
  title: string;
  description: string;
  h1: string;
  intro: string;
  bullets: [string, string, string];
  sectionTitle: string;
  sectionBody: string;
};

export const seoRouteContent: Record<SeoRouteContent["slug"], SeoRouteContent> = {
  "4k-wallpapers": {
    slug: "4k-wallpapers",
    navLabel: "4K Wallpapers",
    title: `4K iPhone Wallpapers | ${APP_NAME}`,
    description:
      "Browse crisp iPhone wallpapers with Přism, including high-resolution images, Live Photos, matching sets, and profile pictures.",
    h1: "4K iPhone wallpapers with fast discovery",
    intro:
      "Přism focuses on clean browsing, high-quality previews, and simple saving flows for iPhone wallpaper users.",
    bullets: [
      "Discover wallpapers that stay crisp on modern iPhone screens.",
      "Move between categories, search results, and fullscreen previews quickly.",
      "Save the actual media item instead of a low-quality branded preview.",
    ],
    sectionTitle: "Built for iPhone wallpaper browsing",
    sectionBody:
      "Přism keeps the product focused on wallpapers, Live Photos, matching sets, and profile pictures so users are not pushed through unrelated app flows.",
  },
  "amoled-wallpapers": {
    slug: "amoled-wallpapers",
    navLabel: "AMOLED Wallpapers",
    title: `AMOLED iPhone Wallpapers | ${APP_NAME}`,
    description:
      "Find dark, high-contrast wallpapers with Přism, built for iPhone users who want a sharper browsing and saving flow.",
    h1: "AMOLED-style wallpapers that look clean on iPhone",
    intro:
      "Přism makes dark and high-contrast wallpaper discovery simple, organized, and focused on the image itself.",
    bullets: [
      "Browse deep-tone images with clean fullscreen previews.",
      "Use category rows and search to move faster through the catalog.",
      "Save media through iOS-native flows with fewer interruptions.",
    ],
    sectionTitle: "Cleaner dark wallpaper discovery",
    sectionBody:
      "The experience is designed to get users from browsing to saving with less friction and fewer unrelated app surfaces.",
  },
  "home-screen-setups": {
    slug: "home-screen-setups",
    navLabel: "iPhone Wallpapers",
    title: `iPhone Wallpaper App | ${APP_NAME}`,
    description:
      "Přism is an iPhone wallpaper app for high-quality wallpapers, Live Photos, matching sets, and profile pictures.",
    h1: "iPhone wallpaper browsing without the clutter",
    intro:
      "Přism keeps the app centered on finding, previewing, swiping, and saving the media users actually want.",
    bullets: [
      "Browse vertically by category and horizontally within each row.",
      "Open fullscreen previews and swipe to nearby images.",
      "Keep matching sets split so each image can be saved separately.",
    ],
    sectionTitle: "Focused on the core wallpaper flow",
    sectionBody:
      "The app avoids unrelated feeds, coin systems, and extra tool surfaces so the experience stays fast and direct.",
  },
  collections: {
    slug: "collections",
    navLabel: "Collections",
    title: `Wallpaper Collections for iPhone | ${APP_NAME}`,
    description:
      "Browse organized iPhone wallpaper collections with Přism, including Live Photos, matching sets, and profile pictures.",
    h1: "Wallpaper collections organized for faster browsing",
    intro:
      "Přism uses clear categories and media types so users can find the right image without digging through unrelated content.",
    bullets: [
      "Navigate curated categories designed for quick discovery.",
      "Browse wallpapers, Live Photos, matching sets, and profile pictures separately.",
      "Use fullscreen previews and clean save flows for each media item.",
    ],
    sectionTitle: "Collections with a simple product shape",
    sectionBody:
      "Přism treats the catalog as the center of the app and keeps supporting features lightweight around it.",
  },
};

export const seoRouteOrder: SeoRouteContent["slug"][] = [
  "4k-wallpapers",
  "amoled-wallpapers",
  "home-screen-setups",
  "collections",
];
