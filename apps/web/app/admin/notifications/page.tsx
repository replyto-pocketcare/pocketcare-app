"use client";

import { useState, useEffect } from "react";
import { getAudienceGroups, sendBroadcastPush, createAudienceGroup, addUsersToGroupByEmail, addUsersToGroupByDemographics, getGroupMembers, GroupMember } from "../../../src/admin-actions";

export default function AdminNotifications() {
  const [groups, setGroups] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  
  // Group Selection
  const [groupId, setGroupId] = useState("");

  // Broadcast State
  const [sending, setSending] = useState(false);
  const [status, setStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [body, setBody] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [href, setHref] = useState("");

  // Create Group State
  const [creatingGroup, setCreatingGroup] = useState(false);
  const [groupStatus, setGroupStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);
  const [newGroupName, setNewGroupName] = useState("");
  const [newGroupDesc, setNewGroupDesc] = useState("");

  // Manage Members State
  const [addingMembers, setAddingMembers] = useState(false);
  const [memberStatus, setMemberStatus] = useState<{ type: "success" | "error"; msg: string } | null>(null);
  const [emails, setEmails] = useState("");
  const [country, setCountry] = useState("");
  const [gender, setGender] = useState("");
  const [ipRegion, setIpRegion] = useState("");

  const [groupMembers, setGroupMembers] = useState<GroupMember[] | null>(null);
  const [loadingMembers, setLoadingMembers] = useState(false);

  const loadGroups = async () => {
    const res = await getAudienceGroups();
    if (res.ok) {
      setGroups(res.data);
      if (res.data.length > 0 && !groupId) setGroupId(String(res.data[0].id));
    }
    setLoading(false);
  };

  useEffect(() => {
    loadGroups();
  }, []);

  useEffect(() => {
    setGroupMembers(null);
  }, [groupId]);

  const loadMembers = async () => {
    if (!groupId) return;
    setLoadingMembers(true);
    const res = await getGroupMembers(groupId);
    setLoadingMembers(false);
    if (res.ok) {
      setGroupMembers(res.data);
    } else {
      setMemberStatus({ type: "error", msg: res.error });
    }
  };

  const handleBroadcastSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!groupId || !title) return;
    setSending(true); setStatus(null);
    const res = await sendBroadcastPush({ group_id: groupId, title, subtitle: subtitle || undefined, body: body || undefined, image_url: imageUrl || undefined, href: href || undefined });
    setSending(false);
    if (res.ok) {
      setStatus({ type: "success", msg: `Successfully queued push to ${res.data.users} members. Sent ${res.data.sent} pushes.` });
      setTitle(""); setSubtitle(""); setBody(""); setImageUrl(""); setHref("");
    } else {
      setStatus({ type: "error", msg: res.error });
    }
  };

  const handleCreateGroupSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newGroupName) return;
    setCreatingGroup(true); setGroupStatus(null);
    const res = await createAudienceGroup(newGroupName, newGroupDesc);
    setCreatingGroup(false);
    if (res.ok) {
      setGroupStatus({ type: "success", msg: `Group "${res.data.name}" created successfully.` });
      setNewGroupName(""); setNewGroupDesc("");
      loadGroups();
    } else {
      setGroupStatus({ type: "error", msg: res.error });
    }
  };

  const handleAddByEmail = async () => {
    if (!groupId || !emails) return;
    setAddingMembers(true); setMemberStatus(null);
    const emailList = emails.split(",").map(e => e.trim()).filter(Boolean);
    const res = await addUsersToGroupByEmail(groupId, emailList);
    setAddingMembers(false);
    if (res.ok) {
      setMemberStatus({ type: "success", msg: `Successfully added ${res.data} matching users to the group.` });
      setEmails("");
    } else {
      setMemberStatus({ type: "error", msg: res.error });
    }
  };

  const handleAddByDemographics = async () => {
    if (!groupId || (!country && !gender && !ipRegion)) return;
    setAddingMembers(true); setMemberStatus(null);
    const filters = {
      country: country || undefined,
      gender: gender || undefined,
      ip_region: ipRegion || undefined
    };
    const res = await addUsersToGroupByDemographics(groupId, filters);
    setAddingMembers(false);
    if (res.ok) {
      setMemberStatus({ type: "success", msg: `Successfully added ${res.data} matching users to the group.` });
      setCountry(""); setGender(""); setIpRegion("");
    } else {
      setMemberStatus({ type: "error", msg: res.error });
    }
  };

  const inputStyle = { width: "100%", padding: 12, borderRadius: 8, border: "1px solid #333", background: "#111", color: "#fff", marginBottom: 16, fontFamily: "inherit" };
  const buttonStyle = (active: boolean) => ({ padding: "12px 24px", borderRadius: 8, border: "none", background: active ? "#555" : "#cc6644", color: "#fff", fontWeight: "bold", cursor: active ? "not-allowed" : "pointer", width: "100%" });

  const StatusBox = ({ s }: { s: { type: "success" | "error"; msg: string } | null }) => s ? (
    <div style={{ padding: 12, borderRadius: 8, marginBottom: 16, background: s.type === "error" ? "#4a1212" : "#124a1f", border: `1px solid ${s.type === "error" ? "#f00" : "#0f0"}` }}>{s.msg}</div>
  ) : null;

  return (
    <div style={{ display: "grid", gap: 30, maxWidth: 600 }}>
      <h1>Notifications Manager</h1>
      
      {loading ? (
        <p>Loading...</p>
      ) : (
        <>
          {/* Create Group Form */}
          <form onSubmit={handleCreateGroupSubmit} style={{ background: "#222", borderRadius: 12, border: "1px solid #333", padding: 30 }}>
            <h3 style={{ margin: "0 0 20px" }}>1. Create Notification Group</h3>
            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Group Name *</label>
            <input type="text" value={newGroupName} onChange={(e) => setNewGroupName(e.target.value)} placeholder="e.g. Beta Testers" style={inputStyle} required />
            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Description</label>
            <input type="text" value={newGroupDesc} onChange={(e) => setNewGroupDesc(e.target.value)} placeholder="e.g. Users testing unreleased features" style={inputStyle} />
            <StatusBox s={groupStatus} />
            <button type="submit" disabled={creatingGroup || !newGroupName} style={buttonStyle(creatingGroup)}>{creatingGroup ? "Creating..." : "Create Group"}</button>
          </form>

          {/* Manage Members Form */}
          <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", padding: 30 }}>
            <h3 style={{ margin: "0 0 20px" }}>2. Manage Group Members</h3>
            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Select Group</label>
            <select value={groupId} onChange={(e) => setGroupId(e.target.value)} style={inputStyle}>
              {groups.map(g => <option key={String(g.id)} value={String(g.id)}>{g.name} - {g.description}</option>)}
            </select>

            {groupId && (
              <div style={{ display: "grid", gap: 20, marginTop: 10 }}>
                <div style={{ padding: 16, border: "1px solid #444", borderRadius: 8, background: "#1a1a1a" }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
                    <h4 style={{ margin: 0 }}>View Members</h4>
                    <button type="button" onClick={loadMembers} disabled={loadingMembers} style={{ padding: "6px 12px", borderRadius: 4, background: "#444", border: "none", color: "#fff", cursor: loadingMembers ? "not-allowed" : "pointer" }}>{loadingMembers ? "Loading..." : "Load Members"}</button>
                  </div>
                  {groupMembers && (
                    <div style={{ maxHeight: 200, overflowY: "auto", borderTop: "1px solid #333", paddingTop: 10 }}>
                      {groupMembers.length === 0 ? <p style={{ fontSize: 14, color: "#999" }}>No members in this group.</p> : (
                        <ul style={{ margin: 0, padding: 0, listStyle: "none" }}>
                          {groupMembers.map(m => (
                            <li key={m.user_id} style={{ padding: "6px 0", borderBottom: "1px solid #222", fontSize: 14 }}>
                              <strong style={{ color: "#eee" }}>{m.name}</strong> {m.email ? `<${m.email}>` : ""}
                            </li>
                          ))}
                        </ul>
                      )}
                    </div>
                  )}
                </div>

                <div style={{ padding: 16, border: "1px solid #444", borderRadius: 8, background: "#1a1a1a" }}>
                  <h4 style={{ margin: "0 0 10px" }}>Add by Email</h4>
                  <textarea value={emails} onChange={(e) => setEmails(e.target.value)} placeholder="user1@app.com, user2@app.com" style={{ ...inputStyle, minHeight: 60, marginBottom: 10 }} />
                  <button type="button" onClick={handleAddByEmail} disabled={addingMembers || !emails} style={buttonStyle(addingMembers || !emails)}>Add Users by Email</button>
                </div>

                <div style={{ padding: 16, border: "1px solid #444", borderRadius: 8, background: "#1a1a1a" }}>
                  <h4 style={{ margin: "0 0 10px" }}>Add by Demographics</h4>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                    <div>
                      <label style={{ fontSize: 12, display: "block", marginBottom: 4 }}>Country</label>
                      <input type="text" value={country} onChange={(e) => setCountry(e.target.value)} placeholder="e.g. IN, US" style={{...inputStyle, marginBottom: 10}} />
                    </div>
                    <div>
                      <label style={{ fontSize: 12, display: "block", marginBottom: 4 }}>Gender</label>
                      <input type="text" value={gender} onChange={(e) => setGender(e.target.value)} placeholder="e.g. female, male" style={{...inputStyle, marginBottom: 10}} />
                    </div>
                  </div>
                  <div>
                    <label style={{ fontSize: 12, display: "block", marginBottom: 4 }}>IP Region</label>
                    <input type="text" value={ipRegion} onChange={(e) => setIpRegion(e.target.value)} placeholder="e.g. Maharashtra" style={{...inputStyle, marginBottom: 10}} />
                  </div>
                  <button type="button" onClick={handleAddByDemographics} disabled={addingMembers || (!country && !gender && !ipRegion)} style={buttonStyle(addingMembers || (!country && !gender && !ipRegion))}>Bulk Add by Demographics</button>
                </div>
              </div>
            )}
            <div style={{ marginTop: 16 }}><StatusBox s={memberStatus} /></div>
          </div>

          {/* Broadcast Form */}
          <form onSubmit={handleBroadcastSubmit} style={{ background: "#222", borderRadius: 12, border: "1px solid #333", padding: 30 }}>
            <h3 style={{ margin: "0 0 20px" }}>3. New Broadcast</h3>
            
            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Target Group</label>
            <select value={groupId} onChange={(e) => setGroupId(e.target.value)} style={inputStyle} required>
              {groups.map(g => <option key={String(g.id)} value={String(g.id)}>{g.name} - {g.description}</option>)}
            </select>

            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Title *</label>
            <input type="text" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Special Offer!" style={inputStyle} required />

            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Subtitle</label>
            <input type="text" value={subtitle} onChange={(e) => setSubtitle(e.target.value)} placeholder="e.g. 50% off all premium features" style={inputStyle} />

            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Body</label>
            <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Describe the notification details..." style={{ ...inputStyle, minHeight: 100 }} />

            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Image URL</label>
            <input type="url" value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} placeholder="https://example.com/image.png" style={inputStyle} />

            <label style={{ display: "block", marginBottom: 4, fontWeight: "bold" }}>Deep Link (Href)</label>
            <input type="text" value={href} onChange={(e) => setHref(e.target.value)} placeholder="e.g. /premium" style={inputStyle} />

            <StatusBox s={status} />

            <button type="submit" disabled={sending || !groupId || !title} style={buttonStyle(sending)}>
              {sending ? "Broadcasting..." : "Send Broadcast"}
            </button>
          </form>
        </>
      )}
    </div>
  );
}
