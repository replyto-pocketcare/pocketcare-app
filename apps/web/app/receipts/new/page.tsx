"use client";

/**
 * Receipt capture. Take or upload a photo (or a PDF bill), read it on-device,
 * and hand a structured draft to the review screen.
 *
 * The AI fallback is offered HERE rather than on review because this is the
 * only screen that still holds the image in memory — and because the choice to
 * send it belongs next to the photo, not three taps later.
 */
import { useCallback, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { reconcile } from "@pocketcare/receipts";
import type { ReceiptDraft } from "@pocketcare/receipts";

import { useBaseCurrency } from "../../../src/hooks";
import { useEntitlement } from "../../../src/entitlement";
import { CameraIcon, ReceiptIcon, UploadIcon } from "../../../src/ui/icons";
import { Spinner } from "../../../src/ui/Spinner";
import {
  escalateToAi,
  saveScan,
  ScanError,
  scanReceipt,
  type ScanResult,
  type ScanStage,
} from "../../../src/receipts/scan";
import type { PreparedImage } from "../../../src/receipts/image";

export default function NewReceiptPage() {
  const { t } = useTranslation("receipts");
  const router = useRouter();
  const currency = useBaseCurrency();
  const ent = useEntitlement();

  const [stage, setStage] = useState<ScanStage | null>(null);
  const [fraction, setFraction] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ScanResult | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [source, setSource] = useState<"camera" | "upload">("upload");
  const [aiBusy, setAiBusy] = useState(false);
  const [pendingPdf, setPendingPdf] = useState<File | null>(null);
  const [dragging, setDragging] = useState(false);

  const cameraRef = useRef<HTMLInputElement>(null);
  const uploadRef = useRef<HTMLInputElement>(null);

  const run = useCallback(
    async (file: File, from: "camera" | "upload", password?: string) => {
      setError(null);
      setResult(null);
      setPreview(null);
      setSource(from);
      setStage("preparing");
      setFraction(0);
      try {
        const res = await scanReceipt(file, {
          currency,
          ...(password ? { password } : {}),
          onProgress: (p) => {
            setStage(p.stage);
            if (p.fraction !== undefined) setFraction(p.fraction);
          },
        });
        setResult(res);
        setPreview(res.image?.previewUrl ?? null);
        setPendingPdf(null);
        // A clean read needs no decision from the user — go straight to review.
        if (res.reconciled) await commit(res.draft, from);
      } catch (e) {
        if (e instanceof ScanError && e.needsPassword) {
          setPendingPdf(file);
          setError(t("errors.pdfLocked", "This PDF is password protected."));
        } else {
          setError((e as Error).message);
        }
      } finally {
        setStage(null);
      }
    },
    // `commit` is stable enough for this flow; re-creating it would reset state.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [currency, t],
  );

  async function commit(draft: ReceiptDraft, from: "camera" | "upload") {
    const scanId = await saveScan(draft, from);
    router.push(`/receipts/review?scan=${scanId}`);
  }

  async function improveWithAi() {
    if (!result?.image) return;
    setAiBusy(true);
    setError(null);
    try {
      const draft = await escalateToAi(result.image, {
        currency,
        ...(result.draft.rawText ? { rawText: result.draft.rawText } : {}),
      });
      await commit(draft, source);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setAiBusy(false);
    }
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files?.[0];
    if (file) void run(file, "upload");
  }

  const busy = stage !== null;
  const stageLabel = stage
    ? t(`stage.${stage}`, { defaultValue: stage })
    : null;

  return (
    <div style={{ display: "grid", gap: 16, maxWidth: 640 }}>
      <div>
        <h1 style={{ margin: 0 }}>{t("capture.title", "Scan a bill or receipt")}</h1>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {t("capture.intro", "Photograph a restaurant bill or grocery receipt and we'll turn it into a transaction — item by item.")}
        </p>
      </div>

      {/* ---- capture ---- */}
      {!result && (
        <section
          className="card"
          onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
          style={{
            padding: 24,
            display: "grid",
            gap: 16,
            justifyItems: "center",
            textAlign: "center",
            borderStyle: dragging ? "dashed" : undefined,
            borderColor: dragging ? "var(--accent)" : undefined,
          }}
        >
          {busy ? (
            <div style={{ display: "grid", gap: 12, justifyItems: "center", padding: "20px 0" }}>
              <Spinner />
              <strong style={{ fontSize: 15 }}>{stageLabel}</strong>
              {stage === "reading" && (
                <>
                  <div
                    aria-hidden
                    style={{ width: 220, height: 6, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}
                  >
                    <div
                      style={{
                        width: `${Math.round(fraction * 100)}%`,
                        height: "100%",
                        background: "var(--accent)",
                        transition: "width 0.2s",
                      }}
                    />
                  </div>
                  <span className="muted" style={{ fontSize: 12 }}>{Math.round(fraction * 100)}%</span>
                </>
              )}
            </div>
          ) : (
            <>
              <ReceiptIcon size={40} />
              <div style={{ display: "flex", gap: 10, flexWrap: "wrap", justifyContent: "center" }}>
                <button className="btn" type="button" onClick={() => cameraRef.current?.click()}>
                  <CameraIcon size={18} /> {t("capture.takePhoto", "Take photo")}
                </button>
                <button className="btn ghost" type="button" onClick={() => uploadRef.current?.click()}>
                  <UploadIcon size={18} /> {t("capture.upload", "Upload a file")}
                </button>
              </div>
              <p className="muted" style={{ fontSize: 12, margin: 0, maxWidth: 380 }}>
                {t("capture.dropHint", "Or drop an image or PDF here. JPEG, PNG or a PDF bill.")}
              </p>
            </>
          )}

          {/* `capture` opens the rear camera directly on a phone. */}
          <input
            ref={cameraRef}
            type="file"
            accept="image/*"
            capture="environment"
            hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void run(f, "camera");
              e.target.value = "";
            }}
          />
          <input
            ref={uploadRef}
            type="file"
            accept="image/*,application/pdf"
            hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void run(f, "upload");
              e.target.value = "";
            }}
          />
        </section>
      )}

      {/* ---- couldn't read it cleanly ---- */}
      {result && !result.reconciled && (
        <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
          <div style={{ display: "grid", gap: 4 }}>
            <strong>{t("capture.unclear.title", "We couldn't read this cleanly")}</strong>
            <span className="muted" style={{ fontSize: 13 }}>
              {describeMismatch(result.draft, t)}
            </span>
          </div>

          {preview && (
            <img
              src={preview}
              alt={t("capture.previewAlt", "The receipt you captured")}
              style={{ maxWidth: "100%", maxHeight: 220, objectFit: "contain", borderRadius: 10, justifySelf: "center" }}
            />
          )}

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            {result.canEscalate && result.image && (
              <button className="btn" type="button" onClick={() => void improveWithAi()} disabled={aiBusy || ent.quotaLeft <= 0}>
                {aiBusy ? <Spinner /> : null}
                {t("capture.improveWithAi", "Improve with AI")}
                {ent.quotaLeft > 0 && (
                  <span className="chip" style={{ marginLeft: 6, fontSize: 11 }}>
                    {t("capture.creditsLeft", "{{count}} left", { count: ent.quotaLeft })}
                  </span>
                )}
              </button>
            )}
            <button className="btn ghost" type="button" onClick={() => void commit(result.draft, source)} disabled={aiBusy}>
              {t("capture.editManually", "Edit it myself")}
            </button>
            <button className="btn ghost" type="button" onClick={() => { setResult(null); setPreview(null); }} disabled={aiBusy}>
              {t("capture.retake", "Retake")}
            </button>
          </div>

          {result.canEscalate && result.image && (
            <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
              {ent.quotaLeft <= 0 ? (
                <>
                  {t("capture.noCredits", "You're out of AI credits this month. You can still edit the receipt by hand.")}{" "}
                  <Link href="/settings">{t("capture.seePlans", "See plans")}</Link>
                </>
              ) : (
                t("capture.aiNote", "This sends the photo to our AI reader once. It isn't stored — by us or anyone else.")
              )}
            </p>
          )}
        </section>
      )}

      {/* ---- password-protected PDF ---- */}
      {pendingPdf && (
        <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
          <strong>{t("capture.pdfPassword", "This PDF needs a password")}</strong>
          <form
            style={{ display: "flex", gap: 8, flexWrap: "wrap" }}
            onSubmit={(e) => {
              e.preventDefault();
              const pw = new FormData(e.currentTarget).get("pw");
              if (typeof pw === "string" && pw) void run(pendingPdf, "upload", pw);
            }}
          >
            <input className="input" name="pw" type="password" autoComplete="off" placeholder={t("capture.passwordPlaceholder", "Password")} />
            <button className="btn" type="submit">{t("capture.unlock", "Unlock")}</button>
          </form>
        </section>
      )}

      {error && (
        <div className="card" style={{ padding: 14, color: "var(--negative)", fontSize: 13 }}>
          {error}
        </div>
      )}

      <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
        {t("capture.privacy", "Receipts are read on your device. Photos are never saved.")}
      </p>
    </div>
  );
}

/** Explain the specific reason a draft didn't reconcile, in money terms. */
function describeMismatch(draft: ReceiptDraft, t: TFunction<"receipts">): string {
  const r = reconcile(draft);
  if (r.reason === "no_lines") return t("capture.unclear.noLines", { defaultValue: "We couldn't find any items on this receipt." });
  if (r.reason === "missing_total") return t("capture.unclear.noTotal", { defaultValue: "We read the items but couldn't find the total." });
  return t("capture.unclear.mismatch", {
    defaultValue: "The items we read don't add up to the printed total.",
  });
}
