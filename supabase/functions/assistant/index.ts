// PocketCare AI assistant — thin, authenticated proxy to Anthropic's Messages API.
//
// The API key lives ONLY here (as a Supabase secret); the browser never sees it.
// The client sends the conversation + tool definitions + an AGGREGATED financial
// summary (never raw transactions). This function forwards to Claude and returns
// the raw response, including any tool_use blocks, which the client executes
// locally against its SQLite DB (with user confirmation for write actions).
//
// Deploy:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy assistant
// verify_jwt is ON by default, so only signed-in PocketCare users can call it.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Pinned id (the `-latest` aliases don't always resolve). Override with the
// ASSISTANT_MODEL secret to match whatever your Anthropic account supports.
const DEFAULT_MODEL = "claude-3-5-haiku-20241022";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Always HTTP 200 with the payload in the body (errors carried in an `error`
// field) so the browser's functions.invoke() always gives us the body to read.
function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  
  if (!supabaseUrl || !supabaseServiceKey) return json({ error: "Supabase environment not configured." });
  if (!key) return json({ error: "Assistant is not configured (missing ANTHROPIC_API_KEY)." });

  const supabase = createClient(supabaseUrl, supabaseServiceKey, { db: { schema: "pocketcare" } });
  const { data: { user }, error: authErr } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (authErr || !user) return json({ error: "Unauthorized" });

  // Fetch entitlements to enforce quota
  const { data: entitlement, error: entErr } = await supabase
    .from("entitlements")
    .select("monthly_quota_total, monthly_quota_used, purchased_quota_remaining")
    .eq("user_id", user.id)
    .single();

  if (entErr || !entitlement) {
    return json({ error: "Entitlements not found." });
  }

  const { monthly_quota_total, monthly_quota_used, purchased_quota_remaining } = entitlement;
  const quota = (monthly_quota_total || 0) - (monthly_quota_used || 0) + (purchased_quota_remaining || 0);

  if (quota <= 0) {
    return json({ error: "Quota exceeded. Please upgrade to Premium or purchase a top-up to continue using the AI assistant." });
  }

  let payload: {
    system?: string;
    messages?: unknown[];
    tools?: unknown[];
    model?: string;
    max_tokens?: number;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body." });
  }

  const { system, messages, tools } = payload;
  if (!Array.isArray(messages) || messages.length === 0) {
    return json({ error: "messages[] is required." });
  }

  const model = payload.model || Deno.env.get("ASSISTANT_MODEL") || DEFAULT_MODEL;
  const max_tokens = payload.max_tokens ?? 1024;

  try {
    const res = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({ model, max_tokens, system, messages, tools }),
    });
    const data = await res.json();
    // Surface Anthropic-level errors (e.g. { type: "error", error: {...} }).
    if (!res.ok || data?.type === "error") {
      return json({ error: data?.error?.message || `Anthropic error (${res.status}).` });
    }
    
    await supabase
      .from("entitlements")
      .update({ monthly_quota_used: (monthly_quota_used || 0) + 1 })
      .eq("user_id", user.id);

    return json(data);
  } catch (e) {
    return json({ error: `Upstream error: ${(e as Error).message}` });
  }
});
