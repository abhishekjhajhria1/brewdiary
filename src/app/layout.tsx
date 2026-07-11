import type { Metadata, Viewport } from "next";
import { Hanken_Grotesk, Newsreader } from "next/font/google";
import "./globals.css";
import { TabBar } from "@/components/ui/TabBar";
import { TopBar } from "@/components/ui/TopBar";
import { PWA } from "@/components/ui/PWA";
import { AgeGate } from "@/components/onboarding/AgeGate";
import { NO_FLASH_SCRIPT } from "@/lib/theme";
import { AGE_FLAG_SCRIPT, AGE_GATE_STYLE } from "@/lib/age";

// Type voice: "editorial whisper" — a humanist grotesque for everything,
// with a restrained editorial serif reserved for moments (month name, titles).
const grotesque = Hanken_Grotesk({
  subsets: ["latin"],
  variable: "--font-grotesque",
  display: "swap",
});

const serif = Newsreader({
  subsets: ["latin"],
  variable: "--font-serif",
  style: ["normal", "italic"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "brewdiary",
  description: "An all-inclusive drink diary. Tap a day, log a drink, watch the year quietly fill in.",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: [
      { url: "/icon.svg", type: "image/svg+xml" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: "/apple-touch-icon.png",
  },
  appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "brewdiary" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover", // let the app paint under notches; safe-area insets handle spacing
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ece7f2" },
    { media: "(prefers-color-scheme: dark)", color: "#0b0c12" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${grotesque.variable} ${serif.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: NO_FLASH_SCRIPT }} />
        <script dangerouslySetInnerHTML={{ __html: AGE_FLAG_SCRIPT }} />
        <style dangerouslySetInnerHTML={{ __html: AGE_GATE_STYLE }} />
      </head>
      <body>
        <div className="mx-auto flex min-h-dvh w-full max-w-2xl flex-col px-5 pb-[calc(7rem+env(safe-area-inset-bottom))] pt-[max(2rem,env(safe-area-inset-top))] sm:pt-[max(3rem,env(safe-area-inset-top))]">
          <TopBar />
          {children}
        </div>
        <TabBar />
        <PWA />
        <AgeGate />
      </body>
    </html>
  );
}
