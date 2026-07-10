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

// --- Guardrail (mirror of packages/core/guardrail; keep in sync with its tests) ---
const GUARDRAIL_RULES: Array<{ category: string; test: RegExp }> = [
  { category: "injection", test: /\b(ignore|disregard|forget|override|bypass)\b[\s\S]{0,40}\b(previous|prior|above|earlier|all)?\s*(instructions?|rules?|prompt|guidelines?|guardrails?)\b/i },
  { category: "injection", test: /\b(reveal|show|print|repeat|output|display|leak|tell me)\b[\s\S]{0,40}\b(your\s+)?(system\s*prompt|initial\s*instructions?|persona|the\s+(text|prompt)\s+above|hidden\s+(prompt|instructions?))\b/i },
  { category: "injection", test: /\b(you are now|pretend (to be|you)|act as (if|though|an?)|from now on you|developer mode|jailbreak|DAN mode|do anything now|unfiltered|no (restrictions|rules|guardrails))\b/i },
  { category: "injection", test: /(^|\n)\s*(system|assistant|developer)\s*:|<\/?(system|assistant|instructions?)>|\[\/?INST\]|<\|.*?\|>/i },
  { category: "exfiltration", test: /\b(other|another|someone else'?s|every|all|other people'?s)\s+(users?|people|persons?|accounts?|customers?|members?)\b[\s\S]{0,40}\b(data|transactions?|balance|info|records?|passwords?|account)\b/i },
  { category: "exfiltration", test: /(select\s+\*|drop\s+table|delete\s+from|insert\s+into|update\s+.+\s+set|dump (the )?(database|db|table)|raw (sql|query)|union\s+select)/i },
  { category: "exfiltration", test: /\b(list|show|give me|export)\b[\s\S]{0,30}\b(all|every)\s+(users?|accounts?|rows?|records?|customers?)\b/i },
  { category: "secrets", test: /\b(api[_\s-]?key|secret[_\s-]?key|service[_\s-]?role|access[_\s-]?token|bearer\s+token|env(ironment)?\s+(vars?|variables?)|\.env|private\s+key|password|credentials?|connection\s+string)\b/i },
  { category: "secrets", test: /\b(anthropic|openai|supabase|alphavantage|stripe|razorpay)\b[\s\S]{0,20}\b(key|token|secret)\b/i },
  { category: "malware", test: /\b(write|create|generate|build|give me)\b[\s\S]{0,40}\b(malware|ransomware|keylogger|virus|worm|trojan|exploit|(sql|xss|csrf)\s*injection|phishing (page|kit|site)|backdoor|rootkit|botnet|ddos)\b/i },
  { category: "harmful", test: /\b(how (to|do i|can i|would i)\s+(make|build|synthesize|create|obtain|produce)|instructions? for|recipe for|steps? to (make|build|synthesize))\b[\s\S]{0,40}\b(bomb|explosive|nerve agent|bioweapon|chemical weapon|nuclear (device|weapon)|meth(amphetamine)?|napalm|ricin)\b/i },
  { category: "harmful", test: /\b(child|minor|underage|preteen|teen)\b[\s\S]{0,25}\b(sex|sexual|nude|naked|porn|explicit)\b/i },
  { category: "harmful", test: /\b(how (can|do) i|best way to|help me)\b[\s\S]{0,25}\b(kill myself|end my life|commit suicide|overdose|hurt myself)\b/i },
];
const REFUSAL_MESSAGE = "I can only help with your own PocketCare finances — budgets, spending, goals, and the like. I can't help with that request.";
function screenConversation(messages: unknown[]): { allow: boolean; category?: string } {
  const arr = messages as Array<{ role?: string; content?: unknown }>;
  const lastUser = [...arr].reverse().find((m) => m?.role === "user");
  if (!lastUser) return { allow: true };
  const text = (typeof lastUser.content === "string"
    ? lastUser.content
    : Array.isArray(lastUser.content)
      ? lastUser.content.map((b) => (b && typeof b === "object" && "text" in b ? String((b as { text: unknown }).text) : "")).join(" ")
      : "").normalize("NFKC");
  if (!text.trim()) return { allow: true };
  for (const r of GUARDRAIL_RULES) if (r.test.test(text)) return { allow: false, category: r.category };
  return { allow: true };
}
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

  // Defense-in-depth: deterministically refuse prompt-injection / exfiltration /
  // secret-harvesting / malware / harmful classes BEFORE they reach the model.
  // Canonical spec + 50+ tests live in packages/core/guardrail (kept in sync).
  const screen = screenConversation(messages);
  if (!screen.allow) {
    return json({
      content: [{ type: "text", text: REFUSAL_MESSAGE }],
      stop_reason: "guardrail",
      guardrail: { blocked: true, category: screen.category },
    });
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
