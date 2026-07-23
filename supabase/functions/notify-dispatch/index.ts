// PocketCare — notification dispatcher.
//
// Computes per-user triggers (upcoming EMIs/bills, budget limits, low balance,
// unusual spend), writes them into `pocketcare.notifications` (deduped so a
// given event alerts once), and delivers a Web Push to every registered
// subscription so the alert arrives even with the app closed (browser must be
// running in the background).
//
// Deploy:   supabase functions deploy notify-dispatch --no-verify-jwt
// Secrets:  supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:you@app
// Schedule: hit this endpoint on a cron (e.g. hourly) via Supabase scheduled
//           functions / pg_cron / an external scheduler. Optional POST body
//           { "user_id": "<uuid>" } runs it for a single user (handy for tests).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

const DAY = 86_400_000;
const todayISO = () => new Date().toISOString().slice(0, 10);
const addDays = (iso: string, n: number) => new Date(new Date(iso + "T00:00:00Z").getTime() + n * DAY).toISOString().slice(0, 10);

interface Prefs {
  push_enabled: boolean; emi_due: boolean; budget: boolean;
  low_balance: boolean; outlier: boolean; low_balance_threshold: number; emi_lead_days: number;
}
const DEFAULT_PREFS: Prefs = {
  push_enabled: false, emi_due: true, budget: true, low_balance: true, outlier: true,
  low_balance_threshold: 0, emi_lead_days: 3,
};

interface Notif { kind: string; title: string; body: string; severity: string; href: string | null; dedupe_key: string }

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") ?? "mailto:support@pocketcare.app";
  if (!url || !key) return json({ error: "Supabase environment not configured." }, 500);
  if (vapidPublic && vapidPrivate) webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

  const db = createClient(url, key, { db: { schema: "pocketcare" } });

  let onlyUser: string | undefined;
  try { onlyUser = (await req.json())?.user_id; } catch { /* no body — run for everyone */ }

  // Which users to process: the requested one, or everyone with a profile.
  const { data: profiles, error: pErr } = onlyUser
    ? await db.from("profiles").select("id").eq("id", onlyUser)
    : await db.from("profiles").select("id");
  if (pErr) return json({ error: pErr.message }, 500);

  let created = 0, pushed = 0;
  for (const p of profiles ?? []) {
    try {
      const r = await processUser(db, p.id);
      created += r.created; pushed += r.pushed;
    } catch (e) {
      console.error(`[notify-dispatch] user ${p.id} failed:`, (e as Error).message);
    }
  }
  return json({ ok: true, users: profiles?.length ?? 0, created, pushed });
});

async function processUser(db: ReturnType<typeof createClient>, userId: string): Promise<{ created: number; pushed: number }> {
  // Prefs (fall back to defaults if the user never opened settings).
  const { data: prefRow } = await db.from("notification_prefs")
    .select("push_enabled, emi_due, budget, low_balance, outlier, low_balance_threshold, emi_lead_days")
    .eq("user_id", userId).is("deleted_at", null).maybeSingle();
  const prefs: Prefs = prefRow
    ? {
        push_enabled: !!prefRow.push_enabled, emi_due: !!prefRow.emi_due, budget: !!prefRow.budget,
        low_balance: !!prefRow.low_balance, outlier: !!prefRow.outlier,
        low_balance_threshold: prefRow.low_balance_threshold ?? 0, emi_lead_days: prefRow.emi_lead_days ?? 3,
      }
    : DEFAULT_PREFS;

  // 1. Compute cron-style triggers and insert them (deduped).
  const out: Notif[] = [];
  if (prefs.emi_due) out.push(...await emiDue(db, userId, prefs.emi_lead_days));
  if (prefs.budget) out.push(...await budgetAlerts(db, userId));
  if (prefs.low_balance) out.push(...await lowBalance(db, userId, prefs.low_balance_threshold));
  if (prefs.outlier) out.push(...await outliers(db, userId));

  let created = 0;
  if (out.length) {
    const now = new Date().toISOString();
    const rows = out.map((n) => ({ ...n, user_id: userId, created_at: now, updated_at: now }));
    const { data: inserted, error } = await db.from("notifications")
      .upsert(rows, { onConflict: "user_id,dedupe_key", ignoreDuplicates: true })
      .select("id");
    if (error) console.error("[notify-dispatch] insert:", error.message);
    else created = (inserted ?? []).length;
  }

  // 2. Push EVERY unpushed recent notification — covers both the rows we just
  // inserted AND event-driven rows created by DB triggers (group joins/expenses)
  // since the last run. This unifies delivery so trigger rows aren't missed.
  const pushed = prefs.push_enabled ? await pushUnpushed(db, userId) : 0;
  return { created, pushed };
}

