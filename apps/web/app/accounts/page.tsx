"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useAccountBalances, useAccountsLoading } from "../../src/hooks";
import { getDb } from "../../src/powersync";
import { useMoneyFmt } from "../../src/ui/Money";
import { CardsSkeleton } from "../../src/ui/Skeleton";

export default function AccountsPage() {
  const [showArchived, setShowArchived] = useState(false);
  const { t } = useTranslation();
  const fmt = useMoneyFmt();
  const balances = useAccountBalances(showArchived);
  const archivedCount = useAccountBalances(true).filter((b) => b.account.is_archived).length;
  const accountsLoading = useAccountsLoading();

  async function toggleNw(id: string, current: boolean) {
    await getDb()?.execute("UPDATE accounts SET include_in_net_worth = ?, updated_at = ? WHERE id = ?", [current ? 0 : 1, new Date().toISOString(), id]);
  }
  async function setArchived(id: string, archived: boolean) {
    await getDb()?.execute("UPDATE accounts SET is_archived = ?, updated_at = ? WHERE id = ?", [archived ? 1 : 0, new Date().toISOString(), id]);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1>{t("pages.accounts", "Accounts")}</h1>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          {archivedCount > 0 && (
            <button className="chip" data-active={showArchived} onClick={() => setShowArchived((v) => !v)}>
              {showArchived ? "Hide archived" : `Show archived (${archivedCount})`}
            </button>
          )}
          <Link href="/accounts/new" className="btn">＋ New account</Link>
        </div>
      </div>
      {balances.length === 0 && accountsLoading ? (
        <CardsSkeleton count={4} minWidth={260} />
      ) : (
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(260px, 100%), 1fr))", gap: 12 }}>
        {balances.map(({ account, balance }) => {
          const included = account.include_in_net_worth !== 0;
          const archived = !!account.is_archived;
          return (
            <div key={account.id} className="card" style={{ padding: 0, overflow: "hidden", display: "flex", opacity: archived ? 0.6 : 1 }}>
              <div style={{ width: 6, background: account.color || "var(--accent)" }} />
              <div style={{ padding: 18, display: "grid", gap: 4, flex: 1 }}>
                <span className="muted" style={{ fontSize: 12, textTransform: "capitalize" }}>
                  {account.type.replace("_", " ")} · {account.currency}{archived ? " · archived" : ""}
                </span>
                <span style={{ fontWeight: 600 }}>{account.name}</span>
                <span style={{ fontSize: 22, fontWeight: 700 }}>{fmt(balance)}</span>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 4 }}>
                  {archived ? (
                    <button className="chip" style={{ padding: "2px 10px", fontSize: 12 }} onClick={() => setArchived(account.id, false)}>Unarchive</button>
                  ) : (
                    <label style={{ display: "flex", gap: 6, alignItems: "center", fontSize: 12 }} className="muted">
                      <input type="checkbox" checked={included} onChange={() => toggleNw(account.id, included)} /> in net worth
                    </label>
                  )}
                  <Link href={`/accounts/${account.id}/edit`} className="chip" style={{ padding: "2px 10px", fontSize: 12 }}>Edit</Link>
                </div>
              </div>
            </div>
          );
        })}
        {balances.length === 0 && <p className="muted">No accounts yet.</p>}
      </div>
      )}
    </div>
  );
}
