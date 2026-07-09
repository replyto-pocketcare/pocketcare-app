"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { isCatalogReady, refreshCatalog, refreshCatalogWithProgress, type CatalogFetchResult } from "./catalog";

export type CatalogPhase = "checking" | "seed" | "loading" | "ready" | "offline" | "error";

/**
 * Manages the instruments catalog for the investments screen. The full ticker
 * database is only downloaded for people who actually track investments, and
 * only the first time they open the picker — with a progress bar. After that,
 * opening the screen kicks off a silent once-a-day refresh.
 *
 * @param active whether the user has investment accounts (gates the download).
 * @param autoStart start the one-time download immediately vs. on demand.
 */
export function useCatalog(active: boolean, autoStart = true) {
  const [phase, setPhase] = useState<CatalogPhase>("checking");
  const [pct, setPct] = useState(0);
  const started = useRef(false);

  const start = useCallback(() => {
    if (started.current) return;
    started.current = true;
    setPhase("loading");
    setPct(0);
    void refreshCatalogWithProgress(setPct).then((r: CatalogFetchResult) => {
      // On offline/error the seed still powers the picker, so let them proceed;
      // we surface the state so the UI can show a gentle note + retry.
      setPhase(r === "ok" || r === "unchanged" ? "ready" : r);
    });
  }, []);

  const retry = useCallback(() => {
    started.current = false;
    start();
  }, [start]);

  useEffect(() => {
    if (!active) return;
    let live = true;
    void isCatalogReady().then((ready) => {
      if (!live) return;
      if (ready) {
        setPhase("ready");
        void refreshCatalog().catch(() => {}); // silent daily refresh in the background
      } else if (autoStart) {
        start();
      } else {
        setPhase("seed");
      }
    });
    return () => { live = false; };
  }, [active, autoStart, start]);

  return { phase, pct, start, retry };
}
