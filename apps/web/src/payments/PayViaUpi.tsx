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
 */
import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { buildIntentUrl, maskVpa } from "@pocketcare/upi";

import { Spinner } from "../ui/Spinner";
import { fetchCounterpartyHandle, HandleError } from "./handles";
import { renderQrDataUrl } from "./qr";

/** Coarse but sufficient: does this device have a UPI app to hand off to? */
function isMobile(): boolean {
  if (typeof navigator === "undefined") return false;
  return /android|iphone|ipad|ipod/i.test(navigator.userAgent);
}

type Stage = "idle" | "fetching" | "ready" | "handed-off" | "error";

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
        note: note ?? `PocketCare settle-up`,
      });
      setVpa(handle.vpa);
      setIntent(built);
      setStage("ready");
    } catch (e) {
      setError((e as Error).message);
      if (e instanceof HandleError) setErrorCode(e.code);
      setStage("error");
    }
  }, [counterpartyId, counterpartyName, amountMinor, note]);

  // Desktop needs the QR; mobile doesn't, so don't pay the CDN cost there.
  useEffect(() => {
    if (stage !== "ready" || mobile || !intent) return;
    let cancelled = false;
    void renderQrDataUrl(intent.url)
      .then((url) => { if (!cancelled) setQr(url); })
      .catch((e) => { if (!cancelled) setError((e as Error).message); });
    return () => { cancelled = true; };
  }, [stage, mobile, intent]);

  function handOff() {
    if (!intent) return;
    setStage("handed-off");
    // Navigating (rather than window.open) is what actually triggers the app
    // switch on both Android and iOS; a popup gets blocked or opens a blank tab.
    window.location.href = intent.url;
  }

  // ---- idle ----
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

  // ---- ready / handed-off ----
  return (
    <div style={{ display: "grid", gap: 12 }}>
      {vpa && (
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", fontSize: 13 }}>
          <span className="muted">{t("pay.payingTo", "Paying")}</span>
          <code style={{ fontSize: 12.5 }}>{maskVpa(vpa)}</code>
          <button
            className="chip"
            type="button"
            style={{ fontSize: 11 }}
            onClick={() => void navigator.clipboard?.writeText(vpa)}
          >
            {t("pay.copyId", "Copy UPI ID")}
          </button>
        </div>
      )}

      {mobile ? (
        <button className="btn" type="button" onClick={handOff}>
          {t("pay.openApp", "Open UPI app")}
        </button>
      ) : (
        <div style={{ display: "grid", gap: 8, justifyItems: "center" }}>
          {qr ? (
            <img
              src={qr}
              alt={t("pay.qrAlt", "QR code to pay via UPI")}
              width={240}
              height={240}
              style={{ borderRadius: 10, background: "#fff" }}
            />
          ) : (
            <Spinner />
          )}
          <p className="muted" style={{ fontSize: 12, margin: 0, textAlign: "center", maxWidth: 260 }}>
            {t("pay.scanHint", "Scan this with any UPI app on your phone to pay.")}
          </p>
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
