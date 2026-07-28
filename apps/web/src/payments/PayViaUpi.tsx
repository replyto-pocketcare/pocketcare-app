"use client";

/**
 * "Pay via UPI" — the whole payer-side flow in one component.
 *
 * Fetch the payee's handle → build an Intent link → hand off to their UPI app
 * (mobile) or show a QR (desktop) → come back and ask whether it went through.
 *
 * THERE IS NO SUCCESS CALLBACK. UPI Intent hands control to a third-party app
 * and never reports back to a web page. That's structural, not a gap we can
 * close later, so the UI asks the user plainly rather than pretending to know.
 *
 * DEEP LINKS ARE NOT GUARANTEED. `upi://` handling varies by OS, browser and
 * installed apps, and iOS/Safari in particular can no-op silently. So there is
 * always a manual path — copy the UPI ID and amount, or save the QR and use
 * "scan from gallery" — and we surface it automatically when a hand-off looks
 * like it failed. The payment must never be a dead end because a URL scheme
 * stopped working.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { buildIntentUrl, formatAmount, maskVpa } from "@pocketcare/upi";

import { Spinner } from "../ui/Spinner";
import { fetchCounterpartyHandle, HandleError } from "./handles";
import { renderQrDataUrl } from "./qr";

/** Coarse but sufficient: does this device have a UPI app to hand off to? */
function isMobile(): boolean {
  if (typeof navigator === "undefined") return false;
  return /android|iphone|ipad|ipod/i.test(navigator.userAgent);
}

/**
 * If the UPI app opened, this page gets backgrounded. If we're still visible
 * after this long, the hand-off almost certainly did nothing.
 */
const HANDOFF_TIMEOUT_MS = 1500;

type Stage = "idle" | "fetching" | "ready" | "error";

export interface PayViaUpiProps {
  readonly counterpartyId: string;
  readonly counterpartyName: string;
  /** Minor units the payer owes. */
  readonly amountMinor: number;
  readonly note?: string;
  /** Called once the user says they've paid; receives our `tr=` reference. */
  readonly onPaid: (ref: string) => void;
}

