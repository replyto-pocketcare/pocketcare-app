"use client";

import { useEffect, useState } from "react";
import { getAdminDashboardStats } from "../../src/admin-actions";
import { Spinner } from "../../src/ui/Spinner";
import { AdminError } from "./AdminError";
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

export default function AdminDashboard() {
  const [stats, setStats] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getAdminDashboardStats().then((res) => {
      if (res.ok) setStats(res.data);
      else setError(res.error);
    });
  }, []);

  if (error) return <AdminError title="Couldn’t load dashboard" message={error} />;
  if (!stats) return <Spinner />;

  // Mock data for beautiful graphs
  const mockChartData = [
    { name: "Jan", income: 4000, projected: 4400 },
    { name: "Feb", income: 3000, projected: 3200 },
    { name: "Mar", income: 2000, projected: 2500 },
    { name: "Apr", income: 2780, projected: 3000 },
    { name: "May", income: 1890, projected: 2200 },
    { name: "Jun", income: 2390, projected: 2500 },
    { name: "Jul", income: 3490, projected: 3800 },
  ];

  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Dashboard</h1>
      
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 20 }}>
        <div style={{ padding: 20, background: "#222", borderRadius: 12, border: "1px solid #333" }}>
          <div style={{ color: "#aaa", fontSize: 14 }}>Total Users</div>
          <div style={{ fontFamily: "var(--font-serif)", fontSize: 32, fontWeight: 700 }}>{stats.totalUsers}</div>
        </div>
        <div style={{ padding: 20, background: "#222", borderRadius: 12, border: "1px solid #333" }}>
          <div style={{ color: "#aaa", fontSize: 14 }}>Active Subscriptions</div>
          <div style={{ fontFamily: "var(--font-serif)", fontSize: 32, fontWeight: 700 }}>{stats.activeSubscriptions}</div>
        </div>
        <div style={{ padding: 20, background: "#222", borderRadius: 12, border: "1px solid #333" }}>
          <div style={{ color: "#aaa", fontSize: 14 }}>Total Income</div>
          <div style={{ fontFamily: "var(--font-serif)", fontSize: 32, fontWeight: 700, color: "var(--accent)" }}>
            ${(stats.totalIncome / 100).toFixed(2)}
          </div>
        </div>
      </div>

      <div style={{ padding: 20, background: "#222", borderRadius: 12, border: "1px solid #333", height: 400 }}>
        <h3 style={{ marginTop: 0, marginBottom: 20 }}>Income & Projections</h3>
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={mockChartData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
            <defs>
              <linearGradient id="colorIncome" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="var(--accent)" stopOpacity={0.8}/>
                <stop offset="95%" stopColor="var(--accent)" stopOpacity={0}/>
              </linearGradient>
              <linearGradient id="colorProjected" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#8884d8" stopOpacity={0.8}/>
                <stop offset="95%" stopColor="#8884d8" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <XAxis dataKey="name" stroke="#888" />
            <YAxis stroke="#888" />
            <CartesianGrid strokeDasharray="3 3" stroke="#444" vertical={false} />
            <Tooltip contentStyle={{ background: "#333", border: "none", borderRadius: 8, color: "#fff" }} />
            <Area type="monotone" dataKey="projected" stroke="#8884d8" fillOpacity={1} fill="url(#colorProjected)" />
            <Area type="monotone" dataKey="income" stroke="var(--accent)" fillOpacity={1} fill="url(#colorIncome)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
