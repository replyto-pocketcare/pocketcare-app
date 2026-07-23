"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
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
  const { t } = useTranslation("templates");
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
        <h1 style={{ margin: 0 }}>{t("title")}</h1>
        <button className="btn" onClick={openNew}>+ {t("newTemplate")}</button>
      </div>

      {!isPaid && (
        <div className="muted" style={{ fontSize: 12.5 }}>
          {t("freeUsed", { used: templates.length, limit: FREE_TEMPLATE_LIMIT })}{atLimit ? " " : ""}
          {atLimit && <Link href="/settings">{t("goPremium")}</Link>}
        </div>
      )}

      <p className="muted" style={{ fontSize: 12.5, margin: 0 }}>{t("introPre")}<Link href="/recurring">{t("introLink")}</Link>.</p>

      <section style={{ display: "grid", gap: 8 }}>
        {templates.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>{t("noTemplates")}</p>
        ) : (
          <div className="list-grid">
            {templates.map((tpl, i) => (
              <div key={tpl.id} className="card lift" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, padding: "12px 14px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6, minWidth: 0 }}>
                  <div style={{ display: "grid" }}>
                    <button className="chip" style={{ padding: "0 6px", fontSize: 11, lineHeight: 1.2, opacity: i === 0 ? 0.3 : 1 }} disabled={i === 0} onClick={() => void move(i, -1)} aria-label={t("moveUp")}>▲</button>
                    <button className="chip" style={{ padding: "0 6px", fontSize: 11, lineHeight: 1.2, opacity: i === templates.length - 1 ? 0.3 : 1 }} disabled={i === templates.length - 1} onClick={() => void move(i, 1)} aria-label={t("moveDown")}>▼</button>
                  </div>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{tpl.name}</div>
                    <div className="muted" style={{ fontSize: 12 }}>{t(`type.${tpl.type === "income" ? "income" : "expense"}`)}{tpl.amount != null ? ` · ${fmt(money(tpl.amount, tpl.currency ?? base))}` : ""}{tpl.split_group_id ? ` · ${t("split")}` : ""}</div>
                  </div>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
                  <Link href={`/transactions/new?template=${tpl.id}`} className="chip">{t("use")}</Link>
                  <KebabMenu label={t("actions", { name: tpl.name })} items={[
                    { label: t("edit"), onClick: () => openEdit(tpl) },
                    { label: t("delete"), danger: true, onClick: async () => { if (await confirm({ title: t("deleteTitle"), message: t("deleteMsg", { name: tpl.name }) })) softDelete("transaction_templates", tpl.id); } },
                  ]} />
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <Modal open={showT} onClose={() => setShowT(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{editTpl ? t("editTitle") : t("newTitle")}</h2>
          <input className="input" placeholder={t("namePlaceholder")} value={tName} onChange={(e) => setTName(e.target.value)} />
          <div style={{ display: "flex", gap: 6 }}>
            {(["expense", "income"] as const).map((k) => <button key={k} className="chip" data-active={k === tType} onClick={() => setTType(k)}>{t(`type.${k}`)}</button>)}
          </div>
          <input className="input" inputMode="decimal" placeholder={t("amountPlaceholder", { base })} value={tAmount} onChange={(e) => setTAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>{t("account")}</span>
            <select className="input" value={tAccount} onChange={(e) => setTAccount(e.target.value)}>
              <option value="">{t("chooseAtUse")}</option>
              {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </label>
          <input className="input" placeholder={t("descriptionPlaceholder")} value={tDesc} onChange={(e) => setTDesc(e.target.value)} />
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShowT(false)}>{t("cancel")}</button>
            <button className="btn" onClick={() => void submitTemplate()} disabled={busy || !tName.trim()}>{editTpl ? t("save") : t("create")}</button>
          </div>
        </div>
      </Modal>

      <UpgradeModal open={showUpgrade} onClose={() => setShowUpgrade(false)} title={t("limitTitle")}
        message={t("limitMsg", { limit: FREE_TEMPLATE_LIMIT })} />
    </div>
  );
}
