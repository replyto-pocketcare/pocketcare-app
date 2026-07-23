"use client";

import { useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { updateRow, softDelete } from "../../../src/write";
import { useConfirm } from "../../../src/ui/Confirm";
import { Modal } from "../../../src/ui/Modal";
import { KebabMenu } from "../../../src/ui/KebabMenu";
import { useGroup, useGroupExpenses, useGroupBalances, useGroupMemberIds, useUserProfiles, useConnections } from "../../../src/splits/hooks";
import { createInvite } from "../../../src/splits/write";

interface Invitee { id: string | null; name: string; email: string }
const looksLikeEmail = (s: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s.trim());

export default function GroupDetailPage() {
  const { t } = useTranslation("groups");
  const params = useParams<{ id: string }>();
  const id = params.id;
  const router = useRouter();
  const base = useBaseCurrency();
  const confirm = useConfirm();
  const fmt = useMoneyFmt();
  const group = useGroup(id);
  const expenses = useGroupExpenses(id);
  const balances = useGroupBalances(id);
  const memberIds = useGroupMemberIds(id);
  const profiles = useUserProfiles();

  const name = (uid: string) => profiles.get(uid)?.name ?? t("someone");
  const total = expenses.reduce((s, e) => s + e.amount, 0);
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);

  const [inviteOpen, setInviteOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [eName, setEName] = useState("");
  const [eStart, setEStart] = useState("");
  const [eEnd, setEEnd] = useState("");
  const [eAuto, setEAuto] = useState(false);
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [inviteMsg, setInviteMsg] = useState<string | null>(null);
  const [inviting, setInviting] = useState(false);
  const [copied, setCopied] = useState(false);
  // Multi-select invite (search connections + typed emails → chips).
  const connections = useConnections();
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<Invitee[]>([]);
  const selectedKey = (i: Invitee) => i.id ?? i.email.toLowerCase();
  const isPicked = (i: Invitee) => selected.some((s) => selectedKey(s) === selectedKey(i));
  const suggestions = connections
    .filter((c) => !!c.email && !memberIds.includes(c.id) && !isPicked({ id: c.id, name: c.name, email: c.email! }))
    .filter((c) => { const q = query.trim().toLowerCase(); return !q || c.name.toLowerCase().includes(q) || (c.email ?? "").toLowerCase().includes(q); })
    .slice(0, 6);
  const canAddTypedEmail = looksLikeEmail(query) &&
    !connections.some((c) => (c.email ?? "").toLowerCase() === query.trim().toLowerCase()) &&
    !selected.some((s) => s.email.toLowerCase() === query.trim().toLowerCase());
  const addInvitee = (i: Invitee) => { setSelected((prev) => [...prev, i]); setQuery(""); };
  const removeInvitee = (key: string) => setSelected((prev) => prev.filter((s) => selectedKey(s) !== key));

  function openEdit() {
    if (!group) return;
    setEName(group.name); setEStart(group.start_date ?? ""); setEEnd(group.end_date ?? ""); setEAuto(group.auto_split === 1);
    setEditOpen(true);
  }
  async function saveEdit() {
    if (!group || !eName.trim()) return;
    await updateRow("split_groups", group.id, {
      name: eName.trim(), start_date: eStart || null, end_date: eEnd || null,
      auto_split: eStart && eEnd && eAuto ? 1 : 0,
    });
    setEditOpen(false);
  }
  async function deleteGroup() {
    if (!group) return;
    if (!(await confirm({ title: t("deleteTitle"), message: t("deleteMsg", { name: group.name }) }))) return;
    await softDelete("split_groups", group.id);
    router.replace("/groups");
  }

  /** Invite everyone currently in the chips (connections + typed emails). */
  async function inviteSelected() {
    if (selected.length === 0) return;
    setInviting(true); setInviteMsg(null); setInviteLink(null);
    let added = 0, links = 0; const failed: string[] = [];
    for (const p of selected) {
      try {
        const r = await createInvite(id, p.email || undefined);
        if (r.added) added++; else links++;
      } catch { failed.push(p.name || p.email); }
    }
    setInviting(false);
    setSelected([]); setQuery("");
    const parts: string[] = [];
    if (added) parts.push(t("invitedAdded", { count: added, defaultValue: "{{count}} added" }));
    if (links) parts.push(t("invitedLinks", { count: links, defaultValue: "{{count}} invite link(s) created" }));
    if (failed.length) parts.push(t("invitedFailed", { names: failed.join(", "), defaultValue: "Failed: {{names}}" }));
    setInviteMsg(parts.join(" · ") || null);
  }

  /** Generate a general share link (no specific recipient). */
  async function shareLink() {
    setInviting(true); setInviteMsg(null); setInviteLink(null);
    try {
      const r = await createInvite(id, undefined);
      setInviteLink(r.link ?? null); setCopied(false);
    } catch (e) { setInviteMsg(t("error", { msg: (e as Error).message })); }
    finally { setInviting(false); }
  }

  if (!group) return <div className="fade-up"><p className="muted">{t("groupNotFound")}<Link href="/groups">{t("backToGroupsLink")}</Link></p></div>;

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <Link href="/groups" className="muted" style={{ fontSize: 13 }}>{t("backToGroups")}</Link>
          <h1 style={{ margin: "6px 0 0" }}>{group.name} <span className="muted" style={{ fontSize: 14 }}>· {t(`kind.${group.kind}`, group.kind)}</span></h1>
          <div className="muted" style={{ fontSize: 13, display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginTop: 2 }}>
            {group.start_date ? <span>📅 {group.start_date}{group.end_date ? ` – ${group.end_date}` : ""}</span> : <span>{t("noDates")}</span>}
            <span>· {t("members", { count: memberIds.length })}</span>
            {group.auto_split === 1 && <span style={{ color: "var(--accent)" }}>· {t("autoSplitOn")}</span>}
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Link href={`/transactions/new?split=${group.id}`} className="btn">+ {t("addExpense", "Add expense")}</Link>
          <button className="btn ghost" onClick={() => { setInviteOpen(true); setInviteLink(null); setInviteMsg(null); }}>+ {t("invite")}</button>
          <KebabMenu label={t("groupActions")} items={[
            { label: t("edit"), onClick: openEdit },
            { label: t("delete"), danger: true, onClick: () => void deleteGroup() },
          ]} />
        </div>
      </div>

      <section className="card" style={{ padding: 20, display: "flex", gap: 24, flexWrap: "wrap" }}>
        <div><div className="muted" style={{ fontSize: 13 }}>{t("totalSpent")}</div><div style={{ fontSize: 26, fontWeight: 750 }}>{fmt(money(total, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>{t("youreOwed")}</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--positive)" }}>{fmt(money(owed, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>{t("youOwe")}</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(owe, base))}</div></div>
      </section>

      {group.start_date && group.end_date && (
        <label className="card" style={{ padding: 14, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, cursor: "pointer" }}>
          <span style={{ fontSize: 14 }}><strong>{t("autoSplitLabel")}</strong><span className="muted">{t("autoSplitDesc", { start: group.start_date, end: group.end_date, kind: t(`kind.${group.kind}`) })}</span></span>
          <input type="checkbox" checked={group.auto_split === 1} onChange={(e) => void updateRow("split_groups", group.id, { auto_split: e.target.checked ? 1 : 0 })} />
        </label>
      )}

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>{t("membersTitle")}</h2>
        <div className="card" style={{ padding: 8 }}>
          {memberIds.map((uid) => (
            <div key={uid} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14 }}>
              <span>{name(uid)}</span>
              <span style={{ color: (balances.find((b) => b.userId === uid)?.net ?? 0) > 0 ? "var(--positive)" : (balances.find((b) => b.userId === uid)?.net ?? 0) < 0 ? "var(--negative)" : "var(--text-2)" }}>
                {(() => { const n = balances.find((b) => b.userId === uid)?.net ?? 0; return n > 0 ? t("owesYouAmt", { amount: fmt(money(n, base)) }) : n < 0 ? t("youOweAmt", { amount: fmt(money(-n, base)) }) : t("settledTag"); })()}
              </span>
            </div>
          ))}
        </div>
      </section>

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>{t("expensesTitle")}</h2>
        {expenses.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>{t("noExpensesPre")}<Link href={`/transactions/new?split=${group.id}`}>{t("noExpensesLink")}</Link>{t("noExpensesPost", { kind: t(`kind.${group.kind}`) })}</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {expenses.map((e) => (
              <div key={e.id} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14, gap: 8 }}>
                <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{e.description || t("expenseFallback")} <span className="muted" style={{ fontSize: 12 }}>· {new Date(e.occurred_at).toLocaleDateString()}</span></span>
                <span style={{ flexShrink: 0, fontWeight: 600 }}>{fmt(money(e.amount, base))}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      <Modal open={editOpen} onClose={() => setEditOpen(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{t("editKind", { kind: t(`kind.${group.kind}`) })}</h2>
          <input className="input" placeholder={t("namePlaceholder")} value={eName} onChange={(e) => setEName(e.target.value)} />
          <span className="muted" style={{ fontSize: 12 }}>{t("datesOptional")}</span>
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input" type="date" value={eStart} onChange={(e) => { setEStart(e.target.value); if (eEnd && e.target.value > eEnd) setEEnd(e.target.value); }} />
            <input className="input" type="date" min={eStart || undefined} value={eEnd} onChange={(e) => setEEnd(e.target.value)} />
          </div>
          <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14, opacity: eStart && eEnd ? 1 : 0.5 }}>
            <input type="checkbox" checked={!!eStart && !!eEnd && eAuto} disabled={!eStart || !eEnd} onChange={(e) => setEAuto(e.target.checked)} />
            {t("autoSplitDates")}
          </label>
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setEditOpen(false)}>{t("cancel")}</button>
            <button className="btn" onClick={() => void saveEdit()} disabled={!eName.trim()}>{t("save")}</button>
          </div>
        </div>
      </Modal>

      <Modal open={inviteOpen} onClose={() => setInviteOpen(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>{t("inviteTo", { name: group.name })}</h2>
          <p className="muted" style={{ margin: 0, fontSize: 13 }}>{t("inviteBody")}</p>

          {/* Selected people as chips */}
          {selected.length > 0 && (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {selected.map((s) => (
                <span key={selectedKey(s)} style={{ display: "inline-flex", alignItems: "center", gap: 6, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", borderRadius: 999, padding: "3px 6px 3px 10px", fontSize: 13 }}>
                  {s.name || s.email}
                  <button aria-label={t("remove", "Remove")} onClick={() => removeInvitee(selectedKey(s))}
                    style={{ border: "none", background: "var(--surface-2)", borderRadius: 999, width: 18, height: 18, cursor: "pointer", color: "var(--text-2)", lineHeight: 1 }}>×</button>
                </span>
              ))}
            </div>
          )}

          {/* Search box + suggestions dropdown */}
          <div style={{ position: "relative" }}>
            <input className="input" placeholder={t("invitePlaceholder", "Search people or type an email")} value={query} onChange={(e) => setQuery(e.target.value)} />
            {(suggestions.length > 0 || canAddTypedEmail) && (
              <div className="card" style={{ marginTop: 6, padding: 4, display: "grid", gap: 2, maxHeight: 220, overflowY: "auto" }}>
                {suggestions.map((c) => (
                  <button key={c.id} className="tap-row" onClick={() => addInvitee({ id: c.id, name: c.name, email: c.email! })}
                    style={{ display: "flex", justifyContent: "space-between", gap: 8, padding: "8px 10px", borderRadius: 8, background: "transparent", border: "none", cursor: "pointer", textAlign: "left", color: "inherit" }}>
                    <span style={{ fontWeight: 500 }}>{c.name}</span>
                    <span className="muted" style={{ fontSize: 12, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.email}</span>
                  </button>
                ))}
                {canAddTypedEmail && (
                  <button className="tap-row" onClick={() => addInvitee({ id: null, name: query.trim(), email: query.trim() })}
                    style={{ display: "flex", gap: 8, padding: "8px 10px", borderRadius: 8, background: "transparent", border: "none", cursor: "pointer", textAlign: "left", color: "var(--accent)" }}>
                    {t("inviteAddEmail", { email: query.trim(), defaultValue: "Invite {{email}}" })}
                  </button>
                )}
              </div>
            )}
          </div>

          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <button className="btn" onClick={() => void inviteSelected()} disabled={inviting || selected.length === 0}>
              {inviting ? "…" : t("inviteCount", { count: selected.length, defaultValue: selected.length ? "Invite {{count}}" : "Invite" })}
            </button>
            <button className="chip" onClick={() => void shareLink()} disabled={inviting}>{t("orShareLink")}</button>
          </div>
          {inviteMsg && <div className="card" style={{ padding: 10, fontSize: 13, background: "var(--surface-2)" }}>{inviteMsg}</div>}
          {inviteLink && (
            <div style={{ display: "grid", gap: 6 }}>
              <input className="input" readOnly value={inviteLink} onFocus={(e) => e.currentTarget.select()} />
              <button className="btn" style={{ justifySelf: "end" }} onClick={async () => { try { await navigator.clipboard.writeText(inviteLink); setCopied(true); } catch { /* ignore */ } }}>{copied ? t("copied") : t("copyLink")}</button>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}
