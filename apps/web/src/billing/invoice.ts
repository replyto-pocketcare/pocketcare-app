"use client";

import { downloadText } from "../data/csv";

/**
 * Issuer / letterhead details. ⚠️ Replace the placeholders with your real
 * registered legal entity, address and (if GST-registered) GSTIN before going
 * live — this text prints on every invoice.
 */
export const INVOICE_ISSUER = {
  brand: "PocketCare",
  legalName: "PocketCare",
  address: "Eastonia, Palm Groves Society, Ghorpadi, Pune ",
  email: "replyto.pocketcare@gmail.com",
  gstin: "", // e.g. "27ABCDE1234F1Z5" — leave blank if not GST-registered
  note: "This is a computer-generated invoice and does not require a signature.",
};

export interface InvoicePayment {
  id?: string;
  created_at?: string | null;
  kind: string; // 'subscription' | 'credits'
  amount?: number | null; // paise
  currency?: string | null;
  credits_added?: number | null;
  razorpay_payment_id?: string | null;
  razorpay_order_id?: string | null;
  status?: string | null;
}

const rupees = (paise?: number | null) => `₹${((paise ?? 0) / 100).toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function invoiceNumber(p: InvoicePayment): string {
  const yr = p.created_at ? new Date(p.created_at).getFullYear() : new Date().getFullYear();
  const ref = (p.razorpay_payment_id || p.id || Math.random().toString(36).slice(2)).replace(/[^a-zA-Z0-9]/g, "").slice(-8).toUpperCase();
  return `PC-${yr}-${ref}`;
}

const description = (p: InvoicePayment): string =>
  p.kind === "credits"
    ? `PocketCare AI credits — ${p.credits_added ?? 0} prompts`
    : "PocketCare subscription";

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}

export function invoiceHtml(p: InvoicePayment, buyerEmail: string): string {
  const inv = invoiceNumber(p);
  const date = p.created_at ? new Date(p.created_at).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "";
  const I = INVOICE_ISSUER;
  return `<!doctype html><html><head><meta charset="utf-8"><title>Invoice ${esc(inv)}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, Inter, Segoe UI, Roboto, sans-serif; color: #2b2723; margin: 0; background: #f4ece1; }
  .sheet { max-width: 720px; margin: 24px auto; background: #fffdf9; border: 1px solid #e7dccd; border-radius: 12px; padding: 36px; }
  .head { display: flex; justify-content: space-between; gap: 24px; align-items: flex-start; }
  .brand { display: flex; align-items: center; gap: 10px; }
  .mark { width: 34px; height: 34px; border-radius: 9px; background: #b06a4f; color: #fff; display: grid; place-items: center; font-weight: 800; }
  .brand h1 { font-size: 20px; margin: 0; letter-spacing: -0.01em; } .brand h1 span { color: #b06a4f; }
  .issuer { text-align: right; font-size: 12px; color: #7c7264; line-height: 1.5; }
  .rule { border: none; border-top: 2px solid #e7dccd; margin: 22px 0; }
  .title { font-size: 22px; font-weight: 750; letter-spacing: -0.02em; }
  .meta { display: flex; justify-content: space-between; gap: 24px; margin: 6px 0 22px; font-size: 13px; }
  .meta .muted { color: #7c7264; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th { text-align: left; border-bottom: 2px solid #e7dccd; padding: 8px 6px; color: #7c7264; font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
  td { padding: 12px 6px; border-bottom: 1px solid #efe6d8; }
  .right { text-align: right; }
  .total td { border: none; font-weight: 750; font-size: 16px; padding-top: 16px; }
  .foot { margin-top: 26px; font-size: 12px; color: #7c7264; line-height: 1.6; }
  @media print { body { background: #fff; } .sheet { border: none; margin: 0; } }
</style></head>
<body>
  <div class="sheet">
    <div class="head">
      <div class="brand"><div class="mark">◔</div><h1>Pocket<span>Care</span></h1></div>
      <div class="issuer">
        <strong>${esc(I.legalName)}</strong><br/>
        ${esc(I.address)}<br/>
        ${esc(I.email)}${I.gstin ? `<br/>GSTIN: ${esc(I.gstin)}` : ""}
      </div>
    </div>
    <hr class="rule"/>
    <div class="title">${I.gstin ? "Tax Invoice" : "Invoice"}</div>
    <div class="meta">
      <div>
        <div class="muted">Billed to</div>
        <div><strong>${esc(buyerEmail || "PocketCare customer")}</strong></div>
      </div>
      <div class="right">
        <div><span class="muted">Invoice no.</span> <strong>${esc(inv)}</strong></div>
        <div><span class="muted">Date</span> ${esc(date)}</div>
        ${p.razorpay_payment_id ? `<div><span class="muted">Payment ID</span> ${esc(p.razorpay_payment_id)}</div>` : ""}
      </div>
    </div>
    <table>
      <thead><tr><th>Description</th><th class="right">Qty</th><th class="right">Amount</th></tr></thead>
      <tbody>
        <tr><td>${esc(description(p))}</td><td class="right">1</td><td class="right">${rupees(p.amount)}</td></tr>
        <tr class="total"><td></td><td class="right">Total</td><td class="right">${rupees(p.amount)}</td></tr>
      </tbody>
    </table>
    <div class="foot">
      ${I.gstin ? "Amount is inclusive of applicable GST." : "Amount charged as shown."} Paid via Razorpay.<br/>
      ${esc(I.note)} For any queries, contact ${esc(I.email)}.
    </div>
  </div>
  <script>window.onload=function(){setTimeout(function(){window.print();},250);};</script>
</body></html>`;
}

/** Open the invoice in a new tab for print / save-as-PDF (falls back to download). */
export function openInvoice(p: InvoicePayment, buyerEmail: string): void {
  const html = invoiceHtml(p, buyerEmail);
  const w = typeof window !== "undefined" ? window.open("", "_blank") : null;
  if (w) {
    w.document.open();
    w.document.write(html);
    w.document.close();
  } else {
    downloadText(`pocketcare-invoice-${invoiceNumber(p)}.html`, html, "text/html;charset=utf-8");
  }
}
