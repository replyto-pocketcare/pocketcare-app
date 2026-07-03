"use client";

import { useEffect, useState, type ReactNode } from "react";
import type { AbstractPowerSyncDatabase } from "@powersync/common";
import { PowerSyncContext } from "@powersync/react";
import { initI18n } from "@pocketcare/i18n";
import { lightTheme } from "@pocketcare/ui-tokens";
import { initSystem } from "../src/powersync";
import { Spinner } from "../src/ui/Spinner";

// Boot i18n once. Prefer the user's saved choice, else the browser language.
const savedLang = typeof window !== "undefined" ? localStorage.getItem("lang") : null;
const bootLang = savedLang || (typeof navigator !== "undefined" ? navigator.language.split("-")[0] : "en") || "en";
initI18n(bootLang);
if (typeof document !== "undefined") document.documentElement.lang = bootLang;

/**
 * Client-only provider. PowerSync web (WASM SQLite) cannot run during SSR, so we
 * render a lightweight placeholder on the server and until the DB is ready, then
 * mount the real context. This keeps `useQuery` in pages from ever running
 * without a database.
 */
export function Providers({ children }: { children: ReactNode }) {
  const [db, setDb] = useState<AbstractPowerSyncDatabase | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    initSystem()
      .then((ready) => active && setDb(ready))
      .catch((e) => active && setError(String(e?.message ?? e)));
    return () => {
      active = false;
    };
  }, []);

  if (error) {
    return (
      <div style={fallback}>
        <div>
          <strong>Couldn’t start PocketCare.</strong>
          <div style={{ color: lightTheme.textSecondary, marginTop: 8, fontSize: 13 }}>{error}</div>
          <div style={{ color: lightTheme.textSecondary, marginTop: 8, fontSize: 13 }}>
            Check your <code>.env</code> (NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY / _POWERSYNC_URL).
          </div>
        </div>
      </div>
    );
  }

  if (!db) {
    return (
      <div style={fallback}>
        <div style={{ display: "grid", placeItems: "center", gap: 16 }}>
          <Spinner size={38} />
          <span style={{ color: lightTheme.textSecondary }}>Loading PocketCare…</span>
        </div>
      </div>
    );
  }

  return <PowerSyncContext.Provider value={db}>{children}</PowerSyncContext.Provider>;
}

const fallback: React.CSSProperties = {
  minHeight: "60vh",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  padding: 24,
  textAlign: "center",
};
