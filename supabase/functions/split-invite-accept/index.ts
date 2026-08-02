// Accept a split-group invite. The accepting user (JWT) is added to the group
// and connected to the inviter. Link-is-the-secret: any logged-in user with a
// valid, unexpired token can join.
// Deploy: supabase functions deploy split-invite-accept
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!auth) return json({ error: "Missing Authorization header" }, 401);
  if (!supabaseUrl || !serviceKey) return json({ error: "Supabase environment not configured." }, 500);

  const supabase = createClient(supabaseUrl, serviceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  let body: { token?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }
  if (!body.token) return json({ error: "token is required." }, 400);

  const { data: inv } = await supabase.from("split_invitations")
    .select("id, group_id, inviter, status, accepted_by, expires_at").eq("token", body.token).maybeSingle();
  if (!inv) return json({ error: "Invite not found." }, 404);

  // Idempotency: reopening an invite you already used (double-tap, refresh, or
  // coming back to the link) must NOT error — just send you back into the group.
  // Only a *different* user reusing a spent link is rejected.
  if (inv.status !== "pending") {
    const { data: mem } = await supabase.from("split_group_members")
      .select("id").eq("group_id", inv.group_id).eq("user_id", user.id).is("deleted_at", null).maybeSingle();
    if (mem || inv.accepted_by === user.id) return json({ group_id: inv.group_id });
    if (inv.status === "expired") return json({ error: "This invite has expired." }, 410);
    return json({ error: "This invite has already been used." }, 410);
  }

  if (inv.expires_at && new Date(inv.expires_at).getTime() < Date.now()) {
    await supabase.from("split_invitations").update({ status: "expired" }).eq("id", inv.id);
    return json({ error: "This invite has expired." }, 410);
  }

  // Add membership (idempotent).
  const { error: memErr } = await supabase.from("split_group_members")
    .upsert({ group_id: inv.group_id, user_id: user.id, role: "member" }, { onConflict: "group_id,user_id", ignoreDuplicates: true });
  if (memErr) return json({ error: memErr.message }, 500);

  await supabase.from("split_invitations").update({ status: "accepted", accepted_by: user.id }).eq("id", inv.id);

  // Connect inviter <-> accepter (canonical ordering user_a < user_b).
  if (inv.inviter !== user.id) {
    const [a, b] = [inv.inviter, user.id].sort();
    await supabase.from("connections").upsert({ user_a: a, user_b: b }, { onConflict: "user_a,user_b", ignoreDuplicates: true });
  }

  return json({ group_id: inv.group_id });
});
