"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { fromMajor, sum, format, money, type Money } from "@pocketcare/money";
import type { Account } from "@pocketcare/types";
import { getRepositories } from "../../../src/powersync";
import { LabelPicker } from "../../../src/ui/LabelPicker";
import { SearchSelect } from "../../../src/ui/SearchSelect";
import { AccountBadge } from "../../../src/ui/AccountBadge";
import { useGroups, useUserProfiles, useMyUserId } from "../../../src/splits/hooks";
import { createSplitExpense, type SplitMode } from "../../../src/splits/write";
import { splitEqual, splitByWeights } from "../../../src/splits/math";
import { useTemplates, type Template } from "../../../src/templates/hooks";
import { createTemplate, FREE_TEMPLATE_LIMIT } from "../../../src/templates/write";
import { useEntitlement } from "../../../src/entitlement";
import { UpgradeModal } from "../../../src/ui/UpgradeModal";
import { useAutoCategorize, useLearnCategory } from "../../../src/categorize/hooks";

type TxType = "expense" | "income" | "transfer";
let counter = 0;
const newItem = () => ({ id: `i${++counter}`, description: "", value: "" });

interface PayMethod { id: string; label: string }

export default function NewTransactionPage() {
  const router = useRouter();
  const { data: accounts = [] } = useQuery<Account>(
    "SELECT * FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived, 0) = 0 AND IFNULL(kind,'real') = 'real' ORDER BY created_at",
  );
  const { data: categories = [] } = useQuery<{ id: string; name: string; kind: string; parent_id: string | null }>(
    "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name",
  );
  const { data: labelList = [] } = useQuery<{ id: string; name: string; color: string | null }>(
    "SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name",
  );
  const { data: payMethodMap = [] } = useQuery<PayMethod & { account_type_id: string }>(
    `SELECT pm.id, pm.label, m.account_type_id
     FROM account_type_payment_methods m JOIN payment_methods pm ON pm.id = m.payment_method_id
     ORDER BY pm.sort`,
  );

  const [type, setType] = useState<TxType>("expense");
  const [accountId, setAccountId] = useState<string | null>(null);
  const [toAccountId, setToAccountId] = useState<string | null>(null);
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [selectedLabels, setSelectedLabels] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("");
  const [items, setItems] = useState([newItem()]);
  const [toValue, setToValue] = useState(""); // cross-currency destination amount
  const [date, setDate] = useState(new Date().toLocaleString("sv-SE", { timeZoneName: "short" }).substring(0, 16)); // YYYY-MM-DDTHH:mm
  const [saving, setSaving] = useState(false);

  // Split (multi-user: participants are members of a chosen group).
  const groups = useGroups();
  const profiles = useUserProfiles();
  const me = useMyUserId();
  const { data: groupMembers = [] } = useQuery<{ group_id: string; user_id: string }>(
    "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL",
  );
  const [splitGroupId, setSplitGroupId] = useState("");
  const [splitOn, setSplitOn] = useState(false);
  const [splitTouched, setSplitTouched] = useState(false);
  const [splitMode, setSplitMode] = useState<SplitMode>("equal");
  const [splitMembers, setSplitMembers] = useState<string[]>([]); // user ids in this expense
  const [shareVals, setShareVals] = useState<Record<string, string>>({});
  const [multiPayer, setMultiPayer] = useState(false);
  const [paidVals, setPaidVals] = useState<Record<string, string>>({});
  const membersOf = (gid: string) => groupMembers.filter((m) => m.group_id === gid).map((m) => m.user_id);
  const memberName = (uid: string) => (uid === me ? "You" : profiles.get(uid)?.name ?? "Someone");
  const splitActive = type === "expense" && splitOn && !!splitGroupId && splitMembers.length >= 2;

  // Auto-split: date inside an auto-split trip/group → preselect it.
  const autoGroup = useMemo(
    () => groups.find((g) => g.auto_split === 1 && g.start_date && date.slice(0, 10) >= g.start_date && date.slice(0, 10) <= (g.end_date ?? "9999-12-31")),
    [groups, date],
  );
  useEffect(() => {
    if (type === "expense" && autoGroup && !splitTouched && splitGroupId !== autoGroup.id) {
      setSplitOn(true);
      setSplitGroupId(autoGroup.id);
      setSplitMembers(groupMembers.filter((m) => m.group_id === autoGroup.id).map((m) => m.user_id));
      setSplitMode("equal");
    }
  }, [autoGroup, type, splitTouched, splitGroupId, groupMembers]);

  // Templates (Quick Apply).
  const templates = useTemplates();
  const { isPaid } = useEntitlement();
  const tplAppliedRef = useRef(false);
  const [tplSaved, setTplSaved] = useState(false);
  const [showUpgrade, setShowUpgrade] = useState(false);

  const combinedDescriptionText = useMemo(() => {
    return type === "transfer" ? "" : items.map(it => it.description.trim()).filter(Boolean).join(", ");
  }, [type, items]);
  const autoCategorizeText = [combinedDescriptionText, note.trim()].filter(Boolean).join(" ");

  // Auto-categorization
  const [manualCategory, setManualCategory] = useState(false);
  const { suggestedCategory, isAutoApplied, setIsAutoApplied } = useAutoCategorize(
    autoCategorizeText,
    categories,
    isPaid && type !== "transfer"
  );
  const learnCategory = useLearnCategory();

  // Auto-apply if not manually set
  useEffect(() => {
    if (suggestedCategory && !manualCategory && categoryId !== suggestedCategory) {
      setCategoryId(suggestedCategory);
      setIsAutoApplied(true);
    }
  }, [suggestedCategory, manualCategory, categoryId, setIsAutoApplied]);

  function applyTemplate(t: Template) {
    setType(t.type === "income" ? "income" : t.type === "transfer" ? "transfer" : "expense");
    setItems([{ id: `i${++counter}`, description: t.description ?? "", value: t.amount != null ? String(t.amount / 100) : "" }]);
    if (t.account_id) setAccountId(t.account_id);
    setCategoryId(t.category_id ?? null);
    setManualCategory(true);
    setNote(t.note ?? "");
    if (t.payment_method) setPaymentMethod(t.payment_method);
    setSelectedLabels(t.labels ? t.labels.split(",").map((s) => s.trim()).filter(Boolean) : []);
    if (t.split_group_id) { setSplitTouched(true); setSplitOn(true); setSplitGroupId(t.split_group_id); setSplitMembers(membersOf(t.split_group_id)); setSplitMode((t.split_mode as SplitMode) || "equal"); }
    setTplSaved(false);
  }

  // One-time prefill from ?template=ID (deep link / "Use" button).
  useEffect(() => {
    if (tplAppliedRef.current) return;
    const id = typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("template") : null;
    if (!id) return;
    const t = templates.find((x) => x.id === id);
    if (!t) return;
    tplAppliedRef.current = true;
    applyTemplate(t);
  }, [templates]);

  const occurredAtIso = () => new Date(date).toISOString();

  const account = accounts.find((a) => a.id === accountId) ?? accounts[0];
  const currency = account?.currency ?? "USD";
  const toAccount = accounts.find((a) => a.id === toAccountId) ?? accounts.find((a) => a.id !== account?.id);
  const crossCurrency = type === "transfer" && toAccount && toAccount.currency !== currency;

  // Investment accounts (stocks / mutual funds) can only move money via transfers.
  const isInvestment = account?.type === "stocks" || account?.type === "mutual_funds";
  useEffect(() => {
    if (isInvestment && type !== "transfer") setType("transfer");
  }, [isInvestment, type]);

  // Payment methods depend on the account type (from the lookup mapping table).
  const paymentMethods: PayMethod[] = useMemo(
    () => payMethodMap.filter((m) => m.account_type_id === account?.type),
    [payMethodMap, account?.type],
  );
  useEffect(() => {
    setPaymentMethod(paymentMethods[0]?.id ?? "");
  }, [account?.id, account?.type, paymentMethods.length]);

  const itemMoneys: Money[] = useMemo(
    () => items.map((it) => fromMajor(Number.parseFloat(it.value) || 0, currency)),
    [items, currency],
  );
  const total = useMemo(() => sum(itemMoneys, currency), [itemMoneys, currency]);

  // Assemble + validate the split from the editor state (single source of truth).
  const splitPlan = useMemo(() => {
    const partKeys = splitMembers; // user ids
    const n = partKeys.length;
    const toMinor = (v?: string) => Math.round((Number(v) || 0) * 100);
    let shares: number[];
    if (splitMode === "percent") shares = splitByWeights(total.amount, partKeys.map((k) => Number(shareVals[k] || 0)));
    else if (splitMode === "exact") shares = partKeys.map((k) => toMinor(shareVals[k]));
    else shares = splitEqual(total.amount, n);
    const sharesSum = shares.reduce((a, b) => a + b, 0);
    const pctSum = partKeys.reduce((a, k) => a + (Number(shareVals[k]) || 0), 0);
    const payerList = multiPayer
      ? partKeys.map((k) => ({ key: k, paid: toMinor(paidVals[k]) }))
      : [{ key: me, paid: total.amount }];
    const paidSum = payerList.reduce((a, p) => a + p.paid, 0);
    const myPaid = payerList.filter((p) => p.key === me).reduce((a, p) => a + p.paid, 0);
    const needAccount = myPaid > 0;
    const valid =
      !!splitGroupId && n >= 2 && total.amount > 0 && partKeys.includes(me) &&
      (splitMode === "equal" || (splitMode === "exact" ? sharesSum === total.amount : Math.round(pctSum) === 100)) &&
      (!multiPayer || paidSum === total.amount) &&
      (!needAccount || !!account);
    const input = {
      groupId: splitGroupId,
      mode: splitMode,
      participants: partKeys.map((k) => ({
        userId: k,
        value: splitMode === "percent" ? Number(shareVals[k] || 0) : splitMode === "exact" ? toMinor(shareVals[k]) : undefined,
      })),
      payers: payerList.filter((p) => p.paid > 0).map((p) => ({
        userId: p.key, paid: p.paid, accountId: p.key === me ? account?.id ?? null : null,
      })),
    };
    return { partKeys, shares, sharesSum, pctSum, paidSum, valid, input };
  }, [splitMode, splitMembers, shareVals, multiPayer, paidVals, total, account?.id, splitGroupId, me]);
  const relevantCats = categories.filter((c) => (type === "income" ? c.kind === "income" : c.kind === "expense"));
  const categoryOptions = useMemo(() => {
    const opts: { value: string; label: string; search: string }[] = [];
    for (const p of relevantCats.filter((c) => !c.parent_id)) {
      opts.push({ value: p.id, label: p.name, search: p.name });
      for (const ch of relevantCats.filter((c) => c.parent_id === p.id)) {
        opts.push({ value: ch.id, label: `${p.name} › ${ch.name}`, search: `${p.name} ${ch.name}` });
      }
    }
    return opts;
  }, [relevantCats]);

  const update = (id: string, patch: Partial<(typeof items)[number]>) =>
    setItems((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it)));

  const canSave =
    !!account && total.amount > 0 && !saving && (type !== "transfer" || (!!toAccount && toAccount.id !== account.id))
    && (!splitActive || splitPlan.valid);

  async function save() {
    if (!account || !canSave) return;
    setSaving(true);
    try {
      const repos = getRepositories();
      const combinedDescription = type === "transfer"
        ? null
        : items.map(it => it.description.trim()).filter(Boolean).join(", ");

      // Split path: book only your share; lend/borrow the rest via virtual accounts.
      if (splitActive && splitPlan.valid) {
        await createSplitExpense({
          ...splitPlan.input,
          total,
          categoryId,
          description: combinedDescription || null,
          note: note.trim() || null,
          occurredAt: occurredAtIso(),
        });
        router.push("/transactions");
        return;
      }

      if (type === "transfer" && toAccount) {
        await repos.transactions.create({
          account_id: account.id,
          type: "transfer",
          amount: total,
          to_account_id: toAccount.id,
          to_amount: crossCurrency ? fromMajor(Number.parseFloat(toValue) || 0, toAccount.currency) : null,
          labels: selectedLabels,
          note: note.trim() || null,
          occurred_at: occurredAtIso(),
        });
      } else {
        const payload = items
          .filter((it) => Number.parseFloat(it.value) > 0)
          .map((it, i) => ({
            description: it.description.trim() || `Item ${i + 1}`,
            amount: fromMajor(Number.parseFloat(it.value) || 0, currency),
          }));
        await repos.transactions.create({
          account_id: account.id,
          type,
          amount: total,
          category_id: categoryId,
          labels: selectedLabels,
          note: note.trim() || null,
          description: combinedDescription || null,
          payment_method: paymentMethod || null,
          occurred_at: occurredAtIso(),
          items: payload.length > 1 ? payload : undefined,
        });
      }

      if (type !== "transfer" && autoCategorizeText && isPaid) {
        // Fire and forget learning
        void learnCategory(autoCategorizeText, categoryId, isAutoApplied ? suggestedCategory : null);
      }

      router.push("/transactions");
    } finally {
      setSaving(false);
    }
  }

  if (accounts.length === 0) {
    return (
      <div className="fade-up">
        <h1>Add transaction</h1>
        <p className="muted">Create an account first.</p>
        <a href="/accounts/new" className="btn" style={{ marginTop: 12 }}>＋ New account</a>
      </div>
    );
  }

  const accentFor: Record<TxType, string> = { expense: "var(--negative)", income: "var(--positive)", transfer: "var(--forest)" };

  return (
    <div style={{ maxWidth: 620, display: "grid", gap: 16 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Add transaction</h1>
        {templates.length > 0 && (
          <select className="input" style={{ maxWidth: 220 }} value="" onChange={(e) => { const t = templates.find((x) => x.id === e.target.value); if (t) applyTemplate(t); }}>
            <option value="">Start from a template…</option>
            {templates.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        )}
      </div>

      <div style={{ display: "flex", gap: 8 }}>
        {(["expense", "income", "transfer"] as TxType[]).map((tp) => {
          const blocked = isInvestment && tp !== "transfer";
          return (
            <button key={tp} className="chip" data-active={tp === type} disabled={blocked}
              title={blocked ? "Investment accounts can only transfer to/from other accounts" : undefined}
              style={{ flex: 1, textTransform: "capitalize", opacity: blocked ? 0.4 : 1 }}
              onClick={() => !blocked && setType(tp)}>
              {tp}
            </button>
          );
        })}
      </div>
      {isInvestment && (
        <p className="muted" style={{ fontSize: 12, marginTop: -8 }}>Investment accounts only support transfers to and from other accounts.</p>
      )}

      <div className="card" style={{ padding: 22, display: "grid", gap: 14 }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>Amount{items.length > 1 ? " · sum of items" : ""}</div>
          <div style={{ fontSize: 40, fontWeight: 750, color: accentFor[type], letterSpacing: "-0.02em" }}>{format(total, "en-US")}</div>
        </div>

        {type === "transfer" ? (
          <input className="input" inputMode="decimal" placeholder="0.00" autoFocus
            value={items[0]?.value ?? ""}
            onChange={(e) => setItems([{ ...(items[0] ?? newItem()), value: e.target.value.replace(/[^0-9.]/g, "") }])}
            style={{ fontSize: 20, textAlign: "right" }} />
        ) : (
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it, idx) => (
              <div key={it.id} style={{ display: "flex", gap: 8 }}>
                <input className="input" placeholder={items.length > 1 ? `Item ${idx + 1}` : "What for? (optional)"} value={it.description}
                  onChange={(e) => update(it.id, { description: e.target.value })} />
                <input className="input" style={{ width: 140, textAlign: "right", fontWeight: 600 }} inputMode="decimal" placeholder="0.00"
                  autoFocus={idx === 0} value={it.value}
                  onChange={(e) => update(it.id, { value: e.target.value.replace(/[^0-9.]/g, "") })} />
                {items.length > 1 && (
                  <button className="chip" onClick={() => setItems((p) => p.filter((x) => x.id !== it.id))} aria-label="Remove">×</button>
                )}
              </div>
            ))}
            <button className="chip" style={{ borderStyle: "dashed", color: "var(--accent)", justifySelf: "start" }}
              onClick={() => setItems((p) => [...p, newItem()])}>＋ Add item / split</button>
          </div>
        )}
      </div>

      <Field label={type === "transfer" ? "From account" : "Account"}>
        <div style={chips}>
          {accounts.map((a) => (
            <button key={a.id} className="chip" data-active={a.id === account.id} onClick={() => setAccountId(a.id)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <AccountBadge type={a.type} color={a.color} id={a.id} name={a.name} />
              {a.name} <span className="muted">· {a.currency}</span>
            </button>
          ))}
        </div>
      </Field>

      {type === "transfer" && (
        <Field label="To account">
          <div style={chips}>
            {accounts.filter((a) => a.id !== account.id).map((a) => (
              <button key={a.id} className="chip" data-active={a.id === toAccount?.id} onClick={() => setToAccountId(a.id)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                <AccountBadge type={a.type} color={a.color} id={a.id} name={a.name} />
                {a.name} <span className="muted">· {a.currency}</span>
              </button>
            ))}
          </div>
        </Field>
      )}

      {crossCurrency && (
        <Field label={`Amount received (${toAccount?.currency})`}>
          <input className="input" inputMode="decimal" placeholder="0.00" value={toValue}
            onChange={(e) => setToValue(e.target.value.replace(/[^0-9.]/g, ""))} />
        </Field>
      )}

      {type !== "transfer" && (
        <Field label="Category">
          <div style={{ position: "relative" }}>
            <SearchSelect 
              value={categoryId} 
              onChange={(val) => {
                setCategoryId(val);
                setManualCategory(true);
                setIsAutoApplied(false);
              }} 
              options={categoryOptions} 
              placeholder="Search a category…" 
            />
            {isAutoApplied && (
              <div style={{
                position: "absolute", top: -20, right: 0,
                fontSize: 11, color: "var(--accent)", fontWeight: 600,
                display: "flex", alignItems: "center", gap: 4,
                background: "var(--accent-ghost)", padding: "2px 6px", borderRadius: 4,
                border: "1px solid var(--accent-soft)"
              }}>
                ✦ Auto-categorised
              </div>
            )}
          </div>
        </Field>
      )}

      {type !== "transfer" && paymentMethods.length > 0 && (
        <Field label="Payment method">
          <div style={chips}>
            {paymentMethods.map((m) => (
              <button key={m.id} className="chip" data-active={m.id === paymentMethod} onClick={() => setPaymentMethod(m.id)}>{m.label}</button>
            ))}
          </div>
        </Field>
      )}

      {type === "expense" && (
        <div className="card" style={{ padding: 16, display: "grid", gap: 12 }}>
          <label style={{ display: "flex", justifyContent: "space-between", alignItems: "center", cursor: "pointer" }}>
            <span style={{ fontWeight: 600 }}>Split this expense</span>
            <input type="checkbox" checked={splitOn} onChange={(e) => { setSplitTouched(true); setSplitOn(e.target.checked); }} />
          </label>
          {splitOn && autoGroup && splitGroupId === autoGroup.id && (
            <div style={{ fontSize: 12, color: "var(--accent)", background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", borderRadius: 8, padding: "6px 10px" }}>
              Auto-split with <strong>{autoGroup.name}</strong> (this date is in its range). Turn off to exclude this one.
            </div>
          )}

          {splitOn && (() => {
            const meIdx = splitPlan.partKeys.indexOf(me);
            const myShare = meIdx >= 0 ? splitPlan.shares[meIdx] ?? 0 : 0;
            const myPaid = multiPayer ? Math.round((Number(paidVals[me]) || 0) * 100) : total.amount;
            const net = myPaid - myShare;
            const groupMemberIds = splitGroupId ? membersOf(splitGroupId) : [];
            return (
              <div style={{ display: "grid", gap: 12 }}>
                {/* group / trip (required — participants are its members) */}
                <label style={{ display: "grid", gap: 4 }}>
                  <span className="muted" style={{ fontSize: 12 }}>Group / trip</span>
                  <select className="input" value={splitGroupId} onChange={(e) => {
                    const gid = e.target.value;
                    setSplitTouched(true);
                    setSplitGroupId(gid);
                    setSplitMembers(gid ? membersOf(gid) : []);
                  }}>
                    <option value="">Choose a group…</option>
                    {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
                  </select>
                </label>

                {!splitGroupId ? (
                  <span className="muted" style={{ fontSize: 12 }}>Pick a group. Create one and invite friends from <Link href="/groups">Groups &amp; trips</Link>.</span>
                ) : groupMemberIds.length < 2 ? (
                  <span className="muted" style={{ fontSize: 12 }}>This group has only you so far — invite someone from the group page first.</span>
                ) : (
                  <>
                    {/* mode */}
                    <div style={{ display: "flex", gap: 6 }}>
                      {(["equal", "exact", "percent"] as SplitMode[]).map((m) => (
                        <button key={m} type="button" className="chip" data-active={m === splitMode} onClick={() => setSplitMode(m)}>
                          {m === "equal" ? "Equally" : m === "exact" ? "Exact" : "Percent"}
                        </button>
                      ))}
                    </div>

                    {/* participants (group members) */}
                    <span className="muted" style={{ fontSize: 12 }}>Split between:</span>
                    <div style={chips}>
                      {groupMemberIds.map((uid) => {
                        const on = splitMembers.includes(uid);
                        return (
                          <button key={uid} type="button" className="chip" data-active={on}
                            onClick={() => setSplitMembers((p) => on ? p.filter((x) => x !== uid) : [...p, uid])}>{memberName(uid)}</button>
                        );
                      })}
                    </div>

                    {/* per-participant share inputs (exact / percent) */}
                    {splitMode !== "equal" && splitPlan.partKeys.length > 0 && (
                      <div style={{ display: "grid", gap: 6 }}>
                        {splitPlan.partKeys.map((k, i) => (
                          <div key={k} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
                            <span style={{ fontSize: 14 }}>{memberName(k)}</span>
                            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                              <input className="input" style={{ width: 110, textAlign: "right" }} inputMode="decimal"
                                placeholder={splitMode === "percent" ? "%" : currency}
                                value={shareVals[k] ?? ""} onChange={(e) => setShareVals((p) => ({ ...p, [k]: e.target.value.replace(/[^0-9.]/g, "") }))} />
                              <span className="muted" style={{ fontSize: 12, width: 80, textAlign: "right" }}>{format(money(splitPlan.shares[i] ?? 0, currency), "en-US")}</span>
                            </div>
                          </div>
                        ))}
                        <span className="muted" style={{ fontSize: 12 }}>
                          {splitMode === "exact"
                            ? `Shares total ${format(money(splitPlan.sharesSum, currency), "en-US")} of ${format(total, "en-US")} ${splitPlan.sharesSum === total.amount ? "✓" : "— must match"}`
                            : `Percent total ${Math.round(splitPlan.pctSum)}% ${Math.round(splitPlan.pctSum) === 100 ? "✓" : "— must be 100%"}`}
                        </span>
                      </div>
                    )}

                    {/* payers */}
                    <label style={{ display: "flex", justifyContent: "space-between", alignItems: "center", cursor: "pointer" }}>
                      <span style={{ fontSize: 14 }}>Multiple people paid</span>
                      <input type="checkbox" checked={multiPayer} onChange={(e) => setMultiPayer(e.target.checked)} />
                    </label>
                    {multiPayer ? (
                      <div style={{ display: "grid", gap: 6 }}>
                        {splitPlan.partKeys.map((k) => (
                          <div key={k} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
                            <span style={{ fontSize: 14 }}>{memberName(k)} paid</span>
                            <input className="input" style={{ width: 110, textAlign: "right" }} inputMode="decimal" placeholder={currency}
                              value={paidVals[k] ?? ""} onChange={(e) => setPaidVals((p) => ({ ...p, [k]: e.target.value.replace(/[^0-9.]/g, "") }))} />
                          </div>
                        ))}
                        <span className="muted" style={{ fontSize: 12 }}>
                          Paid total {format(money(splitPlan.paidSum, currency), "en-US")} of {format(total, "en-US")} {splitPlan.paidSum === total.amount ? "✓" : "— must match"}
                        </span>
                        <span className="muted" style={{ fontSize: 11 }}>Only your payment uses {account?.name}; others’ payments just change who owes whom.</span>
                      </div>
                    ) : (
                      <span className="muted" style={{ fontSize: 12 }}>You paid {format(total, "en-US")} from {account?.name}.</span>
                    )}

                    {/* summary */}
                    {splitPlan.valid ? (
                      <div className="card" style={{ padding: 12, background: "var(--surface-2)", display: "grid", gap: 4, fontSize: 13 }}>
                        <div>Your share: <strong>{format(money(myShare, currency), "en-US")}</strong> <span className="muted">(counts in your budget)</span></div>
                        {net > 0 && <div style={{ color: "var(--positive)" }}>Others owe you {format(money(net, currency), "en-US")}</div>}
                        {net < 0 && <div style={{ color: "var(--negative)" }}>You’ll owe {format(money(-net, currency), "en-US")}</div>}
                      </div>
                    ) : (
                      <span className="muted" style={{ fontSize: 12 }}>Pick at least two people and make the totals match.</span>
                    )}
                  </>
                )}
              </div>
            );
          })()}
        </div>
      )}

      <Field label="Labels (optional)">
        <LabelPicker labels={labelList} selected={selectedLabels} onChange={setSelectedLabels} />
      </Field>

      <Field label="Note (optional)">
        <textarea className="input" rows={2} placeholder="Any extra notes?" value={note} onChange={(e) => setNote(e.target.value)} style={{ resize: "vertical" }} />
      </Field>

      <Field label="Date">
        <input className="input" type="datetime-local" value={date} onChange={(e) => setDate(e.target.value)} />
      </Field>

      <button className="btn" disabled={!canSave} onClick={save} style={{ justifyContent: "center", padding: 14 }}>
        {saving ? "Saving…" : `Save · ${format(total, "en-US")}`}
      </button>
      {!!account && total.amount > 0 && (
        <button className="chip" style={{ justifySelf: "center" }} disabled={tplSaved} onClick={() => void saveAsTemplate()}>
          {tplSaved ? "Saved as template ✓" : "Save as template"}
        </button>
      )}

      <UpgradeModal open={showUpgrade} onClose={() => setShowUpgrade(false)} title="Template limit reached"
        message={`Free plans can keep up to ${FREE_TEMPLATE_LIMIT} templates. Upgrade to Premium for unlimited templates.`} />
    </div>
  );

  async function saveAsTemplate() {
    if (!account) return;
    if (!isPaid && templates.length >= FREE_TEMPLATE_LIMIT) { setShowUpgrade(true); return; }
    const guess = items.map((i) => i.description.trim()).filter(Boolean).join(", ") || (type === "income" ? "Income" : type === "transfer" ? "Transfer" : "Expense");
    const name = typeof window !== "undefined" ? window.prompt("Template name", guess) : guess;
    if (!name) return;
    await createTemplate({
      name, type: type === "transfer" ? "transfer" : type,
      amount: total.amount ? total.amount / 100 : null,
      accountId: account.id, toAccountId: type === "transfer" ? (toAccount?.id ?? null) : null,
      categoryId, description: guess === "Income" || guess === "Expense" || guess === "Transfer" ? null : guess,
      note: note.trim() || null, paymentMethod: paymentMethod || null, labels: selectedLabels,
      splitGroupId: splitActive ? splitGroupId : null, splitMode: splitActive ? splitMode : "equal",
    });
    setTplSaved(true);
  }
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label style={{ display: "grid", gap: 8 }}>
      <span className="muted" style={{ fontSize: 13 }}>{label}</span>
      {children}
    </label>
  );
}

const chips: React.CSSProperties = { display: "flex", flexWrap: "wrap", gap: 8 };
