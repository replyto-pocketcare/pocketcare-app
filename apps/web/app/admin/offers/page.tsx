"use client";

import { useEffect, useState } from "react";
import { getPriceOffers, createPriceOffer, togglePriceOffer, getAudienceGroups } from "../../../src/admin-actions";
import { Spinner } from "../../../src/ui/Spinner";
import { AdminError } from "../AdminError";

export default function AdminOffers() {
  const [offers, setOffers] = useState<any[] | null>(null);
  const [groups, setGroups] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);

  // New offer form
  const [tier, setTier] = useState("lite");
  const [cycle, setCycle] = useState("yearly");
  const [price, setPrice] = useState("");
  const [label, setLabel] = useState("");
  const [segmentId, setSegmentId] = useState("");

  const refresh = () => {
    getPriceOffers().then(res => res.ok ? setOffers(res.data) : setError(res.error));
  };

  useEffect(() => {
    refresh();
    getAudienceGroups().then(res => res.ok && setGroups(res.data));
  }, []);

  const handleCreate = async () => {
    const p = parseInt(price, 10);
    if (!p || !label) return;
    const res = await createPriceOffer({
      tier, cycle, price: p, label, segment_id: segmentId || null
    });
    if (res.ok) {
      setPrice("");
      setLabel("");
      refresh();
    } else {
      alert(res.error);
    }
  };

  if (error) return <AdminError title="Couldn't load offers" message={error} />;
  if (!offers) return <Spinner />;

  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Promotional Offers</h1>

      <div style={{ background: "#222", padding: 20, borderRadius: 12, border: "1px solid #333", display: "grid", gap: 16 }}>
        <h2>Create Offer</h2>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          <select className="input" value={tier} onChange={e => setTier(e.target.value)} style={{ width: 100 }}>
            <option value="lite">Lite</option>
            <option value="pro">Pro</option>
          </select>
          <select className="input" value={cycle} onChange={e => setCycle(e.target.value)} style={{ width: 120 }}>
            <option value="monthly">Monthly</option>
            <option value="yearly">Yearly</option>
          </select>
          <input className="input" placeholder="Price (minor units e.g. 2900 for ₹29)" value={price} onChange={e => setPrice(e.target.value)} type="number" />
          <input className="input" placeholder="Label (e.g. Founder's Offer)" value={label} onChange={e => setLabel(e.target.value)} />
          <select className="input" value={segmentId} onChange={e => setSegmentId(e.target.value)}>
            <option value="">All Users (Global)</option>
            {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
          </select>
          <button className="btn" onClick={handleCreate}>Create</button>
        </div>
      </div>

      <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid #333", background: "#1a1a1a" }}>
              <th style={{ padding: 16 }}>Label</th>
              <th style={{ padding: 16 }}>Plan</th>
              <th style={{ padding: 16 }}>Price</th>
              <th style={{ padding: 16 }}>Audience</th>
              <th style={{ padding: 16 }}>Status</th>
              <th style={{ padding: 16 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {offers.map(o => (
              <tr key={o.id} style={{ borderBottom: "1px solid #333", opacity: o.active ? 1 : 0.5 }}>
                <td style={{ padding: 16 }}><strong>{o.label}</strong></td>
                <td style={{ padding: 16, textTransform: "capitalize" }}>{o.tier} {o.cycle}</td>
                <td style={{ padding: 16 }}>{o.price / 100}</td>
                <td style={{ padding: 16 }}>{o.audience_groups?.name || "Global"}</td>
                <td style={{ padding: 16 }}>{o.active ? <span style={{ color: "#2ea043" }}>Active</span> : "Inactive"}</td>
                <td style={{ padding: 16 }}>
                  <button className="btn ghost" onClick={async () => {
                    await togglePriceOffer(o.id, !o.active);
                    refresh();
                  }}>
                    {o.active ? "Deactivate" : "Activate"}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {offers.length === 0 && <div style={{ padding: 20, textAlign: "center", color: "#888" }}>No offers created yet.</div>}
      </div>
    </div>
  );
}
