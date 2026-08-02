"use client";

/**
 * Payments other people say they've made to you, awaiting your confirmation.
 *
 * This exists because UPI Intent gives us no callback: the payer told their
 * bank, not us. Only the payee can see the money land, so only the payee can
 * close the loop.
 *
 * Note what "Didn't arrive" does NOT do: it doesn't unwind the payer's ledger
 * entry. The ledger is append-only, and if their money really left, that's
 * still true. What changes is that the settlement stops counting toward the
 * balance between you.
 */
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { money } from "@sanvya/money";

import { useMyUserId, useUserProfiles } from "../splits/hooks";
import { confirmSettlement, disputeSettlement, type PendingSettlement } from "../splits/write";
import { useMoneyFmt } from "../ui/Money";
import { Spinner } from "../ui/Spinner";

export function usePendingSettlements(): PendingSettlement[] {
  const me = useMyUserId();
  const { data = [] } = useQuery<PendingSettlement>(
    `SELECT id, from_user, to_user, amount, currency, group_id, status, upi_ref, created_at
     FROM settlements
     WHERE status = 'pending' AND deleted_at IS NULL AND to_user = ? AND created_by <> ?
     ORDER BY created_at DESC`,
    [me, me],
  );
  return data;
}

export function PendingSettlements() {
  const { t } = useTranslation("payments");
  const fmt = useMoneyFmt();
  const profiles = useUserProfiles();
  const pending = usePendingSettlements();

  const { data: accounts = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at",
  );

  const [accountId, setAccountId] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (pending.length === 0) return null;

  const nameOf = (id: string) => profiles.get(id)?.name ?? t("someone", "Someone");

  async function act(s: PendingSettlement, arrived: boolean) {
    setBusyId(s.id);
    setError(null);
    try {
      if (arrived) await confirmSettlement(s, accountId || null);
      else await disputeSettlement(s.id);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section className="card" style={{ padding: 16, display: "grid", gap: 12 }}>
      <div>
        <strong>{t("confirm.title", "Confirm a payment")}</strong>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {t("confirm.intro", "We can't see UPI transfers, so please check your bank before confirming.")}
        </p>
      </div>

      {pending.map((s) => (
        <div key={s.id} style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}>
            <span style={{ fontSize: 14 }}>
              {t("confirm.claim", "{{name}} says they paid you", { name: nameOf(s.from_user) })}
            </span>
            <strong style={{ fontVariantNumeric: "tabular-nums" }}>
              {fmt(money(s.amount, s.currency as Parameters<typeof money>[1]))}
            </strong>
          </div>

          {/* The UPI reference is the one thread that ties this to a bank
              statement line, which is exactly what you need when it's missing. */}
          {s.upi_ref && (
            <span className="muted" style={{ fontSize: 11.5 }}>
              {t("confirm.reference", "Reference {{ref}} — look for this in your bank statement", { ref: s.upi_ref })}
            </span>
          )}

          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>{t("confirm.receivedInto", "Received into")}</span>
            <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              <option value="">{t("confirm.noAccount", "Don't record a deposit")}</option>
              {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </label>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn" type="button" disabled={busyId === s.id} onClick={() => void act(s, true)}>
              {busyId === s.id ? <Spinner /> : null}
              {t("confirm.yes", "Yes, it arrived")}
            </button>
            <button className="btn ghost" type="button" disabled={busyId === s.id} onClick={() => void act(s, false)}>
              {t("confirm.no", "Didn't arrive")}
            </button>
          </div>
        </div>
      ))}

      {error && <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>}
    </section>
  );
}

/** Small "awaiting confirmation" pill for the payer's side. */
export function PendingChip() {
  const { t } = useTranslation("payments");
  return (
    <span
      style={{
        flexShrink: 0, fontSize: 10.5, fontWeight: 700, letterSpacing: "0.03em", textTransform: "uppercase",
        color: "var(--text-2)", background: "var(--surface-2)", border: "1px solid var(--border)",
        borderRadius: 999, padding: "1px 7px", lineHeight: 1.5,
      }}
    >
      {t("confirm.pendingChip", "Awaiting")}
    </span>
  );
}
