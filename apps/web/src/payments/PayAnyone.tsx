"use client";

/**
 * Pay any UPI ID — typed in, or read off a QR with the camera.
 *
 * Same posture as the settle-up flow: **no money touches PocketCare**. We build
 * a UPI Intent deep link and the payer's own UPI app moves it bank-to-bank.
 *
 * SECURITY — a scanned QR is untrusted input:
 *  - The name on a QR is only what the code CLAIMS. A sticker on a shop counter
 *    can be swapped. So the VPA is always shown in full, the claimed name is
 *    labelled as claimed, and the real verification is the payer's own UPI app
 *    showing the registered account name before they confirm.
 *  - A scanned amount is a suggestion that lands in an editable field. Nothing
 *    is ever auto-submitted; opening the UPI app is always a deliberate tap.
 *  - Parsing/validation lives in `@pocketcare/upi` (`parseUpiTarget`), which is
 *    unit-tested against duplicated `pa` params, hostile amounts, non-UPI URLs
 *    and EMVCo payloads.
 *
 * This is deliberately NOT recorded as a transaction: UPI Intent returns
 * nothing to a web page, so we can't know whether it went through. Offering to
 * log it afterwards is a follow-up worth doing; silently logging it is not.
 */

import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { buildIntentUrl, parseUpiTarget, maskVpa, type UpiTarget, type UpiParseFailure } from "@pocketcare/upi";
import { Modal } from "../ui/Modal";
import { AmountInput } from "../ui/AmountInput";
import { MaterialIcon } from "../ui/MaterialIcon";
import { createScanner, canScan, ScanError } from "./scanQr";

type Mode = "enter" | "scan";