/** Deliver Web Push for any recent, unread, not-yet-pushed rows; mark them pushed. */
async function pushUnpushed(db: ReturnType<typeof createClient>, userId: string): Promise<number> {
  const since = new Date(Date.now() - 2 * DAY).toISOString();
  const { data: rows } = await db.from("notifications")
    .select("id, title, body, href, dedupe_key")
    .eq("user_id", userId).is("pushed_at", null).is("read_at", null).is("deleted_at", null)
    .gte("created_at", since)
    .order("created_at", { ascending: false }).limit(20);
  if (!rows || rows.length === 0) return 0;

  const sent = await sendPush(db, userId, rows);
  // Mark attempted rows pushed regardless of per-device success, so we don't
  // re-push on every tick (404/410 subscriptions are pruned inside sendPush).
  await db.from("notifications").update({ pushed_at: new Date().toISOString() })
    .in("id", rows.map((r: { id: string }) => r.id));
  return sent;
}

// --- Triggers ---------------------------------------------------------------

/** Loans whose EMI falls within the lead window, plus planned bill payments. */
async function emiDue(db: ReturnType<typeof createClient>, userId: string, lead: number): Promise<Notif[]> {
  const out: Notif[] = [];
  const today = todayISO();
  const horizon = addDays(today, lead);

  const { data: loans } = await db.from("loans")
    .select("id, lender, emi_amount, emi_due_day, currency, tenure_months, emis_paid")
    .eq("user_id", userId).is("deleted_at", null);
  const d = new Date();
  const y = d.getUTCFullYear(), m = d.getUTCMonth();
  for (const l of loans ?? []) {
    if (!l.emi_due_day || !l.emi_amount) continue;
    if (l.tenure_months && l.emis_paid != null && l.emis_paid >= l.tenure_months) continue; // closed
    // Due date this month (clamp day to month length).
    const dim = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
    const dueDay = Math.min(l.emi_due_day, dim);
    const due = new Date(Date.UTC(y, m, dueDay)).toISOString().slice(0, 10);
    if (due >= today && due <= horizon) {
      out.push({
        kind: "emi_due", severity: "warn",
        title: `EMI due ${due === today ? "today" : `on ${due}`}`,
        body: `${l.lender ?? "Loan"} · ${fmt(l.emi_amount, l.currency)}`,
        href: `/loans/${l.id}`,
        dedupe_key: `emi:${l.id}:${y}-${m + 1}`,
      });
    }
  }

  const { data: bills } = await db.from("planned_cashflow")
    .select("id, name, amount, currency, next_due")
    .eq("user_id", userId).eq("direction", "payment").eq("is_active", 1).is("deleted_at", null);
  for (const b of bills ?? []) {
    if (!b.next_due) continue;
    const due = b.next_due.slice(0, 10);
    if (due >= today && due <= horizon) {
      out.push({
        kind: "emi_due", severity: "info",
        title: `Payment due ${due === today ? "today" : `on ${due}`}`,
        body: `${b.name ?? "Scheduled payment"} · ${fmt(b.amount, b.currency)}`,
        href: `/cashflow`,
        dedupe_key: `bill:${b.id}:${due}`,
      });
    }
  }
  return out;
}

/** Budgets crossed 80% / 100% of their limit within the current period. */
async function budgetAlerts(db: ReturnType<typeof createClient>, userId: string): Promise<Notif[]> {
  const out: Notif[] = [];
  const { data: budgets } = await db.from("budgets")
    .select("id, name, limit_amount, currency, start_date, end_date, threshold_pct")
    .eq("user_id", userId).is("deleted_at", null);
  const today = todayISO();
  for (const bg of budgets ?? []) {
    if (!bg.limit_amount || bg.limit_amount <= 0) continue;
    const from = (bg.start_date ?? "").slice(0, 10) || addDays(today, -30);
    const to = (bg.end_date ?? "").slice(0, 10) || today;
    if (today < from || today > to) continue; // not the active period

    const { data: cats } = await db.from("budget_categories").select("category_id").eq("budget_id", bg.id);
    const catIds = (cats ?? []).map((c: { category_id: string }) => c.category_id);
    let q = db.from("transactions").select("amount")
      .eq("user_id", userId).eq("type", "expense").is("deleted_at", null)
      .gte("occurred_at", `${from}T00:00:00Z`).lte("occurred_at", `${to}T23:59:59Z`);
    if (catIds.length) q = q.in("category_id", catIds);
    const { data: txns } = await q;
    const spent = (txns ?? []).reduce((s: number, t: { amount: number }) => s + t.amount, 0);
    const pct = Math.round((spent / bg.limit_amount) * 100);
    const warnAt = bg.threshold_pct && bg.threshold_pct > 0 ? bg.threshold_pct : 80;

    const level = pct >= 100 ? "over" : pct >= warnAt ? "near" : null;
    if (!level) continue;
    out.push({
      kind: "budget", severity: level === "over" ? "urgent" : "warn",
      title: level === "over" ? `Over budget: ${bg.name}` : `${pct}% of ${bg.name} used`,
      body: `${fmt(spent, bg.currency)} of ${fmt(bg.limit_amount, bg.currency)}`,
      href: `/budgets`,
      dedupe_key: `budget:${bg.id}:${from}:${level}`,
    });
  }
  return out;
}

