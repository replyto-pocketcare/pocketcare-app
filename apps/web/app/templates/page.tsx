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
import { useTemplates, type Template } from "../../src/templates/hooks";
import { createTemplate, updateTemplate, reorderTemplates, FREE_TEMPLATE_LIMIT } from "../../src/templates/write";

export default function TemplatesPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const { isPaid } = useEntitlement();
  const templates = useTemplates();
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

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Templates</h1>
        <button className="btn" onClick={openNew}>+ New template</button>
      </div>

      {!isPaid && (
        <div className="muted" style={{ fontSize: 12.5 }}>
          {templates.length}/{FREE_TEMPLATE_LIMIT} free templates used.{atLimit ? " " : ""}
          {atLimit && <Link href="/settings">Go Premium for unlimited →</Link>}
        </div>
      )}

      <p className="muted" style={{ fontSize: 12.5, margin: 0 }}>Templates are one-tap shortcuts for transactions you log often. For salary, rent and other automatic schedules, use <Link href="/recurring">Recurring payments &amp; income</Link>.</p>

      <section style={{ display: "grid", gap: 8 }}>
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

      <UpgradeModal open={showUpgrade} onClose={() => setShowUpgrade(false)} title="Template limit reached"
        message={`Free plans can keep up to ${FREE_TEMPLATE_LIMIT} templates. Upgrade to Premium for unlimited templates.`} />
    </div>
  );
}
