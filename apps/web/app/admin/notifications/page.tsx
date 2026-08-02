"use client";

import { useState, useEffect } from "react";
import { getNotificationGroups, sendBroadcastPush } from "../../../src/admin-actions";

export default function AdminNotifications() {
  const [groups, setGroups] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [status, setStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);

  // Form State
  const [groupId, setGroupId] = useState("");
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [body, setBody] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [href, setHref] = useState("");

  useEffect(() => {
    getNotificationGroups().then((res) => {
      if (res.ok) {
        setGroups(res.data);
        if (res.data.length > 0) setGroupId(String(res.data[0].id));
      }
      setLoading(false);
    });
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!groupId || !title) return;
    
    setSending(true);
    setStatus(null);
    
    const res = await sendBroadcastPush({
      group_id: groupId,
      title,
      subtitle: subtitle || undefined,
      body: body || undefined,
      image_url: imageUrl || undefined,
      href: href || undefined,
    });
    
    setSending(false);
    if (res.ok) {
      setStatus({ type: "success", msg: `Successfully queued push to ${res.data.users} members. Sent ${res.data.sent} pushes.` });
      // Reset
      setTitle(""); setSubtitle(""); setBody(""); setImageUrl(""); setHref("");
    } else {
      setStatus({ type: "error", msg: res.error });
    }
  };

  const inputStyle = {
    width: "100%", padding: 12, borderRadius: 8, border: "1px solid #333",
    background: "#111", color: "#fff", marginBottom: 16, fontFamily: "inherit"
  };

  return (
    <div style={{ display: "grid", gap: 30, maxWidth: 600 }}>
      <h1>Broadcast Notifications</h1>
      
      {loading ? (
        <p>Loading groups...</p>
      ) : (
        <form onSubmit={handleSubmit} style={{ background: "#222", borderRadius: 12, border: "1px solid #333", padding: 30 }}>
          <h3 style={{ margin: "0 0 20px" }}>New Broadcast</h3>
          
          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Target Group</label>
          <select 
            value={groupId} 
            onChange={(e) => setGroupId(e.target.value)}
            style={inputStyle}
            required
          >
            {groups.map(g => (
              <option key={String(g.id)} value={String(g.id)}>{g.name} - {g.description}</option>
            ))}
          </select>

          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Title *</label>
          <input 
            type="text" 
            value={title} 
            onChange={(e) => setTitle(e.target.value)} 
            placeholder="e.g. Special Offer!"
            style={inputStyle}
            required
          />

          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Subtitle</label>
          <input 
            type="text" 
            value={subtitle} 
            onChange={(e) => setSubtitle(e.target.value)} 
            placeholder="e.g. 50% off all premium features"
            style={inputStyle}
          />

          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Body</label>
          <textarea 
            value={body} 
            onChange={(e) => setBody(e.target.value)} 
            placeholder="Describe the notification details..."
            style={{ ...inputStyle, minHeight: 100 }}
          />

          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Image URL</label>
          <input 
            type="url" 
            value={imageUrl} 
            onChange={(e) => setImageUrl(e.target.value)} 
            placeholder="https://example.com/image.png"
            style={inputStyle}
          />

          <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Deep Link (Href)</label>
          <input 
            type="text" 
            value={href} 
            onChange={(e) => setHref(e.target.value)} 
            placeholder="e.g. /premium"
            style={inputStyle}
          />

          {status && (
            <div style={{ padding: 12, borderRadius: 8, marginBottom: 16, background: status.type === "error" ? "#4a1212" : "#124a1f", border: `1px solid ${status.type === "error" ? "#f00" : "#0f0"}` }}>
              {status.msg}
            </div>
          )}

          <button 
            type="submit" 
            disabled={sending || !groupId || !title}
            style={{
              padding: "12px 24px", borderRadius: 8, border: "none",
              background: sending ? "#555" : "#cc6644", color: "#fff",
              fontWeight: "bold", cursor: sending ? "not-allowed" : "pointer",
              width: "100%"
            }}
          >
            {sending ? "Broadcasting..." : "Send Broadcast"}
          </button>
        </form>
      )}
    </div>
  );
}
