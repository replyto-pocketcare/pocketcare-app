"use client";

/**
 * Notification inbox. Reads local rows (synced from Postgres), lets the user
 * open the deep link, mark read, dismiss, or clear all. Push delivery is
 * managed from Settings → Notifications.
 */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useNotifications, useUnreadCount, markRead, markAllRead, dismiss } from "../../src/notifications/hooks";
import { BellIcon } from "../../src/ui/icons";

const SEV_COLOR: Record<string, string> = {
  info: "var(--accent)",
  warn: "var(--warning, #c08a3e)",
  urgent: "var(--negative)",
};

function timeAgo(iso: string): string {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return "just now";
  const m = Math.floor(s / 60); if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60); if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24); if (d < 7) return `${d}d ago`;
  return new Date(iso).toLocaleDateString();
}

export default function NotificationsPage() {
  const items = useNotifications();
  const unread = useUnreadCount();
  const router = useRouter();

  return (
    <div style={{ display: "grid", gap: 16, maxWidth: 640 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Notifications</h1>
        <div style={{ display: "flex", gap: 8 }}>
          {unread > 0 && <button className="chip" onClick={() => void markAllRead()}>Mark all read</button>}
          <Link href="/settings" className="chip">Settings</Link>
        </div>
      </div>

      {items.length === 0 ? (
        <div className="card" style={{ padding: 40, textAlign: "center", display: "grid", gap: 8, justifyItems: "center" }}>
          <span style={{ color: "var(--text-3)" }}><BellIcon size={30} /></span>
          <strong>You're all caught up</strong>
          <span className="muted" style={{ fontSize: 13 }}>Alerts about bills, budgets, low balances and unusual spend will show up here.</span>
          <Link href="/settings" className="btn ghost" style={{ justifySelf: "center", marginTop: 6 }}>Enable notifications</Link>
        </div>
      ) : (
        <div className="card" style={{ padding: 0, overflow: "hidden" }}>
          {items.map((n, i) => (
            <div key={n.id}
              style={{
                display: "flex", gap: 12, alignItems: "flex-start", padding: "12px 14px",
                borderTop: i === 0 ? "none" : "1px solid var(--border)",
                background: n.read_at ? "transparent" : "var(--accent-ghost)",
                minWidth: 0,
              }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, marginTop: 6, flexShrink: 0, background: n.read_at ? "var(--border-strong)" : (SEV_COLOR[n.severity] ?? "var(--accent)") }} />
              <div
                style={{ flex: 1, minWidth: 0, cursor: n.href ? "pointer" : "default" }}
                onClick={() => { void markRead(n.id); if (n.href) router.push(n.href); }}>
                <div style={{ fontSize: 14, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{n.title}</div>
                {n.body && <div className="muted" style={{ fontSize: 12.5, lineHeight: 1.4 }}>{n.body}</div>}
                <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>{timeAgo(n.created_at)}</div>
              </div>
              <button className="chip" style={{ padding: "2px 8px", flexShrink: 0 }} aria-label="Dismiss" onClick={() => void dismiss(n.id)}>×</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
