"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@powersync/react";
import { getDb } from "../powersync";
import { money, format } from "@sanvya/money";
import { useTranslation } from "react-i18next";
import Link from "next/link";
import { X } from "react-feather";

interface Budget {
  id: string;
  name: string;
  limit_amount: number;
  currency: string;
  start_date: string | null;
  end_date: string | null;
  threshold_pct: number;
}

const todayISO = () => new Date().toISOString().slice(0, 10);
const addDays = (iso: string, n: number) => new Date(new Date(iso + "T00:00:00Z").getTime() + n * 86400000).toISOString().slice(0, 10);

export function BudgetAlertMonitor() {
  const { t } = useTranslation("budgets");
  const { data: budgets = [] } = useQuery<Budget>(
    "SELECT id, name, limit_amount, currency, start_date, end_date, threshold_pct FROM budgets WHERE deleted_at IS NULL"
  );
  
  const [alerts, setAlerts] = useState<{ id: string; name: string; pct: number; spent: number; limit: number; currency: string }[]>([]);

  useEffect(() => {
    async function checkBudgets() {
      const db = getDb();
      if (!db) return;
      
      const newAlerts = [];
      const today = todayISO();
      
      for (const bg of budgets) {
        if (!bg.limit_amount || bg.limit_amount <= 0) continue;
        const from = (bg.start_date ?? "").slice(0, 10) || addDays(today, -30);
        const to = (bg.end_date ?? "").slice(0, 10) || today;
        if (today < from || today > to) continue;
        
        const cacheKey = `budget_dismissed_${bg.id}_${from}_${to}`;
        if (localStorage.getItem(cacheKey)) continue;

        const cats = await db.getAll<{ category_id: string }>("SELECT category_id FROM budget_categories WHERE budget_id = ?", [bg.id]);
        const catIds = cats.map(c => c.category_id);
        
        let txns: { amount: number }[] = [];
        if (catIds.length > 0) {
          const placeholders = catIds.map(() => "?").join(",");
          txns = await db.getAll<{ amount: number }>(
            `SELECT amount FROM transactions WHERE type = 'expense' AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at <= ? AND category_id IN (${placeholders})`,
            [`${from}T00:00:00Z`, `${to}T23:59:59Z`, ...catIds]
          );
        } else {
          txns = await db.getAll<{ amount: number }>(
            `SELECT amount FROM transactions WHERE type = 'expense' AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at <= ?`,
            [`${from}T00:00:00Z`, `${to}T23:59:59Z`]
          );
        }
        
        const spent = txns.reduce((sum, t) => sum + t.amount, 0);
        const pct = Math.round((spent / bg.limit_amount) * 100);
        const warnAt = bg.threshold_pct && bg.threshold_pct > 0 ? bg.threshold_pct : 80;
        
        if (pct >= warnAt) {
          newAlerts.push({
            id: bg.id,
            name: bg.name,
            pct,
            spent,
            limit: bg.limit_amount,
            currency: bg.currency,
          });
        }
      }
      
      setAlerts(newAlerts);
    }
    
    checkBudgets();
  }, [budgets]);
  
  if (alerts.length === 0) return null;
  
  return (
    <div style={{ position: "fixed", bottom: 80, left: 20, right: 20, zIndex: 9999, display: "flex", flexDirection: "column", gap: 10, pointerEvents: "none" }}>
      {alerts.map((alert) => (
        <div key={alert.id} className="card fade-up" style={{ padding: "12px 16px", background: "var(--surface)", boxShadow: "0 8px 30px rgba(0,0,0,0.12)", border: alert.pct >= 100 ? "1px solid var(--negative)" : "1px solid var(--warn)", pointerEvents: "auto", display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12 }}>
          <div>
            <div style={{ fontWeight: 600, color: alert.pct >= 100 ? "var(--negative)" : "var(--warn)" }}>
              {alert.pct >= 100 ? `Over budget: ${alert.name}` : `${alert.pct}% of ${alert.name} used`}
            </div>
            <div className="muted" style={{ fontSize: 13, marginTop: 2 }}>
              {format(money(alert.spent, alert.currency))} of {format(money(alert.limit, alert.currency))}
            </div>
            <Link href={`/budgets?edit=${alert.id}`} style={{ fontSize: 13, fontWeight: 500, color: "var(--accent)", marginTop: 6, display: "inline-block" }}>
              View budget
            </Link>
          </div>
          <button 
            className="icon-btn" 
            style={{ margin: "-4px -8px 0 0", opacity: 0.6 }}
            onClick={() => {
              const bg = budgets.find(b => b.id === alert.id);
              if (bg) {
                const today = todayISO();
                const from = (bg.start_date ?? "").slice(0, 10) || addDays(today, -30);
                const to = (bg.end_date ?? "").slice(0, 10) || today;
                localStorage.setItem(`budget_dismissed_${bg.id}_${from}_${to}`, "1");
              }
              setAlerts(prev => prev.filter(a => a.id !== alert.id));
            }}
          >
            <X size={18} />
          </button>
        </div>
      ))}
    </div>
  );
}
