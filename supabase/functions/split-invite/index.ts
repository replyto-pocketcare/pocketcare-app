// Create a split-group invite. The caller (JWT) must be a member of the group.
// Returns a token + shareable link (link is the secret; expires in 14 days).
// Email delivery is out of scope for v1.
// Deploy: supabase functions deploy split-invite
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

  let body: { group_id?: string; email?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body." }, 400); }
  if (!body.group_id) return json({ error: "group_id is required." }, 400);

  const { data: member } = await supabase.from("split_group_members")
    .select("id").eq("group_id", body.group_id).eq("user_id", user.id).is("deleted_at", null).maybeSingle();
  if (!member) return json({ error: "You are not a member of this group." }, 403);

  const token = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  const expiresAt = new Date(Date.now() + 14 * 86_400_000).toISOString();
  const { error: insErr } = await supabase.from("split_invitations").insert({
    group_id: body.group_id, inviter: user.id, invitee_email: body.email ?? null, token, status: "pending", expires_at: expiresAt,
  });
  if (insErr) return json({ error: insErr.message }, 500);

  const appUrl = Deno.env.get("APP_URL");
  return json({ token, link: appUrl ? `${appUrl}/join?token=${token}` : null, expires_at: expiresAt });
});
