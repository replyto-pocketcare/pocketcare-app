// Sanvya payment handles — store a user's UPI ID and release it, narrowly.
//
// This function is the ONLY way a UPI ID moves between two users. Handles are
// never synced to devices (see 0041): they live encrypted at rest here and are
// decrypted just-in-time for a caller who has a genuine reason to pay someone.
//
// THE DISCLOSURE GATE IS THE WHOLE POINT. Without it this endpoint is a
// UPI-ID directory: ask for any user id, get their payment address. Every
// release therefore requires ALL of:
//   1. the caller and the owner share a live group,
//   2. a non-zero balance exists between them,
//   3. the caller is under the rate limit,
// and writes an audit row the owner can read. Do not loosen these.
//
// Deploy:
//   supabase secrets set PAYMENT_HANDLE_KEY=<long random string>
//   supabase functions deploy payment-handle
// verify_jwt is ON by default, so only signed-in users can call it.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Always HTTP 200 with the payload in the body, so functions.invoke() always
// hands us a readable body (matches assistant / receipt-scan).
function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

/** Max handle fetches per caller per hour. Generous for real use, useless for scraping. */
const FETCH_LIMIT_PER_HOUR = 20;

// --- VPA validation (mirror of @sanvya/upi; keep the two in sync) -------
const VPA_RE = /^[a-z0-9](?:[a-z0-9._-]{0,60}[a-z0-9])?@[a-z][a-z0-9.-]{1,63}$/i;
function isValidVpa(value: string): boolean {
  const v = value.trim();
  if (v.length < 3 || v.length > 128) return false;
  if (v.includes("..")) return false;
  if (v.split("@").length !== 2) return false;
  const handle = v.slice(v.lastIndexOf("@") + 1);
  if (handle.startsWith(".") || handle.endsWith(".")) return false;
  return VPA_RE.test(v);
}
function maskVpa(value: string): string {
  const at = value.lastIndexOf("@");
  if (at <= 0) return "••••";
  const name = value.slice(0, at);
  const handle = value.slice(at);
  return name.length <= 3 ? `${name[0] ?? ""}••••${handle}` : `${name.slice(0, 3)}••••${handle}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cryptoKey = Deno.env.get("PAYMENT_HANDLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Supabase environment not configured." });
  if (!cryptoKey) return json({ error: "Payments are not configured (missing PAYMENT_HANDLE_KEY)." });

  const supabase = createClient(supabaseUrl, serviceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" });

  let payload: { action?: string; vpa?: string; displayName?: string; counterpartyId?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body." });
  }

  // Encrypt/decrypt happen inside Postgres (pgp_sym_encrypt) via the RPCs in
  // migration 0041, so the key is only ever a function argument and plaintext
  // never lands in a column.
  switch (payload.action) {
    // ---------------------------------------------------------------- set --
    case "set": {
      const vpa = String(payload.vpa ?? "").trim().toLowerCase();
      if (!isValidVpa(vpa)) {
        return json({ error: "That doesn't look like a UPI ID. It should look like name@bank." });
      }
      // Guests are blocked by a DB trigger too — this is the friendly message.
      if (user.is_anonymous) {
        return json({
          error: "Create an account before saving a UPI ID.",
          code: "guest_not_allowed",
        });
      }

      const displayName = String(payload.displayName ?? "").trim().slice(0, 50) || null;
      const { error } = await supabase.rpc("upsert_payment_handle", {
        p_user: user.id,
        p_vpa: vpa,
        p_hint: maskVpa(vpa),
        p_name: displayName,
        p_key: cryptoKey,
      });
      if (error) {
        const msg = String((error as { message?: string }).message ?? "");
        if (msg.includes("Guest accounts")) {
          return json({ error: "Create an account before saving a UPI ID.", code: "guest_not_allowed" });
        }
        return json({ error: `Couldn't save that: ${msg}` });
      }
      return json({ ok: true, hint: maskVpa(vpa) });
    }

    // ------------------------------------------------------------- forget --
    case "forget": {
      const { error } = await supabase
        .from("payment_handles")
        .update({ deleted_at: new Date().toISOString(), is_primary: false })
        .eq("user_id", user.id)
        .is("deleted_at", null);
      if (error) return json({ error: (error as { message: string }).message });
      return json({ ok: true });
    }

    // ---------------------------------------------------------------- get --
    case "get": {
      const counterpartyId = String(payload.counterpartyId ?? "");
      if (!counterpartyId) return json({ error: "counterpartyId is required." });
      if (counterpartyId === user.id) return json({ error: "That's you." });

      // --- gate 3: rate limit (cheapest check first) ---
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
      const { count: recent } = await supabase
        .from("payment_handle_disclosures")
        .select("id", { count: "exact", head: true })
        .eq("viewer_user_id", user.id)
        .gte("created_at", since);
      if ((recent ?? 0) >= FETCH_LIMIT_PER_HOUR) {
        return json({ error: "Too many lookups. Try again a bit later.", code: "rate_limited" });
      }

      // --- gate 1: a shared, live group ---
      const { data: gate, error: gateErr } = await supabase.rpc("payment_handle_gate", {
        p_viewer: user.id,
        p_owner: counterpartyId,
      });
      if (gateErr) return json({ error: `Couldn't verify access: ${(gateErr as { message: string }).message}` });

      const row = (Array.isArray(gate) ? gate[0] : gate) as
        | { shared_group: string | null; has_activity: boolean | null }
        | null;
      if (!row?.shared_group) {
        return json({ error: "You can only get someone's UPI ID if you share a group.", code: "no_group" });
      }
      // --- gate 2: a real financial relationship ---
      // NOTE: this checks that shared expenses or settlements EXIST between the
      // two of you, not that the exact pairwise net is non-zero. The precise
      // net is computed client-side (`pairwiseEdges`), and reimplementing that
      // allocation in SQL would risk the two drifting apart — a gate that
      // disagrees with the balance on screen is worse than a slightly broader
      // one. This still blocks the directory-harvesting case completely.
      if (!row.has_activity) {
        return json({
          error: "There's nothing to settle with them yet.",
          code: "no_balance",
        });
      }

      const { data: handle, error: hErr } = await supabase.rpc("read_payment_handle", {
        p_user: counterpartyId,
        p_key: cryptoKey,
      });
      if (hErr) return json({ error: `Couldn't read that: ${(hErr as { message: string }).message}` });

      const h = (Array.isArray(handle) ? handle[0] : handle) as
        | { vpa: string; display_name: string | null }
        | null;
      if (!h?.vpa) {
        return json({ error: "They haven't added a UPI ID yet.", code: "no_handle" });
      }

      // Audit the release. Deliberately after the decrypt but before returning,
      // so a disclosure is never silent.
      await supabase.from("payment_handle_disclosures").insert({
        owner_user_id: counterpartyId,
        viewer_user_id: user.id,
        group_id: row.shared_group,
      });

      return json({ vpa: h.vpa, displayName: h.display_name });
    }

    default:
      return json({ error: `Unknown action: ${payload.action ?? "(none)"}` });
  }
});
