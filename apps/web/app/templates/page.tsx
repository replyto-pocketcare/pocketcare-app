"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { softDelete } from "../../src/write";
import { useTemplates, useRules, useDueRules } from "../../src/templates/hooks";
import { createTemplate, createRule, postRuleOnce, skipRuleOnce, type Freq } from "../../src/templates/write";

const FREQS: Freq[] = ["daily", "weekly", "monthly", "yearly"];
const every = (f: string, n: number) => (n > 1 ? `every ${n} ${f.replace("ly", n === 1 ? "" : "s").replace("dai", "day")}` : f);

export default function TemplatesPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const templates = useTemplates();
  const rules = useRules();
  const due = useDueRules();
  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at",
  );

  // create template
  const [showT, setShowT] = useState(false);
  const [tName, setTName] = useState("");
  const [tType, setTType] = useState<"expense" | "income">("expense");
  const [tAmount, setTAmount] = useState("");
  const [tAccount, setTAccount] = useState("");
  const [tDesc, setTDesc] = useState("");

  // create rule
  const [showR, setShowR] = useState(false);
  const [rTemplate, setRTemplate] = useState("");
  const [rFreq, setRFreq] = useState<Freq>("monthly");
  const [rDue, setRDue] = useState(new Date().toISOString().slice(0, 10));
  const [rAuto, setRAuto] = useState(false);
  const [busy, setBusy] = useState(false);

  async function addTemplate() {
    if (!tName.trim()) return;
    setBusy(true);
    try {
      await createTemplate({ name: tName, type: tType, amount: tAmount ? Number(tAmount) : null, accountId: tAccount || null, description: tDesc.trim() || null });
      setTName(""); setTAmount(""); setTAccount(""); setTDesc(""); setShowT(false);
    } finally { setBusy(false); }
  }
  async function addRule() {
    if (!rTemplate) return;
    setBusy(true);
    try { await createRule({ templateId: rTemplate, frequency: rFreq, firstDue: rDue, autoPost: rAuto }); setRTemplate(""); setRAuto(false); setShowR(false); }
    finally { setBusy(false); }
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Templates &amp; recurring</h1>
        <button className="btn" onClick={() => setShowT(true)}>+ New template</button>
      </div>

      {/* Due-to-confirm tray */}
      {due.length > 0 && (
        <section className="card" style={{ padding: 16, display: "grid", gap: 10, borderColor: "var(--accent-soft)", background: "var(--accent-ghost)" }}>
          <strong style={{ fontSize: 14 }}>Recurring due — confirm to record</strong>
          {due.map((r) => (
            <div key={r.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
              <span style={{ fontSize: 14 }}>{r.template_name} <span className="muted" style={{ fontSize: 12 }}>· due {r.next_due}{r.amount != null ? ` · ${fmt(money(r.amount, r.currency ?? base))}` : ""}</span></span>
              <div style={{ display: "flex", gap: 8 }}>
                <button className="chip" onClick={() => void skipRuleOnce(r.id)}>Skip</button>
                <button className="btn" style={{ padding: "4px 12px", fontSize: 13, minHeight: 0 }} onClick={() => void postRuleOnce(r.id)}>Record</button>
              </div>
            </div>
          ))}
        </section>
      )}

      {/* Templates */}
      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0, fontSize: 17 }}>Templates</h2>
        {templates.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No templates yet. Create one for things you log often — rent, salary, groceries.</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {templates.map((t) => (
              <div key={t.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "10px 12px", borderBottom: "1px solid var(--border)" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.name}</div>
                  <div className="muted" style={{ fontSize: 12 }}>{t.type}{t.amount != null ? ` · ${fmt(money(t.amount, t.currency ?? base))}` : ""}{t.split_group_id ? " · split" : ""}</div>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                  <Link href={`/transactions/new?template=${t.id}`} className="chip">Use</Link>
                  <KebabMenu label={`${t.name} actions`} items={[{ label: "Delete", danger: true, onClick: () => softDelete("transaction_templates", t.id) }]} />
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Recurring rules */}
      <section style={{ display: "grid", gap: 8 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h2 style={{ margin: 0, fontSize: 17 }}>Recurring</h2>
          {templates.length > 0 && <button className="chip" onClick={() => { setRTemplate(templates[0]!.id); setShowR(true); }}>+ Add recurring</button>}
        </div>
        {rules.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No recurring rules. Turn a template into a recurring payment or salary.</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {rules.map((r) => (
              <div key={r.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "10px 12px", borderBottom: "1px solid var(--border)" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{r.template_name}</div>
                  <div className="muted" style={{ fontSize: 12 }}>{every(r.frequency, r.interval_count)} · next {r.next_due} · {r.auto_post ? "auto" : "confirm"}</div>
                </div>
                <KebabMenu label={`${r.template_name} recurring actions`} items={[
                  { label: "Post now", onClick: () => void postRuleOnce(r.id) },
                  { label: "Delete", danger: true, onClick: () => softDelete("recurring_rules", r.id) },
                ]} />
              </div>
            ))}
          </div>
        )}
      </section>

      {/* New template dialog */}
      <Modal open={showT} onClose={() => setShowT(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>New template</h2>
          <input className="input" placeholder="Name (e.g. Rent, Salary)" value={tName} onChange={(e) => setTName(e.target.value)} />
          <div style={{ display: "flex", gap: 6 }}>
            {(["expense", "income"] as const).map((k) => <button key={k} className="chip" data-active={k === tType} style={{ textTransform: "capitalize" }} onClick={() => setTType(k)}>{k}</button>)}
          </div>
          <input className="input" inputMode="decimal" placeholder={`Amount (${base}) — optional`} value={tAmount} onChange={(e) => setTAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>Account</span>
            <select className="input" value={tAccount} onChange={(e) => setTAccount(e.target.value)}>
              <option value="">Choose at use time</option>
              {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </label>
          <input className="input" placeholder="Description (optional)" value={tDesc} onChange={(e) => setTDesc(e.target.value)} />
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowT(false)}>Cancel</button>
            <button className="btn" onClick={() => void addTemplate()} disabled={busy || !tName.trim()}>Create</button>
          </div>
        </div>
      </Modal>

      {/* New recurring dialog */}
      <Modal open={showR} onClose={() => setShowR(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>New recurring</h2>
          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>Template</span>
            <select className="input" value={rTemplate} onChange={(e) => setRTemplate(e.target.value)}>
              {templates.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </label>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {FREQS.map((f) => <button key={f} className="chip" data-active={f === rFreq} style={{ textTransform: "capitalize" }} onClick={() => setRFreq(f)}>{f}</button>)}
          </div>
          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>First due date</span>
            <input className="input" type="date" value={rDue} onChange={(e) => setRDue(e.target.value)} />
          </label>
          <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14 }}>
            <input type="checkbox" checked={rAuto} onChange={(e) => setRAuto(e.target.checked)} />
            Post automatically (otherwise I'll confirm each time)
          </label>
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowR(false)}>Cancel</button>
            <button className="btn" onClick={() => void addRule()} disabled={busy || !rTemplate}>Create</button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
