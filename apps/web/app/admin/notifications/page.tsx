"use client";

export default function AdminNotifications() {
  return (
    <div style={{ display: "grid", gap: 30 }}>
      <h1>Notifications</h1>
      
      <div style={{ background: "#222", borderRadius: 12, border: "1px solid #333", padding: 40, textAlign: "center" }}>
        <h3 style={{ margin: "0 0 10px" }}>Coming Soon</h3>
        <p style={{ color: "#888", margin: 0 }}>
          Notification framework is ready. Integration with Expo and Edge Functions will be implemented here.
        </p>
      </div>
    </div>
  );
}
