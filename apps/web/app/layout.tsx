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
  themeColor: "#efe9df",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" dir="ltr">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,500;9..144,600;9..144,700&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <Providers>
          <AppShell>{children}</AppShell>
        </Providers>
      </body>
    </html>
  );
}
