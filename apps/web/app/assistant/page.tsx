"use client";

import { useRef, useState } from "react";
import { getSupabase } from "../../src/powersync";
import { buildFinancialSummary, type FinancialSummary } from "../../src/assistant/summary";
import { ASSISTANT_TOOLS, executeTool, describeToolCall } from "../../src/assistant/tools";

// ---- Anthropic message shapes (minimal) ----
interface TextBlock { type: "text"; text: string }
interface ToolUseBlock { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
interface ToolResultBlock { type: "tool_result"; tool_use_id: string; content: string }
type ContentBlock = TextBlock | ToolUseBlock | ToolResultBlock;
interface ApiMessage { role: "user" | "assistant"; content: string | ContentBlock[] }

interface UiItem { id: string; role: "user" | "assistant" | "action"; text: string }
interface Pending { msgs: ApiMessage[]; queue: ToolUseBlock[]; results: ToolResultBlock[] }

const uid = () => Math.random().toString(36).slice(2);

function systemPrompt(s: FinancialSummary): string {
  return [
    "You are PocketCare's built-in money-planning assistant. You help the user plan real purchases and savings using their own numbers.",
    `Today is ${s.today}. The user's base currency is ${s.baseCurrency}. All amounts below are in ${s.baseCurrency} major units.`,
    "",
    "The user's aggregated financial snapshot (this is the ONLY data you have — never invent balances):",
    JSON.stringify(s, null, 2),
    "",
    "How to help:",
    `- Give concrete, numeric plans: how much to set aside per month, by when, and from which surplus. Use ${s.baseCurrency}.`,
    "- You do NOT know product prices or sale/festival dates. Ask the user for them, or use a figure they provide.",
    "- Base plans on their real monthly surplus, liquid savings, upcoming obligations, and existing goals.",
    "- You can create goals and budgets and reserve money using the provided tools. Propose the plan in words first, then call the tool. The app will ask the user to confirm before anything actually changes, so it's safe to call a tool once the user agrees.",
    "- Keep replies short and friendly. This is planning help, not investment advice.",
  ].join("\n");
}

export default function AssistantPage() {
  const [ui, setUi] = useState<UiItem[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [pending, setPending] = useState<Pending | null>(null);
  const systemRef = useRef<string>("");
  const apiRef = useRef<ApiMessage[]>([]);

  const pushUi = (role: UiItem["role"], text: string) => setUi((u) => [...u, { id: uid(), role, text }]);

  async function callModel(messages: ApiMessage[]): Promise<{ content?: ContentBlock[]; error?: string }> {
    const { data, error } = await getSupabase().functions.invoke("assistant", {
      body: { system: systemRef.current, messages, tools: ASSISTANT_TOOLS },
    });
    if (error) return { error: error.message };
    return data as { content?: ContentBlock[]; error?: string };
  }

  async function runTurn(messages: ApiMessage[]) {
    setBusy(true);
    let data: { content?: ContentBlock[]; error?: string };
    try {
      data = await callModel(messages);
    } catch (e) {
      data = { error: (e as Error).message };
    }
    setBusy(false);

    if (!data || data.error || !data.content) {
      pushUi("assistant", friendly(data?.error));
      return;
    }
    const content = data.content;
    const withAssistant = [...messages, { role: "assistant" as const, content }];
    apiRef.current = withAssistant;

    const text = content.filter((b): b is TextBlock => b.type === "text").map((b) => b.text).join("\n").trim();
    if (text) pushUi("assistant", text);

    const toolUses = content.filter((b): b is ToolUseBlock => b.type === "tool_use");
    if (toolUses.length === 0) return; // conversation turn complete
    // Every tool is a write → require confirmation before executing.
    setPending({ msgs: withAssistant, queue: toolUses, results: [] });
  }

  async function resolvePending(confirm: boolean) {
    if (!pending) return;
    const [tool, ...rest] = pending.queue;
    if (!tool) return;
    let resultText: string;
    if (confirm) {
      try { resultText = await executeTool(tool.name, tool.input); }
      catch (e) { resultText = `Error: ${(e as Error).message}`; }
      pushUi("action", `✓ ${describeToolCall(tool.name, tool.input)}`);
    } else {
      resultText = "User declined this action.";
      pushUi("action", `✗ Skipped: ${describeToolCall(tool.name, tool.input)}`);
    }
    const results = [...pending.results, { type: "tool_result" as const, tool_use_id: tool.id, content: resultText }];
    if (rest.length === 0) {
      const next = [...pending.msgs, { role: "user" as const, content: results }];
      apiRef.current = next;
      setPending(null);
      await runTurn(next);
    } else {
      setPending({ ...pending, queue: rest, results });
    }
  }

  async function send() {
    const text = input.trim();
    if (!text || busy || pending) return;
    setInput("");
    pushUi("user", text);
    try {
      const summary = await buildFinancialSummary();
      systemRef.current = systemPrompt(summary);
    } catch {
      systemRef.current = "You are PocketCare's money-planning assistant. The user's financial data could not be loaded; ask them for the figures you need.";
    }
    const next: ApiMessage[] = [...apiRef.current, { role: "user", content: text }];
    apiRef.current = next;
    await runTurn(next);
  }

  const currentTool = pending?.queue[0];

  return (
    <div style={{ display: "grid", gap: 16, maxWidth: 760 }} className="fade-up">
      <div>
        <h1>Ask PocketCare</h1>
        <p className="muted" style={{ fontSize: 14, marginTop: 4 }}>
          Plan a purchase or savings goal in plain language. Only an aggregated summary of your finances is shared — never individual transactions.
        </p>
      </div>

      {ui.length === 0 && (
        <div className="card" style={{ padding: 18, display: "grid", gap: 10 }}>
          <span className="muted" style={{ fontSize: 13 }}>Try asking…</span>
          {[
            "I want to buy an iPhone in the Diwali sale — help me plan for it.",
            "Can I afford a ₹40,000 trip in 3 months?",
            "Set up a monthly budget for eating out.",
          ].map((ex) => (
            <button key={ex} className="chip" style={{ textAlign: "left", justifySelf: "start" }} onClick={() => setInput(ex)}>{ex}</button>
          ))}
        </div>
      )}

      <div style={{ display: "grid", gap: 10 }}>
        {ui.map((m) => (
          <div key={m.id} style={{ justifySelf: m.role === "user" ? "end" : "start", maxWidth: "85%" }}>
            {m.role === "action" ? (
              <div className="muted" style={{ fontSize: 13 }}>{m.text}</div>
            ) : (
              <div className="card" style={{
                padding: "10px 14px", whiteSpace: "pre-wrap", lineHeight: 1.5,
                background: m.role === "user" ? "var(--accent)" : "var(--surface)",
                color: m.role === "user" ? "#fff" : "var(--text)",
                borderColor: m.role === "user" ? "var(--accent)" : "var(--border)",
              }}>
                {m.text}
              </div>
            )}
          </div>
        ))}
        {busy && <div className="muted" style={{ fontSize: 13 }}>Thinking…</div>}
      </div>

      {currentTool && (
        <div className="card" style={{ padding: 16, display: "grid", gap: 10, borderColor: "var(--accent-soft)", background: "var(--accent-ghost)" }}>
          <div style={{ fontSize: 14 }}><strong>Confirm action</strong></div>
          <div style={{ fontSize: 14 }}>{describeToolCall(currentTool.name, currentTool.input)}</div>
          <div style={{ display: "flex", gap: 8 }}>
            <button className="btn" onClick={() => resolvePending(true)}>Confirm</button>
            <button className="chip" onClick={() => resolvePending(false)}>Skip</button>
          </div>
        </div>
      )}

      <div style={{ display: "flex", gap: 8, position: "sticky", bottom: 0, background: "var(--bg)", paddingTop: 8 }}>
        <input
          className="input"
          placeholder="Ask about a purchase, goal, or budget…"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") send(); }}
          disabled={busy}
        />
        <button className="btn" onClick={send} disabled={busy || !input.trim() || !!pending}>Send</button>
      </div>
    </div>
  );
}

function friendly(err?: string): string {
  if (!err) return "Sorry — I couldn't get a response. Please try again.";
  if (/not configured|ANTHROPIC/i.test(err)) return "The assistant isn't set up yet on this deployment (the AI key is missing).";
  if (/network|fetch|Failed to send/i.test(err)) return "I couldn't reach the assistant — check your connection and try again.";
  return `Sorry — something went wrong. (${err})`;
}
