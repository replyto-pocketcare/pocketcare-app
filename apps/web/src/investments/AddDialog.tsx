"use client";

/**
 * Contextual "add investment" dialog. Opened either from the top of the page
 * (choose any type) or from a group tile (prefilled with that exchange/class,
 * so adding under e.g. BSE adds a BSE stock). Handles stocks, mutual funds,
 * SIPs, crypto, fixed deposits and other schemes, and asks whether the money is
 * an existing holding (track only) or a new investment funded from a savings
 * account.
 */
import { useState } from "react";
import type { Period } from "@pocketcare/types";
import { money, fromMajor } from "@pocketcare/money";
import { Modal } from "../ui/Modal";
import { FloatingInput } from "../ui/FloatingInput";
import { useMoneyFmt } from "../ui/Money";
import { InstrumentPicker, ExchangeSelect } from "../instruments/InstrumentPicker";
import type { Instrument } from "../instruments/catalog";
import { useCatalog } from "../instruments/hooks";
import { CatalogProgress } from "../instruments/CatalogProgress";
import { ASSET_CLASSES, isListed, classMeta, type AssetClass } from "./model";
import { addHolding } from "./write";

interface InvAccount { id: string; name: string; currency: string; type: string }
interface FundAccount { id: string; name: string; currency: string; balance: number }
const SIP_CYCLES: Period[] = ["weekly", "monthly", "yearly"];