export function PayViaUpi({ counterpartyId, counterpartyName, amountMinor, note, onPaid }: PayViaUpiProps) {
  const { t } = useTranslation("payments");
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState<string | null>(null);
  const [errorCode, setErrorCode] = useState<string | undefined>(undefined);
  const [vpa, setVpa] = useState<string | null>(null);
  const [intent, setIntent] = useState<{ url: string; ref: string } | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [showFallback, setShowFallback] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  const handoffTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mobile = isMobile();

  const start = useCallback(async () => {
    setStage("fetching");
    setError(null);
    setErrorCode(undefined);
    try {
      const handle = await fetchCounterpartyHandle(counterpartyId);
      const built = buildIntentUrl({
        vpa: handle.vpa,
        name: handle.displayName ?? counterpartyName,
        amountMinor,
        note: note ?? "PocketCare settle-up",
      });
      setVpa(handle.vpa);
      setIntent(built);
      // Desktop has no app to hand off to, so the QR IS the primary path.
      setShowFallback(!mobile);
      setStage("ready");
    } catch (e) {
      setError((e as Error).message);
      if (e instanceof HandleError) setErrorCode(e.code);
      setStage("error");
    }
  }, [counterpartyId, counterpartyName, amountMinor, note, mobile]);

  // Render the QR whenever the fallback is (or becomes) visible. On mobile
  // that's only after a failed hand-off, so we don't pay the CDN cost up front.
  useEffect(() => {
    if (!showFallback || !intent || qr) return;
    let cancelled = false;
    void renderQrDataUrl(intent.url)
      .then((url) => { if (!cancelled) setQr(url); })
      .catch((e) => { if (!cancelled) setError((e as Error).message); });
    return () => { cancelled = true; };
  }, [showFallback, intent, qr]);

  // If the page gets hidden, the UPI app took over — cancel the "it failed" timer.
  useEffect(() => {
    const onVisibility = () => {
      if (document.visibilityState === "hidden" && handoffTimer.current) {
        clearTimeout(handoffTimer.current);
        handoffTimer.current = null;
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      if (handoffTimer.current) clearTimeout(handoffTimer.current);
    };
  }, []);

  function handOff() {
    if (!intent) return;
    // Navigating (rather than window.open) is what actually triggers the app
    // switch on both Android and iOS; a popup gets blocked or opens a blank tab.
    window.location.href = intent.url;

    // Still here a moment later? Nothing handled the scheme — reveal the
    // manual path rather than leaving the user staring at an unchanged screen.
    if (handoffTimer.current) clearTimeout(handoffTimer.current);
    handoffTimer.current = setTimeout(() => {
      if (document.visibilityState === "visible") setShowFallback(true);
    }, HANDOFF_TIMEOUT_MS);
  }

  async function copy(text: string, which: string) {
    try {
      await navigator.clipboard?.writeText(text);
      setCopied(which);
      setTimeout(() => setCopied(null), 1800);
    } catch {
      /* clipboard blocked — the value is on screen to copy by hand */
    }
  }

  // ---- idle / fetching / error ----
  if (stage === "idle") {
    return (
      <button className="btn" type="button" onClick={() => void start()}>
        {t("pay.button", "Pay via UPI")}
      </button>
    );
  }

  if (stage === "fetching") {
    return (
      <div style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
        <Spinner /> {t("pay.preparing", "Preparing the payment…")}
      </div>
    );
  }

  if (stage === "error") {
    return (
      <div style={{ display: "grid", gap: 8 }}>
        <div style={{ color: "var(--negative)", fontSize: 13 }}>
          {errorCode === "no_handle"
            ? t("pay.noHandle", "{{name}} hasn't added a UPI ID yet.", { name: counterpartyName })
            : error}
        </div>
        <button className="btn ghost" type="button" onClick={() => setStage("idle")} style={{ justifySelf: "start" }}>
          {t("pay.back", "Back")}
        </button>
      </div>
    );
  }

  const amountText = formatAmount(amountMinor);

  // ---- ready ----
  return (
    <div style={{ display: "grid", gap: 12 }}>
      {vpa && (
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", fontSize: 13 }}>
          <span className="muted">{t("pay.payingTo", "Paying")}</span>
          <code style={{ fontSize: 12.5 }}>{maskVpa(vpa)}</code>
        </div>
      )}

      {mobile && (
        <>
          <button className="btn" type="button" onClick={handOff}>
            {t("pay.openApp", "Open UPI app")}
          </button>
          {!showFallback && (
            <button
              className="chip"
              type="button"
              onClick={() => setShowFallback(true)}
              style={{ justifySelf: "start", fontSize: 11.5 }}
            >
              {t("pay.didntOpen", "Didn't open? Pay another way")}
            </button>
          )}
        </>
      )}

      {/* ---- manual fallback: always reachable, auto-revealed on failure ---- */}
      {showFallback && (
        <div
          style={{
            display: "grid",
            gap: 10,
            padding: 12,
            borderRadius: 10,
            background: "var(--surface-2)",
          }}
        >
          {mobile && (
            <strong style={{ fontSize: 13 }}>{t("pay.manualTitle", "Pay it manually")}</strong>
          )}

          {/* Copy the two values needed to pay by hand in any UPI app. */}
          {vpa && (
            <div style={{ display: "grid", gap: 6 }}>
              <div style={{ display: "flex", gap: 8, alignItems: "center", justifyContent: "space-between", flexWrap: "wrap" }}>
                <code style={{ fontSize: 12.5, wordBreak: "break-all" }}>{vpa}</code>
                <button className="chip" type="button" style={{ fontSize: 11 }} onClick={() => void copy(vpa, "vpa")}>
                  {copied === "vpa" ? t("pay.copied", "Copied") : t("pay.copyId", "Copy UPI ID")}
                </button>
              </div>
              <div style={{ display: "flex", gap: 8, alignItems: "center", justifyContent: "space-between", flexWrap: "wrap" }}>
                <code style={{ fontSize: 12.5 }}>₹{amountText}</code>
                <button className="chip" type="button" style={{ fontSize: 11 }} onClick={() => void copy(amountText, "amt")}>
                  {copied === "amt" ? t("pay.copied", "Copied") : t("pay.copyAmount", "Copy amount")}
                </button>
              </div>
            </div>
          )}

          <div style={{ display: "grid", gap: 6, justifyItems: "center" }}>
            {qr ? (
              <img
                src={qr}
                alt={t("pay.qrAlt", "QR code to pay via UPI")}
                width={200}
                height={200}
                style={{ borderRadius: 10, background: "#fff" }}
              />
            ) : (
              <Spinner />
            )}
            <p className="muted" style={{ fontSize: 11.5, margin: 0, textAlign: "center", maxWidth: 280 }}>
              {mobile
                ? t(
                    "pay.qrHintMobile",
                    "Save this image, then use “scan from gallery” in your UPI app — or scan it from another device.",
                  )
                : t("pay.scanHint", "Scan this with any UPI app on your phone to pay.")}
            </p>
          </div>
        </div>
      )}

      <div style={{ display: "grid", gap: 6 }}>
        <span className="muted" style={{ fontSize: 12 }}>
          {t("pay.afterPaying", "Once you've paid:")}
        </span>
        <button className="btn" type="button" onClick={() => intent && onPaid(intent.ref)}>
          {t("pay.markPaid", "I've paid — tell them")}
        </button>
        <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
          {t(
            "pay.noCallbackNote",
            "We can't see UPI payments, so we'll ask {{name}} to confirm it arrived.",
            { name: counterpartyName },
          )}
        </p>
      </div>
    </div>
  );
}