export function PayAnyone({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useTranslation("payments");
  const [mode, setMode] = useState<Mode>("enter");
  const [vpaText, setVpaText] = useState("");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [target, setTarget] = useState<UpiTarget | null>(null);
  const [error, setError] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const scannerRef = useRef<ReturnType<typeof createScanner> | null>(null);

  const reset = () => {
    setMode("enter"); setVpaText(""); setAmount(""); setNote("");
    setTarget(null); setError(null);
  };

  const failureCopy = (reason: UpiParseFailure): string => t(`payAnyone.err.${reason}`, {
    defaultValue: {
      empty: "Enter a UPI ID first.",
      not_upi: "That code isn't a UPI payment code.",
      emvco: "That's a Bharat QR. Scan it with your UPI app directly — this reader only understands UPI codes.",
      bad_vpa: "That doesn't look like a valid UPI ID.",
      unsupported_currency: "UPI only supports payments in rupees.",
    }[reason],
  });

  /** Accept a typed string or a scanned payload through the same validator. */
  const accept = (raw: string) => {
    const r = parseUpiTarget(raw);
    if (!r.ok) { setError(failureCopy(r.reason)); return false; }
    setError(null);
    setTarget(r.target);
    if (r.target.amountMinor) setAmount((r.target.amountMinor / 100).toFixed(2));
    if (r.target.note && !note) setNote(r.target.note);
    return true;
  };

  // Camera lifecycle. The scanner MUST be stopped on unmount or mode change —
  // a live camera outliving its modal is a battery drain and a privacy problem.
  useEffect(() => {
    if (!open || mode !== "scan") return;
    const scanner = createScanner();
    scannerRef.current = scanner;
    let cancelled = false;
    (async () => {
      try {
        if (!videoRef.current) return;
        await scanner.start(videoRef.current, (text) => {
          if (cancelled) return;
          if (accept(text)) setMode("enter");
          else setMode("enter"); // show the reason on the form rather than a dead camera
        });
      } catch (e) {
        if (!cancelled) { setError(e instanceof ScanError ? e.message : t("payAnyone.err.other", "Couldn't start the camera.")); setMode("enter"); }
      }
    })();
    return () => { cancelled = true; scanner.stop(); scannerRef.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, mode]);

  useEffect(() => { if (!open) { scannerRef.current?.stop(); reset(); } }, [open]);

  const minor = Math.round((Number(amount) || 0) * 100);
  const canPay = !!target && minor > 0;

  const pay = () => {
    if (!target || minor <= 0) return;
    try {
      const { url } = buildIntentUrl({
        vpa: target.vpa,
        name: target.name || target.vpa,
        amountMinor: minor,
        ...(note.trim() ? { note: note.trim() } : {}),
      });
      // A deliberate tap, every time — never automatic.
      window.location.href = url;
    } catch (e) {
      setError((e as Error).message);
    }
  };

  return (
    <Modal open={open} onClose={onClose}>
      <div style={{ display: "grid", gap: 14 }}>
        <div>
          <h2 style={{ margin: 0 }}>{t("payAnyone.title", "Pay someone")}</h2>
          <p className="muted" style={{ margin: "4px 0 0", fontSize: 12.5 }}>
            {t("payAnyone.subtitle", "Opens your own UPI app. PocketCare never holds or moves the money.")}
          </p>
        </div>

        {mode === "scan" ? (
          <div style={{ display: "grid", gap: 10 }}>
            <div style={{ position: "relative", borderRadius: 14, overflow: "hidden", background: "#000", aspectRatio: "1 / 1" }}>
              <video ref={videoRef} muted playsInline style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              <div aria-hidden style={{
                position: "absolute", inset: "14%", border: "2px solid rgba(255,255,255,0.9)",
                borderRadius: 12, boxShadow: "0 0 0 100vmax rgba(0,0,0,0.35)",
              }} />
            </div>
            <p className="muted" style={{ fontSize: 12, margin: 0, textAlign: "center" }}>
              {t("payAnyone.scanHint", "Point the camera at a UPI QR code")}
            </p>
            <button className="btn ghost" onClick={() => setMode("enter")}>{t("payAnyone.cancelScan", "Cancel")}</button>
          </div>
        ) : (
          <>
            <label style={{ display: "grid", gap: 5 }}>
              <span className="muted" style={{ fontSize: 12 }}>{t("payAnyone.upiId", "UPI ID")}</span>
              <input
                className="input"
                inputMode="email"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                placeholder="name@bank"
                value={target ? target.vpa : vpaText}
                onChange={(e) => { setTarget(null); setVpaText(e.target.value); setError(null); }}
                onBlur={() => { if (!target && vpaText.trim()) accept(vpaText); }}
              />
            </label>

            {canScan() && (
              <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => { setError(null); setMode("scan"); }}>
                <MaterialIcon name="search" size={16} /> {t("payAnyone.scanCta", "Scan a QR code")}
              </button>
            )}

            {target && (
              <div className="card" style={{ padding: 12, display: "grid", gap: 4, background: "var(--surface-2)" }}>
                <div style={{ fontWeight: 700, fontSize: 14, overflowWrap: "anywhere" }}>{target.vpa}</div>
                {target.name && (
                  // "Claims to be" is not pedantry: the payer's UPI app shows
                  // the REAL registered name, and that's the check that counts.
                  <div className="muted" style={{ fontSize: 12 }}>
                    {t("payAnyone.claimsName", { name: target.name, defaultValue: "Code says: {{name}} — your UPI app will show the real account name" })}
                  </div>
                )}
              </div>
            )}

            <label style={{ display: "grid", gap: 5 }}>
              <span className="muted" style={{ fontSize: 12 }}>{t("payAnyone.amount", "Amount")}</span>
              <AmountInput value={amount} onChange={setAmount} />
            </label>

            <input
              className="input"
              placeholder={t("payAnyone.notePlaceholder", "Note (optional)")}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={50}
            />

            {error && (
              <div className="card" style={{ padding: 10, fontSize: 12.5, borderColor: "var(--negative)", color: "var(--negative)" }}>{error}</div>
            )}

            <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
              {t("payAnyone.footnote", "Check the account name in your UPI app before you confirm. PocketCare can't verify who owns a UPI ID.")}
            </p>

            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
              <button className="btn ghost" onClick={onClose}>{t("payAnyone.close", "Close")}</button>
              <button className="btn" disabled={!canPay} onClick={pay}>
                {canPay ? t("payAnyone.payAmount", { amount: maskVpa(target!.vpa), defaultValue: "Open UPI app" }) : t("payAnyone.pay", "Open UPI app")}
              </button>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
