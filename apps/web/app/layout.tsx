import type { ReactNode } from "react";
import "./globals.css";
import { Providers } from "./providers";
import { AppShell } from "./AppShell";

export const metadata = {
  title: "PocketCare",
  description: "Offline-first, multi-currency expense & wealth manager",
  manifest: "/manifest.webmanifest",
  applicationName: "PocketCare",
  appleWebApp: { capable: true, title: "PocketCare", statusBarStyle: "default" as const },
};

export const viewport = {
  themeColor: "#faf6f1",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr">
      <body>
        <Providers>
          <AppShell>{children}</AppShell>
        </Providers>
      </body>
    </html>
  );
}
