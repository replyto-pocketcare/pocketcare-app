"use client";

/**
 * Review a scanned receipt before it becomes money.
 *
 * The organising idea is the reconciliation strip: the user always knows
 * whether what's on screen adds up to the printed total, and can fix a
 * mismatch in one tap from either direction (add the missing line, or trust
 * the lines and correct the total). Nothing saves until it balances.
 */
import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { money } from "@sanvya/money";
import {
  balanceWithLine,
  reconcile,
  subtotals,
  type ReceiptDraft,
  type ReceiptLineKind,
} from "@sanvya/receipts";

import { useAccountBalances } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { getDb, getRepositories, getUserId } from "../../../src/powersync";
import { suggestCategory } from "../../../src/categorize/engine";
import { useGroups } from "../../../src/splits/hooks";
import { createGroup } from "../../../src/splits/write";
import { linkScan, updateScanDraft } from "../../../src/receipts/scan";
import {
  addLine,
  adoptComputedTotal,
  digitsFor,
  removeLine,
  sortedLines,
  toMajorString,
  toMinor,
  updateLine,
} from "../../../src/receipts/draft";
import { Spinner } from "../../../src/ui/Spinner";

const KINDS: readonly ReceiptLineKind[] = ["item", "tax", "service_charge", "tip", "discount"];

export default function ReviewReceiptPage() {
  return (
    <Suspense fallback={<Spinner />}>
      <ReviewInner />
    </Suspense>
  );
}

