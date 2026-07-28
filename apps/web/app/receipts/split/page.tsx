"use client";

/**
 * Per-item split assignment — "who had what".
 *
 * One card per line. Tap faces to include people; pick how that line divides.
 * Tax, service charge and tip default to `proportional` (allocated by what each
 * person actually ate), which is the fair answer often enough that most people
 * never touch it — but can be overridden per charge, because "the service
 * charge was for the table" is just as common.
 *
 * Nothing saves until every line is assigned and every exact/percent split
 * validates, so the expense that reaches the ledger is always balanced.
 */
import { Suspense, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { useQuery } from "@powersync/react";
import { money } from "@pocketcare/money";
import {
  allocateReceipt,
  AllocationError,
  isCharge,
  qtyToMajor,
  QTY_SCALE,
  PERCENT_SCALE,
  type ItemSplitMode,
  type LineAssignment,
  type ReceiptDraft,
  type ReceiptLine,
} from "@pocketcare/receipts";

import { useMoneyFmt } from "../../../src/ui/Money";
import { Spinner } from "../../../src/ui/Spinner";
import { useGroup, useGroupMemberIds, useMyUserId, useUserProfiles } from "../../../src/splits/hooks";
import { createSplitExpenseItemized } from "../../../src/splits/writeItemized";
import { linkScan } from "../../../src/receipts/scan";
import { digitsFor, toMajorString, toMinor } from "../../../src/receipts/draft";

/** Modes offered for goods. `quantity` only appears when there is a quantity. */
const ITEM_MODES: readonly ItemSplitMode[] = ["equal", "quantity", "exact", "percent"];
const CHARGE_MODES: readonly ItemSplitMode[] = ["proportional", "equal", "exact", "percent"];

interface LineState {
  mode: ItemSplitMode;
  /** userId -> raw input string (meaning depends on mode). */
  weights: Record<string, string>;
  members: string[];
}

export default function SplitReceiptPage() {
  return (
    <Suspense fallback={<Spinner />}>
      <SplitInner />
    </Suspense>
  );
}

function SplitInner() {
  const { t } = useTranslation("receipts");
  const router = useRouter();
  const params = useSearchParams();
  const scanId = params.get("scan") ?? "";
  const groupId = params.get("group") ?? "";
  const accountId = params.get("account") ?? "";
  const categoryId = params.get("category") ?? "";

  const fmt = useMoneyFmt();
  const me = useMyUserId();
  const group = useGroup(groupId);
  const memberIds = useGroupMemberIds(groupId);
  const profiles = useUserProfiles();

  const { data: scans = [], isLoading } = useQuery<{ parsed_json: string | null }>(
    "SELECT parsed_json FROM receipt_scans WHERE id = ? AND deleted_at IS NULL",
    [scanId],
  );

  const [draft, setDraft] = useState<ReceiptDraft | null>(null);
  const [state, setState] = useState<Record<string, LineState>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (draft || scans.length === 0) return;
    const raw = scans[0]?.parsed_json;
    if (!raw) return;
    try {
      setDraft(JSON.parse(raw) as ReceiptDraft);
    } catch {
      setError(t("split.corrupt", "We couldn't reopen this scan."));
    }
  }, [scans, draft, t]);

  // Seed every line with "everyone, split the obvious way" so the screen is
  // usable immediately and the user only edits the exceptions.
  useEffect(() => {
    if (!draft || memberIds.length === 0 || Object.keys(state).length > 0) return;
    const seeded: Record<string, LineState> = {};
    for (const line of draft.lines) {
      seeded[line.id] = {
        mode: isCharge(line.kind) ? "proportional" : "equal",
        members: [...memberIds],
        weights: {},
      };
    }
    setState(seeded);
  }, [draft, memberIds, state]);

  const digits = digitsFor(draft?.currency ?? "INR");
  const cur = (draft?.currency ?? "INR") as Parameters<typeof money>[1];
  const nameOf = (id: string) =>
    id === me ? t("split.you", "You") : profiles.get(id)?.name ?? t("split.someone", "Member");

  /** Build the package's assignment structures from the UI state. */
  const assignments: LineAssignment[] = useMemo(() => {
    if (!draft) return [];
    return draft.lines.map((line) => {
      const s = state[line.id];
      if (!s) return { lineId: line.id, mode: "equal", shares: [] };
      return {
        lineId: line.id,
        mode: s.mode,
        shares: s.members.map((userId) => ({
          userId,
          weight: weightFor(s, userId, line, digits),
        })),
      };
    });
  }, [draft, state, digits]);

  /** Live allocation. An error here is a validation message, not a crash. */
  const allocation = useMemo(() => {
    if (!draft || draft.lines.length === 0) return null;
    try {
      return { ok: true as const, value: allocateReceipt(draft.lines, assignments) };
    } catch (e) {
      return {
        ok: false as const,
        message: e instanceof AllocationError ? e.message : (e as Error).message,
      };
    }
  }, [draft, assignments]);

  const perLineValid = useMemo(() => {
    const out: Record<string, string | null> = {};
    if (!draft) return out;
    for (const line of draft.lines) {
      out[line.id] = validateLine(line, state[line.id], digits, t);
    }
    return out;
  }, [draft, state, digits, t]);

  const firstProblem = draft?.lines.find((l) => perLineValid[l.id]);
  const canSave = !!draft && !firstProblem && allocation?.ok === true && !saving && !!accountId;

  if (isLoading && !draft) return <Spinner />;
  if (!draft) {
    return <div className="card" style={{ padding: 20 }}>{error ?? t("split.notFound", "That scan is no longer available.")}</div>;
  }

  const setLine = (lineId: string, patch: Partial<LineState>) =>
    setState((prev) => ({ ...prev, [lineId]: { ...prev[lineId]!, ...patch } }));

  const toggleMember = (lineId: string, userId: string) => {
    const s = state[lineId];
    if (!s) return;
    const has = s.members.includes(userId);
    // A line must belong to somebody — refuse to empty the last one.
    if (has && s.members.length === 1) return;
    setLine(lineId, {
      members: has ? s.members.filter((m) => m !== userId) : [...s.members, userId],
    });
  };

  const applyToAll = (members: string[]) => {
    setState((prev) => {
      const next: Record<string, LineState> = {};
      for (const [id, s] of Object.entries(prev)) next[id] = { ...s, members: [...members], weights: {} };
      return next;
    });
  };

  async function save() {
    if (!draft || !allocation?.ok) return;
    setSaving(true);
    setError(null);
    try {
      const expenseId = await createSplitExpenseItemized({
        groupId,
        draft,
        assignments,
        // The scanner flow assumes you paid the whole bill; multi-payer stays
        // in the richer add-transaction editor.
        payers: [{ userId: me, paid: allocation.value.total, accountId }],
        categoryId: categoryId || null,
        occurredAt: draft.occurredAt ?? new Date().toISOString().slice(0, 10),
      });
      await linkScan(scanId, { expenseId });
      router.push(`/groups/${groupId}`);
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  }

  return (
    <div style={{ display: "grid", gap: 16, maxWidth: 820, paddingBottom: 96 }}>
      <div>
        <h1 style={{ margin: 0 }}>{t("split.title", "Who had what?")}</h1>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {t("split.intro", "Assign each item, then choose how tax and service charge are shared.")}
          {group ? ` · ${group.name}` : ""}
        </p>
      </div>

      {/* ---- bulk helpers ---- */}
      <section className="card" style={{ padding: 14, display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <span className="muted" style={{ fontSize: 12 }}>{t("split.quick", "Quick set:")}</span>
        <button className="chip" type="button" onClick={() => applyToAll(memberIds)}>
          {t("split.everyoneAll", "Everyone on everything")}
        </button>
        <button className="chip" type="button" onClick={() => applyToAll([me])}>
          {t("split.onlyMe", "Only me")}
        </button>
      </section>

      {/* ---- one card per line ---- */}
      {draft.lines.map((line) => {
        const s = state[line.id];
        if (!s) return null;
        const modes = isCharge(line.kind)
          ? CHARGE_MODES
          : ITEM_MODES.filter((m) => m !== "quantity" || (line.quantity ?? 0) > 0);
        const shares = allocation?.ok ? allocation.value.perLine.get(line.id) ?? [] : [];
        const problem = perLineValid[line.id];

        return (
          <section key={line.id} className="card" style={{ padding: 16, display: "grid", gap: 12, minWidth: 0 }}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "baseline", flexWrap: "wrap" }}>
              <div style={{ minWidth: 0 }}>
                <strong style={{ fontSize: 15, display: "block", lineHeight: 1.4 }}>
                  {line.description || t(`kind.${line.kind}`, line.kind)}
                </strong>
                {/* The kind used to be a `.chip`, which was wrong twice over:
                    a chip reads as tappable when this is a static label, and an
                    inline element's vertical padding does NOT grow its line
                    box, so it bled upward and clipped the heading above.
                    A plain uppercase caption fixes both. */}
                {(isCharge(line.kind) || line.quantity !== null) && (
                  <div
                    className="muted"
                    style={{ display: "flex", gap: 6, flexWrap: "wrap", fontSize: 11.5, lineHeight: 1.5, marginTop: 2 }}
                  >
                    {isCharge(line.kind) && (
                      <span style={{ textTransform: "uppercase", letterSpacing: "0.05em", fontWeight: 600 }}>
                        {t(`kind.${line.kind}`, line.kind)}
                      </span>
                    )}
                    {isCharge(line.kind) && line.quantity !== null && <span aria-hidden>·</span>}
                    {line.quantity !== null && (
                      <span>
                        {t("split.qtyLabel", "{{qty}}{{unit}}", {
                          qty: qtyToMajor(line.quantity),
                          unit: line.unit ? ` ${line.unit}` : "",
                        })}
                      </span>
                    )}
                  </div>
                )}
              </div>
              <strong style={{ fontVariantNumeric: "tabular-nums" }}>{fmt(money(line.amount, cur))}</strong>
            </div>

            {/* participants */}
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {memberIds.map((uid) => (
                <button
                  key={uid}
                  type="button"
                  className="chip"
                  data-active={s.members.includes(uid)}
                  aria-pressed={s.members.includes(uid)}
                  onClick={() => toggleMember(line.id, uid)}
                  style={{ minHeight: 36 }}
                >
                  {nameOf(uid)}
                </button>
              ))}
            </div>

            {/* mode */}
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {modes.map((m) => (
                <button
                  key={m}
                  type="button"
                  className="chip"
                  data-active={s.mode === m}
                  onClick={() => setLine(line.id, { mode: m, weights: {} })}
                  style={{ minHeight: 36 }}
                >
                  {t(`mode.${m}`, m)}
                </button>
              ))}
            </div>

            {/* per-person inputs for the modes that need them */}
            {(s.mode === "exact" || s.mode === "percent" || s.mode === "quantity") && (
              <div style={{ display: "grid", gap: 8 }}>
                {s.members.map((uid) => (
                  <label
                    key={uid}
                    style={{ display: "flex", gap: 10, alignItems: "center", justifyContent: "space-between", fontSize: 14 }}
                  >
                    <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" }}>{nameOf(uid)}</span>
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                      <input
                        className="input"
                        inputMode="decimal"
                        style={{ width: 110, textAlign: "right" }}
                        value={s.weights[uid] ?? ""}
                        placeholder={s.mode === "percent" ? "0" : s.mode === "quantity" ? "0" : toMajorString(0, digits)}
                        onChange={(e) =>
                          setLine(line.id, { weights: { ...s.weights, [uid]: e.target.value } })
                        }
                        aria-label={`${nameOf(uid)} — ${t(`mode.${s.mode}`, s.mode)}`}
                      />
                      <span className="muted" style={{ fontSize: 12, width: 24 }}>
                        {s.mode === "percent" ? "%" : s.mode === "quantity" ? (line.unit ?? "×") : ""}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
            )}

            {/* resolved amounts / validation */}
            {problem ? (
              <div style={{ fontSize: 12.5, color: "var(--negative)" }}>{problem}</div>
            ) : (
              <div className="muted" style={{ fontSize: 12.5, display: "flex", gap: 10, flexWrap: "wrap" }}>
                {shares.map((sh) => (
                  <span key={sh.userId}>
                    {nameOf(sh.userId)} {fmt(money(sh.amount, cur))}
                  </span>
                ))}
              </div>
            )}
          </section>
        );
      })}

      {/* ---- sticky summary ----
          Sits on the page background (not the surface colour) so the card
          inside reads as a card, matching the line cards above rather than
          looking like a cut-off strip. */}
      <div
        style={{
          position: "sticky",
          bottom: 0,
          zIndex: 5,
          paddingTop: 8,
          paddingBottom: 8,
          background: "linear-gradient(to top, var(--bg) 72%, transparent)",
        }}
      >
        <section
          className="card"
          style={{ padding: 16, display: "grid", gap: 12, boxShadow: "var(--shadow-lg)" }}
        >
          {allocation?.ok ? (
            <>
              {/* Per-person tiles. A row of "Name: ₹x" runs together at a glance;
                  stacking the label over the amount makes each person scannable. */}
              <div
                style={{
                  display: "grid",
                  gap: 8,
                  gridTemplateColumns: "repeat(auto-fit, minmax(min(120px, 100%), 1fr))",
                }}
              >
                {memberIds.map((uid) => {
                  const isMe = uid === me;
                  return (
                    <div
                      key={uid}
                      style={{
                        display: "grid",
                        gap: 2,
                        padding: "8px 10px",
                        borderRadius: 10,
                        minWidth: 0,
                        background: isMe ? "var(--accent-ghost)" : "var(--surface-2)",
                        border: `1px solid ${isMe ? "var(--accent-soft)" : "transparent"}`,
                      }}
                    >
                      <span
                        className="muted"
                        style={{
                          fontSize: 11.5,
                          whiteSpace: "nowrap",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                        }}
                      >
                        {nameOf(uid)}
                      </span>
                      <strong style={{ fontSize: 15, fontVariantNumeric: "tabular-nums" }}>
                        {fmt(money(allocation.value.byUser.get(uid) ?? 0, cur))}
                      </strong>
                    </div>
                  );
                })}
              </div>

              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "baseline",
                  gap: 12,
                  paddingTop: 10,
                  borderTop: "1px solid var(--border)",
                }}
              >
                <span className="muted" style={{ fontSize: 13 }}>{t("split.total", "Total")}</span>
                <strong style={{ fontSize: 17, fontVariantNumeric: "tabular-nums" }}>
                  {fmt(money(allocation.value.total, cur))}
                </strong>
              </div>
            </>
          ) : (
            <div style={{ fontSize: 13, color: "var(--negative)" }}>
              {firstProblem
                ? t("split.fixLines", "Fix the highlighted lines to continue.")
                : allocation?.message}
            </div>
          )}

          {error && <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>}

          <button
            className="btn"
            type="button"
            disabled={!canSave}
            onClick={() => void save()}
            style={{ width: "100%", justifyContent: "center" }}
          >
            {saving ? <Spinner /> : null}
            {t("split.save", "Save split")}
          </button>
        </section>
      </div>
    </div>
  );
}

/** Translate a raw input string into the weight the allocator expects. */
function weightFor(s: LineState, userId: string, line: ReceiptLine, digits: number): number | undefined {
  const raw = s.weights[userId];
  if (s.mode === "equal" || s.mode === "proportional") return undefined;
  if (raw === undefined || raw.trim() === "") return 0;
  if (s.mode === "exact") {
    // Exact weights are minor units and must carry the line's sign so a
    // discount can be split exactly too.
    const v = toMinor(raw, digits);
    return line.amount < 0 ? -Math.abs(v) : v;
  }
  const n = Number.parseFloat(raw.replace(",", "."));
  if (!Number.isFinite(n) || n < 0) return 0;
  return s.mode === "percent" ? Math.round(n * PERCENT_SCALE) : Math.round(n * QTY_SCALE);
}

/** Human validation message for one line, or null when it's fine. */
function validateLine(
  line: ReceiptLine,
  s: LineState | undefined,
  digits: number,
  t: TFunction<"receipts">,
): string | null {
  if (!s || s.members.length === 0) {
    return t("split.needsSomeone", { defaultValue: "Pick who this is for." });
  }
  if (s.mode === "exact") {
    const sum = s.members.reduce((acc, uid) => {
      const v = toMinor(s.weights[uid] ?? "", digits);
      return acc + (line.amount < 0 ? -Math.abs(v) : v);
    }, 0);
    if (sum !== line.amount) {
      const diff = (line.amount - sum) / 10 ** digits;
      return t("split.exactMismatch", {
        defaultValue: "Shares are off by {{diff}}.",
        diff: diff.toFixed(digits),
      });
    }
  }
  if (s.mode === "percent") {
    const sum = s.members.reduce((acc, uid) => {
      const n = Number.parseFloat((s.weights[uid] ?? "").replace(",", "."));
      return acc + (Number.isFinite(n) ? n : 0);
    }, 0);
    if (Math.round(sum) !== 100) {
      return t("split.percentMismatch", { defaultValue: "Percentages add up to {{pct}}%, not 100%.", pct: Math.round(sum) });
    }
  }
  if (s.mode === "quantity" && line.quantity !== null) {
    const sum = s.members.reduce((acc, uid) => {
      const n = Number.parseFloat((s.weights[uid] ?? "").replace(",", "."));
      return acc + (Number.isFinite(n) ? n : 0);
    }, 0);
    if (Math.round(sum * QTY_SCALE) !== line.quantity) {
      return t("split.qtyMismatch", {
        defaultValue: "Quantities add up to {{got}}, not {{want}}.",
        got: sum,
        want: qtyToMajor(line.quantity),
      });
    }
  }
  return null;
}
