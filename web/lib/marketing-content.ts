import { APP_NAME, APP_STORE_URL } from "@/lib/site-config";

export const trustPoints = [
  "iOS-first",
  "TestFlight ready",
  "Built for fast wallpaper discovery",
] as const;

export const credibilityItems = [
  { label: "iOS-first", detail: "Designed around the way iPhone users browse and save media" },
  { label: "Fast browsing", detail: "Focused on quick discovery and fewer dead loading states" },
  { label: "Clean library", detail: "Organized around wallpapers, Live Photos, sets, and profile pictures" },
  {
    label: "Private by design",
    detail: "Account and app data are handled only to run the experience",
  },
] as const;

export const featureItems = [
  {
    title: "High-quality wallpapers",
    body: "Find polished wallpapers made to look crisp on modern iPhone displays.",
  },
  {
    title: "Live Photos",
    body: "Browse motion-ready wallpapers with a flow built around iOS saving behavior.",
  },
  {
    title: "Matching sets",
    body: "Discover paired and group sets where each image can be viewed and saved separately.",
  },
  {
    title: "Profile pictures",
    body: "Find square and circular-ready profile images without fighting bad crops.",
  },
  {
    title: "Better search",
    body: "Search across wallpaper types with clearer results and less random clutter.",
  },
  {
    title: "Simple library flow",
    body: "The app keeps the focus on browsing, viewing, swiping, and saving.",
  },
] as const;

export const galleryItems = [
  { title: "Explore Wallpapers", image: "/assets/screenshots/screen1.jpg" },
  { title: "Browse Live Photos", image: "/assets/screenshots/screen2.jpg" },
  { title: "Matching Sets", image: "/assets/screenshots/screen3.jpg" },
  { title: "Preview Fullscreen", image: "/assets/screenshots/screen4.jpg" },
  { title: "Save Your Look", image: "/assets/screenshots/screen5.jpg" },
] as const;

export const faqItems = [
  {
    q: "What is Přism?",
    a: `${APP_NAME} is an iPhone wallpaper app focused on browsing wallpapers, Live Photos, matching sets, and profile pictures in one clean experience.`,
  },
  {
    q: "Is Přism available on iPhone?",
    a: `${APP_NAME} is set up for iOS distribution and is being prepared through TestFlight and App Store Connect.`,
  },
  {
    q: "Does Přism support Live Photos?",
    a: "The app is built around iOS media flows, including Live Photo wallpaper browsing and saving behavior.",
  },
  {
    q: "Does Přism include matching sets?",
    a: "Yes. Matching sets are treated as separate images so each person can save the copy they want.",
  },
  {
    q: "Where can I view the app listing?",
    a: `The App Store record is ${APP_STORE_URL}`,
  },
] as const;
