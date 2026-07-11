"use client";

import { useEffect, useState } from "react";
import { getAdminFeedback } from "../../../src/admin-actions";
import { Spinner } from "../../../src/ui/Spinner";

export default function AdminFeedback() {
  const [feedback, setFeedback] = useState<any[] | null>(null);
  const [filterKind, setFilterKind] = useState<string>("all");

  useEffect(() => {
    getAdminFeedback().then(setFeedback);
  }, []);

  if (!feedback) return <Spinner />;

  const filtered = feedback.filter((f) => filterKind === "all" || f.kind === filterKind);

  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Beta Tester Feedback</h1>
      
      <div style={{ display: "flex", gap: 10 }}>
        <select 
          value={filterKind} 
          onChange={(e) => setFilterKind(e.target.value)}
          style={{ padding: "10px 14px", borderRadius: 8, border: "1px solid #333", background: "#222", color: "#fff" }}
        >
          <option value="all">All Feedback</option>
          <option value="bug">Bugs</option>
          <option value="suggestion">Suggestions</option>
        </select>
      </div>

      <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", overflow: "hidden" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid #333", background: "#1a1a1a" }}>
              <th style={{ padding: 16 }}>Date</th>
              <th style={{ padding: 16 }}>Kind</th>
              <th style={{ padding: 16 }}>Severity</th>
              <th style={{ padding: 16 }}>Area</th>
              <th style={{ padding: 16 }}>Description</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((f) => (
              <tr key={f.id} style={{ borderBottom: "1px solid #333" }}>
                <td style={{ padding: 16, fontSize: 13, color: "#888", whiteSpace: "nowrap" }}>
                  {new Date(f.created_at).toLocaleDateString()}
                </td>
                <td style={{ padding: 16 }}>
                  <span style={{ 
                    padding: "4px 8px", borderRadius: 4, fontSize: 12, fontWeight: 600,
                    background: f.kind === "bug" ? "var(--warning-soft, #ff444433)" : "var(--accent-ghost)",
                    color: f.kind === "bug" ? "var(--warning, #ff4444)" : "var(--accent)"
                  }}>
                    {f.kind === "bug" ? "Bug" : "Suggestion"}
                  </span>
                </td>
                <td style={{ padding: 16 }}>{f.severity || "—"}</td>
                <td style={{ padding: 16 }}>{f.area || "—"}</td>
                <td style={{ padding: 16, maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {f.description}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filtered.length === 0 && <div style={{ padding: 20, textAlign: "center", color: "#888" }}>No feedback found.</div>}
      </div>
    </div>
  );
}
