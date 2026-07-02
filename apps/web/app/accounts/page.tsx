"use client";

import Link from "next/link";
import { format } from "@pocketcare/money";
import { useAccountBalances } from "../../src/hooks";
import { getDb } from "../../src/powersync";

export default function AccountsPage() {
  const balances = useAccountBalances();

  async function toggleNw(id: string, current: boolean) {
    await getDb()?.execute("UPDATE accounts SET include_in_net_worth = ?, updated_at = ? WHERE id = ?", [current ? 0 : 1, new Date().toISOString(), id]);
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Accounts</h1>
        <Link href="/accounts/new" className="btn">＋ New account</Link>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 12 }}>
        {balances.map(({ account, balance }) => {
          const included = account.include_in_net_worth !== 0;
          return (
            <div key={account.id} className="card" style={{ padding: 0, overflow: "hidden", display: "flex" }}>
              <div style={{ width: 6, background: account.color || "var(--accent)" }} />
              <div style={{ padding: 18, display: "grid", gap: 4, flex: 1 }}>
                <span className="muted" style={{ fontSize: 12, textTransform: "capitalize" }}>{account.type.replace("_", " ")} · {account.currency}</span>
                <span style={{ fontWeight: 600 }}>{account.name}</span>
                <span style={{ fontSize: 22, fontWeight: 700 }}>{format(balance, "en-US")}</span>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 4 }}>
                  <label style={{ display: "flex", gap: 6, alignItems: "center", fontSize: 12 }} className="muted">
                    <input type="checkbox" checked={included} onChange={() => toggleNw(account.id, included)} /> in net worth
                  </label>
                  <Link href={`/accounts/${account.id}/edit`} className="chip" style={{ padding: "2px 10px", fontSize: 12 }}>Edit</Link>
                </div>
              </div>
            </div>
          );
        })}
        {balances.length === 0 && <p className="muted">No accounts yet.</p>}
      </div>
    </div>
  );
}
