/**
 * @pocketcare/guardrail — deterministic pre-flight screening for the AI
 * assistant. This is a defense-in-depth layer that runs BEFORE the model call:
 * it deterministically rejects the classes of prompt we never want to reach the
 * LLM (prompt injection, data exfiltration, secret/credential harvesting,
 * malware/code generation, and clearly harmful requests). The model's own
 * persona still refuses nuanced off-topic asks; this layer makes the dangerous
 * classes non-negotiable and, crucially, unit-testable in CI.
 *
 * It must stay pure (no I/O) so it can run identically in the Edge Function
 * (Deno) and in tests (Node).
 */

export type GuardrailCategory =
  | "injection" // attempts to override/reveal system instructions
  | "exfiltration" // attempts to read other users' or raw DB data
  | "secrets" // attempts to extract API keys / tokens / env
  | "malware" // requests to write exploits / malicious code
  | "harmful"; // weapons, CSAM, self-harm facilitation, etc.

export interface GuardrailResult {
  allow: boolean;
  category?: GuardrailCategory;
  reason?: string;
}

interface Rule {
  category: GuardrailCategory;
  reason: string;
  test: RegExp;
}

// Each rule is intentionally narrow to avoid false positives on real financial
// questions. Ordering is priority order (first match wins).
const RULES: Rule[] = [
  // --- prompt injection / instruction override / prompt disclosure ---
  { category: "injection", reason: "Attempt to override system instructions.", test: /\b(ignore|disregard|forget|override|bypass)\b[\s\S]{0,40}\b(previous|prior|above|earlier|all)?\s*(instructions?|rules?|prompt|guidelines?|guardrails?)\b/i },
  { category: "injection", reason: "Attempt to reveal the system prompt.", test: /\b(reveal|show|print|repeat|output|display|leak|tell me)\b[\s\S]{0,40}\b(your\s+)?(system\s*prompt|initial\s*instructions?|persona|the\s+(text|prompt)\s+above|hidden\s+(prompt|instructions?))\b/i },
  { category: "injection", reason: "Jailbreak / role-override attempt.", test: /\b(you are now|pretend (to be|you)|act as (if|though|an?)|from now on you|developer mode|jailbreak|DAN mode|do anything now|unfiltered|no (restrictions|rules|guardrails))\b/i },
  { category: "injection", reason: "Injected control tokens / fake roles.", test: /(^|\n)\s*(system|assistant|developer)\s*:|<\/?(system|assistant|instructions?)>|\[\/?INST\]|<\|.*?\|>/i },

  // --- data exfiltration (other users / raw DB) ---
  { category: "exfiltration", reason: "Attempt to access other users' data.", test: /\b(other|another|someone else'?s|every|all|other people'?s)\s+(users?|people|persons?|accounts?|customers?|members?)\b[\s\S]{0,40}\b(data|transactions?|balance|info|records?|passwords?|account)\b/i },
  { category: "exfiltration", reason: "Attempt to run raw database queries / dumps.", test: /(select\s+\*|drop\s+table|delete\s+from|insert\s+into|update\s+.+\s+set|dump (the )?(database|db|table)|raw (sql|query)|union\s+select)/i },
  { category: "exfiltration", reason: "Attempt to enumerate the whole database.", test: /\b(list|show|give me|export)\b[\s\S]{0,30}\b(all|every)\s+(users?|accounts?|rows?|records?|customers?)\b/i },

  // --- secret / credential harvesting ---
  { category: "secrets", reason: "Attempt to extract secrets or credentials.", test: /\b(api[_\s-]?key|secret[_\s-]?key|service[_\s-]?role|access[_\s-]?token|bearer\s+token|env(ironment)?\s+(vars?|variables?)|\.env|private\s+key|password|credentials?|connection\s+string)\b/i },
  { category: "secrets", reason: "Attempt to read server configuration.", test: /\b(anthropic|openai|supabase|alphavantage|stripe|razorpay)\b[\s\S]{0,20}\b(key|token|secret)\b/i },

  // --- malware / exploit code generation ---
  { category: "malware", reason: "Request to generate malicious code.", test: /\b(write|create|generate|build|give me)\b[\s\S]{0,40}\b(malware|ransomware|keylogger|virus|worm|trojan|exploit|(sql|xss|csrf)\s*injection|phishing (page|kit|site)|backdoor|rootkit|botnet|ddos)\b/i },

  // --- harmful content ---
  { category: "harmful", reason: "Request facilitating weapons of mass harm.", test: /\b(how (to|do i|can i|would i|to i)\s+(make|build|synthesize|create|obtain|produce)|instructions? for|recipe for|steps? to (make|build|synthesize))\b[\s\S]{0,40}\b(bomb|explosive|nerve agent|bioweapon|chemical weapon|nuclear (device|weapon)|meth(amphetamine)?|napalm|ricin)\b/i },
  { category: "harmful", reason: "Request involving sexual content with minors.", test: /\b(child|minor|underage|preteen|teen)\b[\s\S]{0,25}\b(sex|sexual|nude|naked|porn|explicit)\b/i },
  { category: "harmful", reason: "Request facilitating self-harm.", test: /\b(how (can|do) i|best way to|help me)\b[\s\S]{0,25}\b(kill myself|end my life|commit suicide|overdose|hurt myself)\b/i },
];

/**
 * Screen a user prompt. Returns `{ allow: false, category, reason }` for any
 * disallowed class, else `{ allow: true }`. Empty/whitespace input is allowed
 * (the model handles empty turns). Never throws.
 */
export function screenPrompt(input: string | null | undefined): GuardrailResult {
  const text = (input ?? "").normalize("NFKC");
  if (!text.trim()) return { allow: true };
  for (const rule of RULES) {
    if (rule.test.test(text)) return { allow: false, category: rule.category, reason: rule.reason };
  }
  return { allow: true };
}

/** Convenience: the single most-recent user message from a messages array. */
export function screenConversation(messages: Array<{ role: string; content: unknown }>): GuardrailResult {
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  if (!lastUser) return { allow: true };
  const text = typeof lastUser.content === "string"
    ? lastUser.content
    : Array.isArray(lastUser.content)
      ? lastUser.content.map((b) => (typeof b === "object" && b && "text" in b ? String((b as { text: unknown }).text) : "")).join(" ")
      : "";
  return screenPrompt(text);
}

/** Standard refusal message shown when the guardrail blocks a prompt. */
export const REFUSAL_MESSAGE =
  "I can only help with your own PocketCare finances — budgets, spending, goals, and the like. I can't help with that request.";
