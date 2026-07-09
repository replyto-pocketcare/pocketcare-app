"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { fromMajor, sum, format, money, type Money } from "@pocketcare/money";
import type { Account } from "@pocketcare/types";
import { getRepositories } from "../../../src/powersync";
import { LabelPicker } from "../../../src/ui/LabelPicker";
import { SearchSelect } from "../../../src/ui/SearchSelect";
import { AccountBadge } from "../../../src/ui/AccountBadge";
import { useContacts, useGroups } from "../../../src/splits/hooks";
import { addContact, createSplitExpense, type SplitMode } from "../../../src/splits/write";
import { splitEqual, splitByWeights } from "../../../src/splits/math";

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

  // Split.
  const contacts = useContacts();
  const groups = useGroups();
  const { data: groupMembers = [] } = useQuery<{ group_id: string; contact_id: string }>(
    "SELECT group_id, contact_id FROM split_group_members WHERE deleted_at IS NULL AND contact_id IS NOT NULL",
  );
  const [splitGroupId, setSplitGroupId] = useState("");
  const [splitOn, setSplitOn] = useState(false);
  const [splitMode, setSplitMode] = useState<SplitMode>("equal");
  const [includeSelf, setIncludeSelf] = useState(true);
  const [splitWith, setSplitWith] = useState<string[]>([]);
  const [shareVals, setShareVals] = useState<Record<string, string>>({});
  const [multiPayer, setMultiPayer] = useState(false);
  const [paidVals, setPaidVals] = useState<Record<string, string>>({});
  const [newContact, setNewContact] = useState("");
  const splitActive = type === "expense" && splitOn && splitWith.length > 0;

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
    const partKeys = [...(includeSelf ? ["self"] : []), ...splitWith];
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
      : [{ key: "self", paid: total.amount }];
    const paidSum = payerList.reduce((a, p) => a + p.paid, 0);
    const selfPaid = payerList.filter((p) => p.key === "self").reduce((a, p) => a + p.paid, 0);
    const needAccount = selfPaid > 0;
    const valid =
      splitWith.length > 0 && n >= 1 && total.amount > 0 &&
      (splitMode === "equal" || (splitMode === "exact" ? sharesSum === total.amount : Math.round(pctSum) === 100)) &&
      (!multiPayer || paidSum === total.amount) &&
      (!needAccount || !!account);
    const input = {
      mode: splitMode,
      participants: partKeys.map((k) => ({
        contactId: k === "self" ? null : k,
        value: splitMode === "percent" ? Number(shareVals[k] || 0) : splitMode === "exact" ? toMinor(shareVals[k]) : undefined,
      })),
      payers: payerList.filter((p) => p.paid > 0).map((p) => ({
        contactId: p.key === "self" ? null : p.key, paid: p.paid, accountId: p.key === "self" ? account?.id ?? null : null,
      })),
    };
    return { partKeys, shares, sharesSum, pctSum, paidSum, valid, input };
  }, [splitMode, includeSelf, splitWith, shareVals, multiPayer, paidVals, total, account?.id]);
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

  async function handleAddContact() {
    const name = newContact.trim();
    if (!name) return;
    const id = await addContact(name);
    setSplitWith((p) => [...p, id]);
    setNewContact("");
  }

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
          groupId: splitGroupId || null,
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
      <h1>Add transaction</h1>

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
          <SearchSelect value={categoryId} onChange={setCategoryId} options={categoryOptions} placeholder="Search a category…" />
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
            <input type="checkbox" checked={splitOn} onChange={(e) => setSplitOn(e.target.checked)} />
          </label>

          {splitOn && (() => {
            const partLabel = (k: string) => (k === "self" ? "You" : contacts.find((c) => c.id === k)?.name ?? "?");
            const selfIdx = splitPlan.partKeys.indexOf("self");
            const selfShare = selfIdx >= 0 ? splitPlan.shares[selfIdx] ?? 0 : 0;
            const selfPaid = multiPayer ? Math.round((Number(paidVals["self"]) || 0) * 100) : total.amount;
            const net = selfPaid - selfShare;
            return (
              <div style={{ display: "grid", gap: 12 }}>
                {/* group / trip */}
                {groups.length > 0 && (
                  <label style={{ display: "grid", gap: 4 }}>
                    <span className="muted" style={{ fontSize: 12 }}>Add to a group / trip (optional)</span>
                    <select className="input" value={splitGroupId} onChange={(e) => {
                      const gid = e.target.value;
                      setSplitGroupId(gid);
                      if (gid) {
                        setSplitWith(groupMembers.filter((m) => m.group_id === gid).map((m) => m.contact_id));
                        setIncludeSelf(true);
                      }
                    }}>
                      <option value="">Not in a group</option>
                      {groups.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
                    </select>
                  </label>
                )}

                {/* mode */}
                <div style={{ display: "flex", gap: 6 }}>
                  {(["equal", "exact", "percent"] as SplitMode[]).map((m) => (
                    <button key={m} type="button" className="chip" data-active={m === splitMode} onClick={() => setSplitMode(m)}>
                      {m === "equal" ? "Equally" : m === "exact" ? "Exact" : "Percent"}
                    </button>
                  ))}
                </div>

                {/* participants */}
                <span className="muted" style={{ fontSize: 12 }}>Split between:</span>
                <div style={chips}>
                  <button type="button" className="chip" data-active={includeSelf} onClick={() => setIncludeSelf((v) => !v)}>You</button>
                  {contacts.map((c) => {
                    const on = splitWith.includes(c.id);
                    return (
                      <button key={c.id} type="button" className="chip" data-active={on}
                        onClick={() => setSplitWith((p) => on ? p.filter((x) => x !== c.id) : [...p, c.id])}>{c.name}</button>
                    );
                  })}
                </div>
                <div style={{ display: "flex", gap: 8 }}>
                  <input className="input" placeholder="Add a person…" value={newContact}
                    onChange={(e) => setNewContact(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void handleAddContact(); } }} />
                  <button type="button" className="chip" onClick={() => void handleAddContact()} disabled={!newContact.trim()}>Add</button>
                </div>

                {/* per-participant share inputs (exact / percent) */}
                {splitMode !== "equal" && splitPlan.partKeys.length > 0 && (
                  <div style={{ display: "grid", gap: 6 }}>
                    {splitPlan.partKeys.map((k, i) => (
                      <div key={k} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
                        <span style={{ fontSize: 14 }}>{partLabel(k)}</span>
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
                        <span style={{ fontSize: 14 }}>{partLabel(k)} paid</span>
                        <input className="input" style={{ width: 110, textAlign: "right" }} inputMode="decimal" placeholder={currency}
                          value={paidVals[k] ?? ""} onChange={(e) => setPaidVals((p) => ({ ...p, [k]: e.target.value.replace(/[^0-9.]/g, "") }))} />
                      </div>
                    ))}
                    <span className="muted" style={{ fontSize: 12 }}>
                      Paid total {format(money(splitPlan.paidSum, currency), "en-US")} of {format(total, "en-US")} {splitPlan.paidSum === total.amount ? "✓" : "— must match"}
                    </span>
                    <span className="muted" style={{ fontSize: 11 }}>Only your payment uses {account?.name}; friends’ payments just change who owes whom.</span>
                  </div>
                ) : (
                  <span className="muted" style={{ fontSize: 12 }}>You paid {format(total, "en-US")} from {account?.name}.</span>
                )}

                {/* summary */}
                {splitWith.length === 0 ? (
                  <span className="muted" style={{ fontSize: 12 }}>Pick at least one person to split with.</span>
                ) : splitPlan.valid ? (
                  <div className="card" style={{ padding: 12, background: "var(--surface-2)", display: "grid", gap: 4, fontSize: 13 }}>
                    <div>Your share: <strong>{format(money(selfShare, currency), "en-US")}</strong> <span className="muted">(counts in your budget)</span></div>
                    {net > 0 && <div style={{ color: "var(--positive)" }}>Friends owe you {format(money(net, currency), "en-US")}</div>}
                    {net < 0 && <div style={{ color: "var(--negative)" }}>You’ll owe {format(money(-net, currency), "en-US")}</div>}
                  </div>
                ) : (
                  <span className="muted" style={{ fontSize: 12 }}>Adjust shares/payers so the totals match.</span>
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
    </div>
  );
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