function ReviewInner() {
  const { t } = useTranslation("receipts");
  const router = useRouter();
  const params = useSearchParams();
  const scanId = params.get("scan") ?? "";
  const fmt = useMoneyFmt();
  const accounts = useAccountBalances();
  const groups = useGroups();

  const { data: scans = [], isLoading } = useQuery<{ id: string; parsed_json: string | null }>(
    "SELECT id, parsed_json FROM receipt_scans WHERE id = ? AND deleted_at IS NULL",
    [scanId],
  );
  const { data: categories = [] } = useQuery<{ id: string; name: string; kind: string }>(
    "SELECT id, name, kind FROM categories WHERE deleted_at IS NULL ORDER BY name",
  );

  const [draft, setDraft] = useState<ReceiptDraft | null>(null);
  const [accountId, setAccountId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [wantsSplit, setWantsSplit] = useState(false);
  const [groupId, setGroupId] = useState("");
  const [newGroupName, setNewGroupName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Hydrate the editable draft from the stored scan exactly once.
  useEffect(() => {
    if (draft || scans.length === 0) return;
    const raw = scans[0]?.parsed_json;
    if (!raw) return;
    try {
      setDraft(JSON.parse(raw) as ReceiptDraft);
    } catch {
      setError(t("review.corrupt", "We couldn't reopen this scan. Please scan it again."));
    }
  }, [scans, draft, t]);

  // Default the account to the first one; suggest a category from the merchant.
  useEffect(() => {
    if (!accountId && accounts.length > 0) setAccountId(accounts[0]!.account.id);
  }, [accounts, accountId]);

  // Reuse the same learned classifier the add-transaction form uses, so a
  // scanned "SPICE GARDEN" lands in whatever category the user has been
  // filing that merchant under.
  useEffect(() => {
    const merchant = draft?.merchant;
    if (!merchant || categoryId || categories.length === 0) return;
    const db = getDb();
    if (!db) return;
    let cancelled = false;
    void suggestCategory(merchant, db, getUserId(), categories).then((id) => {
      if (!cancelled && id) setCategoryId(id);
    });
    return () => { cancelled = true; };
  }, [draft?.merchant, categoryId, categories]);

  const digits = digitsFor(draft?.currency ?? "INR");
  const rec = useMemo(() => (draft ? reconcile(draft) : null), [draft]);
  const subs = useMemo(() => (draft ? subtotals(draft.lines) : null), [draft]);
  const cur = (draft?.currency ?? "INR") as Parameters<typeof money>[1];

  if (isLoading && !draft) return <Spinner />;
  if (!draft) {
    return (
      <div className="card" style={{ padding: 20 }}>
        {error ?? t("review.notFound", "That scan is no longer available.")}
      </div>
    );
  }

  const patch = (p: Partial<ReceiptDraft>) => setDraft({ ...draft, ...p });
  const balanced = rec?.ok ?? false;
  const canSave = balanced && !!accountId && !saving;

  async function saveAsTransaction() {
    if (!draft || !rec?.stated) return;
    setSaving(true);
    setError(null);
    try {
      await updateScanDraft(scanId, draft);
      const tx = await getRepositories().transactions.create({
        account_id: accountId,
        type: "expense",
        amount: money(rec.stated, cur),
        category_id: categoryId || null,
        description: draft.merchant ?? null,
        occurred_at: draft.occurredAt ?? new Date().toISOString().slice(0, 10),
        // The breakdown must sum to the total — reconciliation already proved it.
        items: draft.lines.map((l) => ({
          description: describeItem(l.description, l.quantity, l.unit),
          amount: money(l.amount, cur),
        })),
      });
      await linkScan(scanId, { transactionId: tx.id });
      router.push(`/transactions/${tx.id}`);
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  }

  async function goToSplit() {
    if (!draft) return;
    setSaving(true);
    setError(null);
    try {
      await updateScanDraft(scanId, draft);
      let gid = groupId;
      if (!gid && newGroupName.trim()) {
        gid = await createGroup({
          name: newGroupName.trim(),
          kind: "group",
          currency: draft.currency,
        });
      }
      if (!gid) {
        setError(t("review.pickGroup", "Choose a group, or name a new one."));
        setSaving(false);
        return;
      }
      router.push(`/receipts/split?scan=${scanId}&group=${gid}&account=${accountId}&category=${categoryId}`);
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  }

  return (
    <div style={{ display: "grid", gap: 16, maxWidth: 780 }}>
      <div>
        <h1 style={{ margin: 0 }}>{t("review.title", "Check the details")}</h1>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {t("review.intro", "We read this off the receipt — fix anything that looks wrong before saving.")}
        </p>
      </div>

      {/* ---- header fields ---- */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
        <div className="dash-cols" style={{ display: "grid", gap: 12, gridTemplateColumns: "1fr 1fr" }}>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, minWidth: 0 }}>
            {t("review.merchant", "Merchant")}
            <input
              className="input"
              value={draft.merchant ?? ""}
              onChange={(e) => patch({ merchant: e.target.value })}
              placeholder={t("review.merchantPlaceholder", "Where was this?")}
            />
          </label>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, minWidth: 0 }}>
            {t("review.date", "Date")}
            <input
              className="input"
              type="date"
              value={draft.occurredAt ?? ""}
              onChange={(e) => patch({ occurredAt: e.target.value })}
            />
          </label>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, minWidth: 0 }}>
            {t("review.account", "Paid from")}
            <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              {accounts.map((a) => (
                <option key={a.account.id} value={a.account.id}>{a.account.name}</option>
              ))}
            </select>
          </label>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, minWidth: 0 }}>
            {t("review.category", "Category")}
            <select className="input" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">{t("review.noCategory", "Uncategorised")}</option>
              {categories.filter((c) => c.kind !== "income").map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
        </div>
      </section>

      {/* ---- line items ---- */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 10, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
          <strong>{t("review.items", "Items & charges")}</strong>
          <span className="muted" style={{ fontSize: 12 }}>
            {t("review.lineCount", "{{count}} lines", { count: draft.lines.length })}
          </span>
        </div>

        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, minWidth: 520 }}>
            <thead>
              <tr style={{ textAlign: "left", color: "var(--text-2)", fontSize: 12 }}>
                <th style={{ padding: "6px 4px" }}>{t("review.description", "Description")}</th>
                <th style={{ padding: "6px 4px", width: 96 }}>{t("review.qty", "Qty")}</th>
                <th style={{ padding: "6px 4px", width: 120 }}>{t("review.kind", "Type")}</th>
                <th style={{ padding: "6px 4px", width: 110, textAlign: "right" }}>{t("review.amount", "Amount")}</th>
                <th style={{ width: 36 }} />
              </tr>
            </thead>
            <tbody>
              {sortedLines(draft).map((line) => (
                <tr key={line.id} style={{ borderTop: "1px solid var(--border)" }}>
                  <td style={{ padding: "6px 4px" }}>
                    <input
                      className="input"
                      value={line.description}
                      onChange={(e) => setDraft(updateLine(draft, line.id, { description: e.target.value }))}
                      aria-label={t("review.description", "Description")}
                    />
                  </td>
                  <td style={{ padding: "6px 4px" }}>
                    <input
                      className="input"
                      inputMode="decimal"
                      value={line.quantity !== null ? String(line.quantity / 1000) : ""}
                      placeholder="—"
                      onChange={(e) => {
                        const v = e.target.value.trim();
                        const n = Number.parseFloat(v.replace(",", "."));
                        setDraft(updateLine(draft, line.id, {
                          quantity: v === "" || !Number.isFinite(n) ? null : Math.round(n * 1000),
                        }));
                      }}
                      aria-label={t("review.qty", "Qty")}
                    />
                  </td>
                  <td style={{ padding: "6px 4px" }}>
                    <select
                      className="input"
                      value={line.kind}
                      onChange={(e) => {
                        const kind = e.target.value as ReceiptLineKind;
                        // Keep the sign consistent with the new meaning.
                        const amount = kind === "discount" ? -Math.abs(line.amount) : Math.abs(line.amount);
                        setDraft(updateLine(draft, line.id, { kind, amount }));
                      }}
                      aria-label={t("review.kind", "Type")}
                    >
                      {KINDS.map((k) => (
                        <option key={k} value={k}>{t(`kind.${k}`, k.replace("_", " "))}</option>
                      ))}
                    </select>
                  </td>
                  <td style={{ padding: "6px 4px" }}>
                    <input
                      className="input"
                      inputMode="decimal"
                      style={{ textAlign: "right" }}
                      value={toMajorString(line.amount, digits)}
                      onChange={(e) => {
                        const v = toMinor(e.target.value, digits);
                        setDraft(updateLine(draft, line.id, {
                          amount: line.kind === "discount" ? -Math.abs(v) : v,
                        }));
                      }}
                      aria-label={t("review.amount", "Amount")}
                    />
                  </td>
                  <td style={{ padding: "6px 4px", textAlign: "center" }}>
                    <button
                      type="button"
                      className="btn ghost"
                      style={{ padding: "4px 8px", minHeight: 0 }}
                      aria-label={t("review.removeLine", "Remove line")}
                      onClick={() => setDraft(removeLine(draft, line.id))}
                    >
                      ×
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <button className="btn ghost" type="button" onClick={() => setDraft(addLine(draft, "item"))}>
            + {t("review.addItem", "Add item")}
          </button>
          <button className="btn ghost" type="button" onClick={() => setDraft(addLine(draft, "tax"))}>
            + {t("review.addCharge", "Add charge")}
          </button>
        </div>
      </section>

      {/* ---- totals + reconciliation ---- */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 10 }}>
        {subs && (
          <dl style={{ display: "grid", gap: 6, margin: 0, fontSize: 14 }}>
            <Row label={t("review.subtotalItems", "Items")} value={fmt(money(subs.items, cur))} />
            {subs.discount !== 0 && <Row label={t("kind.discount", "Discount")} value={fmt(money(subs.discount, cur))} />}
            {subs.serviceCharge !== 0 && <Row label={t("kind.service_charge", "Service charge")} value={fmt(money(subs.serviceCharge, cur))} />}
            {subs.tax !== 0 && <Row label={t("kind.tax", "Tax")} value={fmt(money(subs.tax, cur))} />}
            {subs.tip !== 0 && <Row label={t("kind.tip", "Tip")} value={fmt(money(subs.tip, cur))} />}
          </dl>
        )}

        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, maxWidth: 220 }}>
          {t("review.total", "Total on the receipt")}
          <input
            className="input"
            inputMode="decimal"
            value={draft.total !== null ? toMajorString(draft.total, digits) : ""}
            placeholder="—"
            onChange={(e) => {
              const v = e.target.value.trim();
              patch({ total: v === "" ? null : toMinor(v, digits) });
            }}
          />
        </label>

        {rec && (
          <div
            role="status"
            style={{
              display: "flex",
              gap: 10,
              alignItems: "center",
              flexWrap: "wrap",
              padding: "10px 12px",
              borderRadius: 10,
              fontSize: 13,
              background: balanced ? "var(--surface-2)" : "color-mix(in srgb, var(--negative) 12%, transparent)",
              color: balanced ? "var(--text-2)" : "var(--text)",
            }}
          >
            {balanced ? (
              <span>
                {t("review.balanced", "Adds up: {{total}}", { total: fmt(money(rec.computed, cur)) })} ✓
              </span>
            ) : (
              <>
                <span>
                  {rec.reason === "missing_total"
                    ? t("review.needTotal", "Enter the total printed on the receipt.")
                    : t("review.offBy", "Lines add up to {{computed}}, but the receipt says {{stated}}.", {
                        computed: fmt(money(rec.computed, cur)),
                        stated: rec.stated !== null ? fmt(money(rec.stated, cur)) : "—",
                      })}
                </span>
                {rec.reason === "mismatch" && (
                  <>
                    <button
                      className="btn"
                      type="button"
                      style={{ padding: "4px 10px", minHeight: 0, height: 30, fontSize: 12 }}
                      onClick={() => setDraft(balanceWithLine(draft, `fix-${Date.now()}`, t("review.unmatched", "Unmatched")))}
                    >
                      {t("review.addDifference", "Add {{amount}} as a line", { amount: fmt(money(rec.delta, cur)) })}
                    </button>
                    <button
                      className="btn ghost"
                      type="button"
                      style={{ padding: "4px 10px", minHeight: 0, height: 30, fontSize: 12 }}
                      onClick={() => setDraft(adoptComputedTotal(draft))}
                    >
                      {t("review.useComputed", "Use {{amount}} as the total", { amount: fmt(money(rec.computed, cur)) })}
                    </button>
                  </>
                )}
              </>
            )}
          </div>
        )}
      </section>

      {/* ---- record or split ---- */}
      <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
        <div style={{ display: "flex", gap: 8 }}>
          <button className="chip" type="button" data-active={!wantsSplit} onClick={() => setWantsSplit(false)}>
            {t("review.justRecord", "Just record it")}
          </button>
          <button className="chip" type="button" data-active={wantsSplit} onClick={() => setWantsSplit(true)}>
            {t("review.splitIt", "Split this bill")}
          </button>
        </div>

        {wantsSplit && (
          <div style={{ display: "grid", gap: 10 }}>
            <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>
              {t("review.group", "With which group?")}
              <select
                className="input"
                value={groupId}
                onChange={(e) => { setGroupId(e.target.value); setNewGroupName(""); }}
              >
                <option value="">{t("review.newGroup", "Create a new group…")}</option>
                {groups.map((g) => (
                  <option key={g.id} value={g.id}>{g.name}</option>
                ))}
              </select>
            </label>
            {!groupId && (
              <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>
                {t("review.newGroupName", "New group name")}
                <input
                  className="input"
                  value={newGroupName}
                  onChange={(e) => setNewGroupName(e.target.value)}
                  placeholder={t("review.newGroupPlaceholder", "Dinner with friends")}
                />
              </label>
            )}
            <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
              {t("review.splitNote", "Next you'll assign each item to whoever had it, and choose how tax and service charge are shared.")}
            </p>
          </div>
        )}

        {error && <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>}

        <div>
          <button
            className="btn"
            type="button"
            disabled={!canSave}
            onClick={() => void (wantsSplit ? goToSplit() : saveAsTransaction())}
          >
            {saving ? <Spinner /> : null}
            {wantsSplit ? t("review.continueToSplit", "Continue to split") : t("review.save", "Save transaction")}
          </button>
          {!balanced && (
            <p className="muted" style={{ fontSize: 11.5, margin: "8px 0 0" }}>
              {t("review.mustBalance", "The lines need to add up to the total before this can be saved.")}
            </p>
          )}
        </div>
      </section>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
      <dt className="muted" style={{ margin: 0 }}>{label}</dt>
      <dd style={{ margin: 0, fontVariantNumeric: "tabular-nums" }}>{value}</dd>
    </div>
  );
}

/** Fold quantity into the stored item description — transaction_items has no qty column. */
function describeItem(description: string, quantity: number | null, unit: string | null): string {
  const name = description.trim() || "Item";
  if (quantity === null) return name;
  const q = quantity / 1000;
  const qty = Number.isInteger(q) ? String(q) : q.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
  return unit ? `${name} (${qty} ${unit})` : `${name} × ${qty}`;
}
