"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@powersync/react";
import { getSupabase, getUserId } from "../powersync";

const GENDERS = ["", "female", "male", "non-binary", "prefer not to say"];
const COUNTRIES = ["", "IN", "US", "GB", "CA", "AU", "SG", "AE", "DE", "FR", "NL", "JP", "BR", "ZA", "NG", "KE", "Other"];

/** Optional self-declared traits — used only for tailored offers/segments,
 *  never shown to other users. */
export function ProfileTraits() {
  const { data = [] } = useQuery<{ gender: string | null; country: string | null }>(
    "SELECT gender, country FROM profiles WHERE id = ? LIMIT 1", [getUserId() ?? ""],
  );
  const row = data[0];
  const [gender, setGender] = useState("");
  const [country, setCountry] = useState("");
  const [ready, setReady] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    if (row && !ready) { setGender(row.gender ?? ""); setCountry(row.country ?? ""); setReady(true); }
  }, [row, ready]);

  async function save() {
    const uid = getUserId();
    if (!uid) return;
    setMsg(null);
    const { error } = await getSupabase().schema("pocketcare").from("profiles")
      .update({ gender: gender || null, country: country || null, updated_at: new Date().toISOString() }).eq("id", uid);
    setMsg(error ? error.message : "Saved.");
  }

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
      <div>
        <h2 style={{ margin: 0 }}>About you <span className="muted" style={{ fontSize: 13, fontWeight: 400 }}>· optional</span></h2>
        <p className="muted" style={{ fontSize: 12, margin: "4px 0 0" }}>Helps us tailor offers and beta invites. Private — never shown to anyone else.</p>
      </div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <label style={{ display: "grid", gap: 4, flex: 1, minWidth: 150 }}>
          <span className="muted" style={{ fontSize: 12 }}>Gender</span>
          <select className="input" value={gender} onChange={(e) => { setGender(e.target.value); setMsg(null); }}>
            {GENDERS.map((g) => <option key={g} value={g}>{g ? g[0]!.toUpperCase() + g.slice(1) : "Not specified"}</option>)}
          </select>
        </label>
        <label style={{ display: "grid", gap: 4, flex: 1, minWidth: 150 }}>
          <span className="muted" style={{ fontSize: 12 }}>Country</span>
          <select className="input" value={country} onChange={(e) => { setCountry(e.target.value); setMsg(null); }}>
            {COUNTRIES.map((c) => <option key={c} value={c}>{c || "Not specified"}</option>)}
          </select>
        </label>
      </div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <button className="btn" onClick={save}>Save</button>
        {msg && <span className="muted" style={{ fontSize: 13 }}>{msg}</span>}
      </div>
    </section>
  );
}
