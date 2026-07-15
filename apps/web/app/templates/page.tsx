"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../src/hooks";
import { useEntitlement } from "../../src/entitlement";
import { useMoneyFmt } from "../../src/ui/Money";
import { Modal } from "../../src/ui/Modal";
import { UpgradeModal } from "../../src/ui/UpgradeModal";
import { KebabMenu } from "../../src/ui/KebabMenu";
import { useConfirm } from "../../src/ui/Confirm";
import { softDelete } from "../../src/write";
import { useTemplates, useRules, useDueRules, type Template } from "../../src/templates/hooks";
import { createTemplate, updateTemplate, reorderTemplates, createRule, postRuleOnce, skipRuleOnce, FREE_TEMPLATE_LIMIT, type Freq } from "../../src/templates/write";

const FREQS: Freq[] = ["daily", "weekly", "monthly", "yearly"];
const every = (f: string, n: number) => (n > 1 ? `every ${n} ${f.replace("ly", "").replace("dai", "day")}s` : f);

export default function TemplatesPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const { isPaid } = useEntitlement();
  const templates = useTemplates();
  const rules = useRules();
  const due = useDueRules();
  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' AND type NOT IN ('stocks','mutual_funds') ORDER BY created_at",
  );

  const [showUpgrade, setShowUpgrade] = useState(false);
  const atLimit = !isPaid && templates.length >= FREE_TEMPLATE_LIMIT;

  // create / edit template
  const [showT, setShowT] = useState(false);
  const [editTpl, setEditTpl] = useState<Template | null>(null);
  const [tName, setTName] = useState("");
  const [tType, setTType] = useState<"expense" | "income">("expense");
  const [tAmount, setTAmount] = useState("");
  const [tAccount, setTAccount] = useState("");
  const [tDesc, setTDesc] = useState("");
  const [busy, setBusy] = useState(false);

  function openNew() {
    if (atLimit) { setShowUpgrade(true); return; }
    setEditTpl(null); setTName(""); setTType("expense"); setTAmount(""); setTAccount(""); setTDesc(""); setShowT(true);
  }
  function openEdit(t: Template) {
    setEditTpl(t); setTName(t.name); setTType(t.type === "income" ? "income" : "expense");
    setTAmount(t.amount != null ? String(t.amount / 100) : ""); setTAccount(t.account_id ?? ""); setTDesc(t.description ?? ""); setShowT(true);
  }
  async function submitTemplate() {
    if (!tName.trim()) return;
    setBusy(true);
    try {
      const input = {
        name: tName, type: tType, amount: tAmount ? Number(tAmount) : null, accountId: tAccount || null,
        description: tDesc.trim() || null,
        // preserve fields the simple form doesn't edit
        categoryId: editTpl?.category_id ?? null, note: editTpl?.note ?? null, paymentMethod: editTpl?.payment_method ?? null,
        labels: editTpl?.labels ? editTpl.labels.split(",").map((s) => s.trim()).filter(Boolean) : [],
        splitGroupId: editTpl?.split_group_id ?? null, splitMode: (editTpl?.split_mode as "equal" | "exact" | "percent") ?? "equal",
      };
      if (editTpl) await updateTemplate(editTpl.id, input);
      else await createTemplate(input);
      setShowT(false);
    } finally { setBusy(false); }
  }

  async function move(i: number, dir: -1 | 1) {
    const j = i + dir;
    if (j < 0 || j >= templates.length) return;
    const ids = templates.map((t) => t.id);
    [ids[i], ids[j]] = [ids[j]!, ids[i]!];
    await reorderTemplates(ids);
  }

  // create rule
  const [showR, setShowR] = useState(false);
  const [rTemplate, setRTemplate] = useState("");
  const [rFreq, setRFreq] = useState<Freq>("monthly");
  const [rDue, setRDue] = useState(new Date().toISOString().slice(0, 10));
  const [rAuto, setRAuto] = useState(false);
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
        <button className="btn" onClick={openNew}>+ New template</button>
      </div>

      {!isPaid && (
        <div className="muted" style={{ fontSize: 12.5 }}>
          {templates.length}/{FREE_TEMPLATE_LIMIT} free templates used.{atLimit ? " " : ""}
          {atLimit && <Link href="/settings">Go Premium for unlimited →</Link>}
        </div>
      )}

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

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0, fontSize: 17 }}>Templates</h2>
        {templates.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No templates yet. Create one for things you log often — rent, salary, groceries.</p>
        ) : (
          <div className="list-grid">
            {templates.map((t, i) => (
              <div key={t.id} className="card lift" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6, minWidth: 0 }}>
                  <div style={{ display: "grid" }}>
                    <button className="chip" style={{ padding: "0 6px", fontSize: 11, lineHeight: 1.2, opacity: i === 0 ? 0.3 : 1 }} disabled={i === 0} onClick={() => void move(i, -1)} aria-label="Move up">▲</button>
                    <button className="chip" style={{ padding: "0 6px", fontSize: 11, lineHeight: 1.2, opacity: i === templates.length - 1 ? 0.3 : 1 }} disabled={i === templates.length - 1} onClick={() => void move(i, 1)} aria-label="Move down">▼</button>
                  </div>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.name}</div>
                    <div className="muted" style={{ fontSize: 12 }}>{t.type}{t.amount != null ? ` · ${fmt(money(t.amount, t.currency ?? base))}` : ""}{t.split_group_id ? " · split" : ""}</div>
                  </div>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                  <Link href={`/transactions/new?template=${t.id}`} className="chip">Use</Link>
                  <KebabMenu label={`${t.name} actions`} items={[
                    { label: "Edit", onClick: () => openEdit(t) },
                    { label: "Delete", danger: true, onClick: async () => { if (await confirm({ title: "Delete this template?", message: `“${t.name}” will be removed.` })) softDelete("transaction_templates", t.id); } },
                  ]} />
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section style={{ display: "grid", gap: 8 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <h2 style={{ margin: 0, fontSize: 17 }}>Recurring</h2>
          {templates.length > 0 && <button className="chip" onClick={() => { setRTemplate(templates[0]!.id); setShowR(true); }}>+ Add recurring</button>}
        </div>
        {rules.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No recurring rules. Turn a template into a recurring payment or salary.</p>
        ) : (
          <div className="list-grid">
            {rules.map((r) => (
              <div key={r.id} className="card lift" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{r.template_name}</div>
                  <div className="muted" style={{ fontSize: 12 }}>{every(r.frequency, r.interval_count)} · next {r.next_due} · {r.auto_post ? "auto" : "confirm"}</div>
                </div>
                <KebabMenu label={`${r.template_name} recurring actions`} items={[
                  { label: "Post now", onClick: () => void postRuleOnce(r.id) },
                  { label: "Delete", danger: true, onClick: async () => { if (await confirm({ title: "Delete this recurring rule?", message: `The schedule for “${r.template_name}” will be removed.` })) softDelete("recurring_rules", r.id); } },
                ]} />
              </div>
            ))}
          </div>
        )}
      </section>

      <Modal open={showT} onClose={() => setShowT(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{editTpl ? "Edit template" : "New template"}</h2>
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
            <button className="btn" onClick={() => void submitTemplate()} disabled={busy || !tName.trim()}>{editTpl ? "Save" : "Create"}</button>
          </div>
        </div>
      </Modal>

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

      <UpgradeModal open={showUpgrade} onClose={() => setShowUpgrade(false)} title="Template limit reached"
        message={`Free plans can keep up to ${FREE_TEMPLATE_LIMIT} templates. Upgrade to Premium for unlimited templates.`} />
    </div>
  );
}
