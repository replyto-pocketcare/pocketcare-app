"use client";

import { useEffect, useState } from "react";
import { getAdminUsers } from "../../../src/admin-actions";
import { Spinner } from "../../../src/ui/Spinner";

export default function AdminUsers() {
  const [users, setUsers] = useState<any[] | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    getAdminUsers().then(setUsers);
  }, []);

  if (!users) return <Spinner />;

  const filtered = users.filter((u) => 
    (u.email?.toLowerCase().includes(search.toLowerCase())) || 
    (u.display_name?.toLowerCase().includes(search.toLowerCase()))
  );

  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Users & Support</h1>
      
      <div style={{ display: "flex", gap: 10 }}>
        <input 
          type="text" 
          placeholder="Search users..." 
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{ padding: "10px 14px", borderRadius: 8, border: "1px solid #333", background: "#222", color: "#fff", width: 300 }}
        />
      </div>

      <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", overflow: "hidden" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid #333", background: "#1a1a1a" }}>
              <th style={{ padding: 16 }}>ID</th>
              <th style={{ padding: 16 }}>Name</th>
              <th style={{ padding: 16 }}>Email</th>
              <th style={{ padding: 16 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((u) => (
              <tr key={u.id} style={{ borderBottom: "1px solid #333" }}>
                <td style={{ padding: 16, fontSize: 13, color: "#888" }}>{u.id.slice(0, 8)}...</td>
                <td style={{ padding: 16 }}>{u.display_name || "—"}</td>
                <td style={{ padding: 16 }}>{u.email || "—"}</td>
                <td style={{ padding: 16, display: "flex", gap: 8 }}>
                  <button className="btn" style={{ padding: "4px 8px", fontSize: 12, minHeight: 0, height: 28 }}>Support Access</button>
                  <button className="btn ghost" style={{ padding: "4px 8px", fontSize: 12, minHeight: 0, height: 28 }}>Manage</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filtered.length === 0 && <div style={{ padding: 20, textAlign: "center", color: "#888" }}>No users found.</div>}
      </div>
    </div>
  );
}