export function AddInvestmentDialog({ ctx, accounts, availableOf, fundingAccounts, base, onClose }: {
  ctx: { assetClass?: AssetClass; exchange?: string | null; accountId?: string };
  accounts: InvAccount[];
  availableOf: (id: string) => number;
  fundingAccounts: FundAccount[];
  base: string;
  onClose: () => void;
}) {
  const fmt = useMoneyFmt();
  const [cls, setCls] = useState<AssetClass>(ctx.assetClass ?? "stock");
  const [accId, setAccId] = useState(ctx.accountId ?? accounts[0]?.id ?? "");
  const [listed, setListed] = useState(true);
  const [instrument, setInstrument] = useState<Instrument | null>(null);
  const [exFilter, setExFilter] = useState<string | null>(ctx.exchange ?? null);
  const [name, setName] = useState("");
  const [qty, setQty] = useState("");
  const [cost, setCost] = useState("");
  const [curVal, setCurVal] = useState("");
  const [rate, setRate] = useState("");
  const [maturity, setMaturity] = useState("");
  const [sipAmt, setSipAmt] = useState("");
  const [sipFreq, setSipFreq] = useState<Period>("monthly");
  // Funding: "existing" = already own it (track only); "new" = fund from an account.
  const [funding, setFunding] = useState<"existing" | "new">("existing");
  const [sourceId, setSourceId] = useState(fundingAccounts[0]?.id ?? "");
  const [saving, setSaving] = useState(false);

  const cat = useCatalog(true);
  const downloading = cat.phase === "loading" || cat.phase === "checking";
  const acc = accounts.find((a) => a.id === accId) ?? accounts[0];
  const classIsListed = isListed(cls);
  const useCatalogPicker = classIsListed && listed;
  const cur = useCatalogPicker ? (instrument?.currency || acc?.currency || base) : (acc?.currency || base);
  const meta = classMeta(cls);

  // FDs and lump schemes: the "amount" is the invested principal (qty=1, cost=amount).
  const isLump = cls === "fd";
  const qtyNum = isLump ? 1 : Number(qty) || 0;
  const costMinor = isLump
    ? (cost ? fromMajor(Number(cost), cur).amount : 0)
    : (cost ? fromMajor(Number(cost), cur).amount : 0);
  const costTotal = Math.round(costMinor * qtyNum);

  const nameOk = useCatalogPicker ? !!instrument : !!name.trim();
  const source = fundingAccounts.find((f) => f.id === sourceId);
  const overFunds = funding === "new" && source ? costTotal > source.balance : false;
  const canAdd = !!acc && nameOk && (isLump ? !!cost : !!qty) && (funding === "existing" || (!!sourceId && !overFunds));

  async function submit() {
    if (!canAdd || !acc) return;
    setSaving(true);
    try {
      const sym = useCatalogPicker ? instrument!.symbol : "";
      const exch = useCatalogPicker ? instrument!.exchange : (cls === "stock" ? (exFilter ?? null) : null);
      await addHolding({
        investmentAccountId: acc.id,
        assetClass: cls,
        symbol: sym,
        exchange: exch,
        name: useCatalogPicker ? (instrument!.symbol) : name.trim(),
        quantity: qtyNum,
        avgCost: costMinor || null,
        currency: cur,
        currentValue: !classIsListed && curVal ? fromMajor(Number(curVal), cur).amount : null,
        annualRate: cls === "fd" && rate ? Number(rate) : null,
        maturityDate: cls === "fd" && maturity ? maturity : null,
        offList: !useCatalogPicker,
        autoFetch: useCatalogPicker,
        funding: funding === "new" ? { mode: "new", sourceAccountId: sourceId } : { mode: "existing" },
        sip: cls === "sip" && sipAmt ? { amount: fromMajor(Number(sipAmt), cur).amount, frequency: sipFreq, expectedReturnPct: rate ? Number(rate) : null } : null,
      });
      onClose();
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open onClose={onClose}>
      <div style={{ display: "grid", gap: 12, maxWidth: 560 }}>
        <h2 style={{ margin: 0 }}>Add investment</h2>

        {/* Type */}
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {ASSET_CLASSES.map((a) => (
            <button key={a.key} className="chip" data-active={a.key === cls} onClick={() => { setCls(a.key); if (!isListed(a.key)) setListed(false); else setListed(true); }}>
              <span style={{ opacity: 0.7, marginRight: 4 }}>{a.icon}</span>{a.label}
            </button>
          ))}
        </div>

        {/* Which investment account */}
        {accounts.length > 1 && (
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Investment account
            <select className="input" value={accId} onChange={(e) => setAccId(e.target.value)}>
              {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </label>
        )}

        {/* Instrument (listed stocks/MFs) or free-text name */}
        {classIsListed && (
          <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
            <button className="chip" data-active={listed} onClick={() => setListed(true)}>In our list</button>
            <button className="chip" data-active={!listed} onClick={() => setListed(false)}>Not listed</button>
          </div>
        )}
        {useCatalogPicker ? (
          <>
            <CatalogProgress phase={cat.phase as never} pct={cat.pct} onRetry={cat.retry} />
            <div style={{ display: "grid", gap: 8, opacity: downloading ? 0.5 : 1, pointerEvents: downloading ? "none" : "auto" }}>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                <div style={{ width: 160, flexShrink: 0 }}><ExchangeSelect value={exFilter} onChange={setExFilter} /></div>
                <div style={{ flex: 1, minWidth: 200 }}><InstrumentPicker value={instrument} exchange={exFilter} onChange={setInstrument} /></div>
              </div>
            </div>
          </>
        ) : (
          <FloatingInput label={`${meta.label} name`} value={name} onChange={setName} />
        )}

        {/* Amount / quantity */}
        {isLump ? (
          <FloatingInput label={`Amount invested (${cur})`} group currency={cur} value={cost} onChange={setCost} />
        ) : (
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={cls === "mf" || cls === "sip" ? "Units" : meta.unitWord ? meta.unitWord.replace(/^./, (c) => c.toUpperCase()) : "Qty"} inputMode="decimal" value={qty} onChange={(v) => setQty(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
            <FloatingInput label={`${cls === "mf" || cls === "sip" ? "NAV / avg cost" : "Avg cost"} (${cur})`} group currency={cur} value={cost} onChange={setCost} style={{ flex: 1 }} />
          </div>
        )}

        {/* Type-specific extras */}
        {cls === "fd" && (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <FloatingInput label="Interest % p.a." inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1, minWidth: 120 }} />
            <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, flex: 1, minWidth: 150 }}>Maturity date
              <input className="input" type="date" value={maturity} onChange={(e) => setMaturity(e.target.value)} />
            </label>
          </div>
        )}
        {cls === "sip" && (
          <div style={{ display: "grid", gap: 6 }}>
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
              <FloatingInput label={`SIP amount (${cur})`} group currency={cur} value={sipAmt} onChange={setSipAmt} style={{ flex: 1, minWidth: 140 }} />
              <div style={{ display: "flex", gap: 6 }}>{SIP_CYCLES.map((c) => <button key={c} className="chip" data-active={c === sipFreq} onClick={() => setSipFreq(c)}>{c}</button>)}</div>
            </div>
            <div className="muted" style={{ fontSize: 11 }}>Adds a recurring saving to Planned Cashflow so your SIP shows up there too.</div>
          </div>
        )}
        {!classIsListed && cls !== "sip" && (
          <FloatingInput label={`Current value (${cur}, optional)`} group currency={cur} value={curVal} onChange={setCurVal} />
        )}

        {/* Existing vs new */}
        <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
          <div className="muted" style={{ fontSize: 12 }}>Is this a new investment or one you already hold?</div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            <button className="chip" data-active={funding === "existing"} onClick={() => setFunding("existing")}>I already hold it (track only)</button>
            <button className="chip" data-active={funding === "new"} onClick={() => setFunding("new")} disabled={fundingAccounts.length === 0}>New — fund from account</button>
          </div>
          {funding === "new" && (
            fundingAccounts.length === 0 ? (
              <div className="muted" style={{ fontSize: 12 }}>No savings/bank account to fund from — add one first, or track it as existing.</div>
            ) : (
              <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Deduct {costTotal > 0 ? fmt(money(costTotal, cur)) : "the amount"} from
                <select className="input" value={sourceId} onChange={(e) => setSourceId(e.target.value)}>
                  {fundingAccounts.map((f) => <option key={f.id} value={f.id}>{f.name} · {fmt(money(f.balance, f.currency))}</option>)}
                </select>
              </label>
            )
          )}
          {overFunds && <div style={{ fontSize: 12, color: "var(--negative)" }}>That’s more than the balance in {source?.name}. Reduce the amount or pick another account.</div>}
          {funding === "existing" && <div className="muted" style={{ fontSize: 11 }}>No money leaves your accounts — this only records an investment you already own.</div>}
        </div>

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 2 }}>
          <button className="btn ghost" onClick={onClose} disabled={saving}>Cancel</button>
          <button className="btn" onClick={submit} disabled={!canAdd || saving}>{saving ? "Adding…" : "Add investment"}</button>
        </div>
      </div>
    </Modal>
  );
}
