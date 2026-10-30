import "./globals.css";
import type { Metadata, Viewport } from "next";
import { AppProvider } from "@/components/AppProvider";
import { ServiceWorker } from "@/components/ServiceWorker";

export const metadata: Metadata = {
  title: "Group ERP",
  description: "One app for the whole business group: finance, CRM, RMC, hot-mix, weighbridge, bricks, projects, petrol bunk, fleet, stores and HR.",
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, title: "Group ERP", statusBarStyle: "default" },
};
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#0f766e" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AppProvider>{children}</AppProvider>
        <ServiceWorker />
      </body>
    </html>
  );
}