/** Accounts whose derived balance is at/below the user's floor. */
async function lowBalance(db: ReturnType<typeof createClient>, userId: string, threshold: number): Promise<Notif[]> {
  const { data: accts } = await db.from("accounts")
    .select("id, name, currency, kind, is_archived")
    .eq("user_id", userId).is("deleted_at", null);
  const real = (accts ?? []).filter((a: { kind?: string; is_archived?: number }) => (a.kind ?? "real") === "real" && !a.is_archived);
  if (real.length === 0) return [];

  const { data: txns } = await db.from("transactions")
    .select("type, amount, account_id, to_account_id, to_amount")
    .eq("user_id", userId).is("deleted_at", null);

  const bal = new Map<string, number>();
  for (const a of real) bal.set(a.id, 0);
  for (const t of txns ?? []) {
    if (bal.has(t.account_id)) {
      const cur = bal.get(t.account_id)!;
      if (t.type === "income" || t.type === "opening_balance" || t.type === "adjustment") bal.set(t.account_id, cur + t.amount);
      else if (t.type === "expense" || t.type === "transfer") bal.set(t.account_id, cur - t.amount);
    }
    if (t.type === "transfer" && t.to_account_id && bal.has(t.to_account_id)) {
      bal.set(t.to_account_id, bal.get(t.to_account_id)! + (t.to_amount ?? t.amount));
    }
  }

  const today = todayISO();
  const out: Notif[] = [];
  for (const a of real) {
    const b = bal.get(a.id) ?? 0;
    if (b <= threshold) {
      out.push({
        kind: "low_balance", severity: b < 0 ? "urgent" : "warn",
        title: `Low balance: ${a.name}`,
        body: `${fmt(b, a.currency)} remaining`,
        href: `/accounts`,
        dedupe_key: `lowbal:${a.id}:${today}`,
      });
    }
  }
  return out;
}

/** Expenses in the last ~2 days that are far above the user's typical spend. */
async function outliers(db: ReturnType<typeof createClient>, userId: string): Promise<Notif[]> {
  const since90 = addDays(todayISO(), -90);
  const { data: txns } = await db.from("transactions")
    .select("id, amount, description, occurred_at, currency")
    .eq("user_id", userId).eq("type", "expense").is("deleted_at", null)
    .gte("occurred_at", `${since90}T00:00:00Z`)
    .order("occurred_at", { ascending: false });
  const rows = txns ?? [];
  if (rows.length < 12) return []; // not enough history to judge "unusual"

  const amounts = rows.map((t: { amount: number }) => t.amount).sort((a: number, b: number) => a - b);
  const median = amounts[Math.floor(amounts.length / 2)];
  const floor = Math.max(median * 4, 200_00); // 4× median, and at least a small absolute floor
  const recentCut = addDays(todayISO(), -2);

  const out: Notif[] = [];
  for (const t of rows) {
    if (t.occurred_at.slice(0, 10) < recentCut) continue;
    if (t.amount >= floor) {
      out.push({
        kind: "outlier", severity: "warn",
        title: "Unusual transaction",
        body: `${(t.description ?? "Large expense").slice(0, 60)} · ${fmt(t.amount, t.currency)}`,
        href: `/transactions/${t.id}`,
        dedupe_key: `outlier:${t.id}`,
      });
    }
  }
  return out;
}

// --- Push delivery ----------------------------------------------------------

async function sendPush(db: ReturnType<typeof createClient>, userId: string, items: { title: string; body: string | null; href: string | null; dedupe_key: string }[]): Promise<number> {
  if (!Deno.env.get("VAPID_PRIVATE_KEY")) return 0;
  const { data: subs } = await db.from("push_subscriptions")
    .select("endpoint, p256dh, auth").eq("user_id", userId);
  if (!subs || subs.length === 0) return 0;

  // One push per new notification, to each of the user's devices.
  let sent = 0;
  for (const it of items) {
    const payload = JSON.stringify({ title: it.title, body: it.body ?? "", href: it.href ?? "/notifications", tag: it.dedupe_key });
    for (const s of subs) {
      const subscription = { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } };
      try {
        await webpush.sendNotification(subscription, payload);
        sent++;
      } catch (e) {
        const status = (e as { statusCode?: number }).statusCode;
        // 404/410 = subscription gone (unsubscribed / browser reset) — prune it.
        if (status === 404 || status === 410) {
          await db.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
        } else {
          console.error("[notify-dispatch] push failed:", status, (e as Error).message);
        }
      }
    }
  }
  return sent;
}

function fmt(minor: number, currency: string): string {
  const major = minor / 100;
  try { return new Intl.NumberFormat(undefined, { style: "currency", currency: currency || "INR", maximumFractionDigits: 0 }).format(major); }
  catch { return `${currency || ""} ${major.toFixed(0)}`; }
}
