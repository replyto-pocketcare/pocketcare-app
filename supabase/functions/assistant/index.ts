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

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-3-5-haiku-latest";

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

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "Assistant is not configured (missing ANTHROPIC_API_KEY)." });

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
    return json(data);
  } catch (e) {
    return json({ error: `Upstream error: ${(e as Error).message}` });
  }
});
