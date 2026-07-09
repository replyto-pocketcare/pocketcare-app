"use client";

import { useState } from "react";
import Link from "next/link";
import { useBaseCurrency } from "../../src/hooks";
import { Modal } from "../../src/ui/Modal";
import { useGroups, useConnections } from "../../src/splits/hooks";
import { createGroup } from "../../src/splits/write";

export default function GroupsPage() {
  const base = useBaseCurrency();
  const groups = useGroups();
  const connections = useConnections();

  const [show, setShow] = useState(false);
  const [name, setName] = useState("");
  const [kind, setKind] = useState<"group" | "trip">("trip");
  const [members, setMembers] = useState<string[]>([]);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [auto, setAuto] = useState(false);
  const [busy, setBusy] = useState(false);
  const canAuto = !!start && !!end;

  async function create() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      await createGroup({ name, kind, currency: base, startDate: start || null, endDate: end || null, autoSplit: canAuto && auto, memberUserIds: members });
      setName(""); setMembers([]); setStart(""); setEnd(""); setKind("trip"); setAuto(false);
      setShow(false);
    } finally { setBusy(false); }
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Groups &amp; trips</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <Link href="/friends" className="btn ghost">Friends</Link>
          <button className="btn" onClick={() => setShow(true)}>+ New</button>
        </div>
      </div>

      {groups.length === 0 ? (
        <div className="card" style={{ padding: 32, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>✈</div>
          <h2 style={{ margin: 0 }}>No groups or trips yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Create a trip or group, then invite friends by link. Once they join you can split expenses.</p>
          <button className="btn" onClick={() => setShow(true)}>+ Create your first</button>
        </div>
      ) : (
        <div style={{ display: "grid", gap: 10 }}>
          {groups.map((g) => (
            <Link key={g.id} href={`/groups/${g.id}`} className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
              <div style={{ minWidth: 0 }}>
                <strong>{g.name}</strong><span className="muted" style={{ fontSize: 12 }}> · {g.kind}</span>
                {g.start_date && <div className="muted" style={{ fontSize: 12 }}>{g.start_date}{g.end_date ? ` → ${g.end_date}` : ""}</div>}
              </div>
              <span style={{ color: "var(--accent)" }}>→</span>
            </Link>
          ))}
        </div>
      )}

      <Modal open={show} onClose={() => setShow(false)}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2 style={{ margin: 0 }}>New group / trip</h2>
          <div style={{ display: "flex", gap: 6 }}>
            {(["trip", "group"] as const).map((k) => (
              <button key={k} type="button" className="chip" data-active={k === kind} style={{ textTransform: "capitalize" }} onClick={() => setKind(k)}>{k}</button>
            ))}
          </div>
          <input className="input" placeholder={kind === "trip" ? "Trip name (e.g. Goa)" : "Group name"} value={name} onChange={(e) => setName(e.target.value)} />

          {connections.length > 0 && (
            <>
              <span className="muted" style={{ fontSize: 12 }}>Add existing friends (others you invite by link after)</span>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                {connections.map((c) => {
                  const on = members.includes(c.id);
                  return <button key={c.id} type="button" className="chip" data-active={on} onClick={() => setMembers((m) => on ? m.filter((x) => x !== c.id) : [...m, c.id])}>{c.name}</button>;
                })}
              </div>
            </>
          )}

          <span className="muted" style={{ fontSize: 12 }}>Dates (optional)</span>
          <div style={{ display: "flex", gap: 8 }}>
            <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end && e.target.value > end) setEnd(e.target.value); }} />
            <input className="input" type="date" min={start || undefined} value={end} onChange={(e) => setEnd(e.target.value)} />
          </div>
          <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 14, opacity: canAuto ? 1 : 0.5 }}>
            <input type="checkbox" checked={canAuto && auto} disabled={!canAuto} onChange={(e) => setAuto(e.target.checked)} />
            Auto-split: any expense I add within these dates splits equally with this {kind}
          </label>

          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
            <button className="btn ghost" onClick={() => setShow(false)}>Cancel</button>
            <button className="btn" onClick={() => void create()} disabled={busy || !name.trim()}>{busy ? "Creating…" : "Create"}</button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
