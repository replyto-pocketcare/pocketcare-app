"use client";

/** Inline error panel for admin pages — shows the real server-action failure
 *  instead of letting it bubble into an opaque 500. */
export function AdminError({ title, message }: { title: string; message: string }) {
  return (
    <div style={{ display: "grid", gap: 12 }}>
      <h1>{title}</h1>
      <div style={{ background: "#2a1a1a", border: "1px solid #633", borderRadius: 12, padding: 20, display: "grid", gap: 10 }}>
        <div style={{ color: "#f88", fontWeight: 600 }}>The server returned an error</div>
        <pre style={{ margin: 0, whiteSpace: "pre-wrap", wordBreak: "break-word", color: "#f99", fontSize: 13 }}>{message}</pre>
        <div style={{ color: "#bbb", fontSize: 13, lineHeight: 1.6 }}>
          Common causes: a required migration hasn’t been applied to this database,
          or <code>SUPABASE_SERVICE_ROLE_KEY</code> isn’t set in the deployment.
        </div>
      </div>
    </div>
  );
}
