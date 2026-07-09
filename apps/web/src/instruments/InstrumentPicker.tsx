"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { loadCatalog, searchInstruments, knownExchanges, type Instrument } from "./catalog";

/**
 * Type-to-search stock/ETF picker backed by the (daily-refreshed, offline)
 * instruments catalog. Optionally scoped to a single exchange. Returns the
 * chosen instrument so the caller can store both symbol and exchange.
 */
export function InstrumentPicker({
  value,
  exchange,
  onChange,
  placeholder = "Search a stock or ETF…",
}: {
  value: { symbol: string; exchange: string } | null;
  exchange: string | null;
  onChange: (i: Instrument | null) => void;
  placeholder?: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Instrument[]>([]);
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let live = true;
    const handle = setTimeout(async () => {
      const r = await searchInstruments(query, exchange, 30);
      if (live) setResults(r);
    }, 150);
    return () => { live = false; clearTimeout(handle); };
  }, [query, exchange, open]);

  const label = value ? `${value.symbol} · ${value.exchange}` : "";

  return (
    <div ref={boxRef} style={{ position: "relative" }} onBlur={(e) => { if (!boxRef.current?.contains(e.relatedTarget as Node)) setOpen(false); }}>
      <input
        className="input"
        value={open ? query : label}
        placeholder={placeholder}
        onFocus={() => { setOpen(true); setQuery(""); }}
        onChange={(e) => { setQuery(e.target.value); setOpen(true); }}
      />
      {value && !open && (
        <button type="button" onMouseDown={(e) => { e.preventDefault(); onChange(null); }}
          aria-label="Clear" style={{ position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", border: "none", background: "transparent", cursor: "pointer", color: "var(--text-2)", fontSize: 16 }}>×</button>
      )}
      {open && (
        <div style={{ position: "absolute", zIndex: 30, top: "calc(100% + 4px)", left: 0, right: 0, maxHeight: 280, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, boxShadow: "var(--shadow)" }}>
          {results.length === 0 && (
            <div className="muted" style={{ padding: "10px 12px", fontSize: 13 }}>
              {query.trim() ? "No matches. Type a ticker or company name." : "Start typing a ticker or company name."}
            </div>
          )}
          {results.map((i) => (
            <button key={`${i.symbol}|${i.exchange}`} type="button"
              onMouseDown={(e) => { e.preventDefault(); onChange(i); setQuery(""); setOpen(false); }}
              style={{ display: "flex", justifyContent: "space-between", gap: 10, width: "100%", textAlign: "left", padding: "9px 12px", border: "none", background: value && i.symbol === value.symbol && i.exchange === value.exchange ? "var(--accent-ghost)" : "transparent", cursor: "pointer", fontSize: 14, color: "var(--text)" }}>
              <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                <strong>{i.symbol}</strong> <span className="muted">{i.name}</span>
              </span>
              <span className="muted" style={{ flexShrink: 0, fontSize: 12 }}>{i.exchange} · {i.currency}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Exchange scope selector — "All" plus every exchange present in the catalog. */
export function ExchangeSelect({ value, onChange }: { value: string | null; onChange: (ex: string | null) => void }) {
  const [exchanges, setExchanges] = useState<string[]>([]);
  useEffect(() => { void loadCatalog().then((all) => setExchanges(knownExchanges(all))); }, []);
  const opts = useMemo(() => ["All exchanges", ...exchanges], [exchanges]);
  return (
    <select className="input" value={value ?? "All exchanges"} onChange={(e) => onChange(e.target.value === "All exchanges" ? null : e.target.value)}>
      {opts.map((o) => <option key={o} value={o}>{o}</option>)}
    </select>
  );
}
