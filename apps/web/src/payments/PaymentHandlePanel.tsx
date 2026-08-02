"use client";

/**
 * Settings → your UPI ID.
 *
 * Deliberately honest about the security tier. Unlike the passphrase-protected
 * personal fields, this value is readable by our server — it has to be, because
 * the whole point is handing it to someone who owes you money. The copy says
 * so, and the disclosure list shows exactly who has fetched it.
 */
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { isValidVpa, maskVpa, normalizeVpa } from "@sanvya/upi";

import { useSession } from "../account";
import { useUserProfiles } from "../splits/hooks";
import { Spinner } from "../ui/Spinner";
import { forgetPaymentHandle, getMyPaymentHandle, savePaymentHandle } from "./handles";
import { useCanSavePaymentHandle, useHandleDisclosures } from "./hooks";

export function PaymentHandlePanel() {
  const { t } = useTranslation("payments");
  const session = useSession();
  const canSave = useCanSavePaymentHandle();
  const disclosures = useHandleDisclosures();
  const profiles = useUserProfiles();

  const [value, setValue] = useState("");
  const [hint, setHint] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showLog, setShowLog] = useState(false);
  const [loading, setLoading] = useState(true);

  // Load the existing handle. Without this the panel only ever knew about a
  // handle saved in the same session, so every reload showed a bare "add" form
  // to someone who already had one — as if their UPI ID had been forgotten.
  useEffect(() => {
    if (!canSave) {
      setLoading(false);
      return;
    }
    let alive = true;
    void getMyPaymentHandle()
      .then((h) => { if (alive) setHint(h); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [canSave]);

  const normalized = normalizeVpa(value);
  const looksValid = normalized.length === 0 || isValidVpa(normalized);
  const canSubmit = !busy && normalized.length > 0 && isValidVpa(normalized);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      const saved = await savePaymentHandle(normalized, session?.username);
      setHint(saved);
      setValue("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function forget() {
    setBusy(true);
    setError(null);
    try {
      await forgetPaymentHandle();
      setHint(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="card" style={{ padding: 18, display: "grid", gap: 12 }}>
      <div>
        <strong>{t("settings.title", "Your UPI ID")}</strong>
        <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>
          {t(
            "settings.intro",
            "Add your UPI ID so friends can pay you back from inside Sanvya. Money goes straight to your bank — we never hold it.",
          )}
        </p>
      </div>

      {!canSave ? (
        <div className="muted" style={{ fontSize: 13 }}>
          {t("settings.guestBlocked", "Create an account to add a UPI ID. Guest sessions can't save payment details.")}
        </div>
      ) : loading ? (
        // Never render the empty form before we know — flashing "add a UPI ID"
        // at someone who has one reads as though it was lost.
        <div style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <Spinner />
        </div>
      ) : (
        <>
          {hint && (
            <div style={{ display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12 }}>
                {t("settings.current", "Your UPI ID")}
              </span>
              <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
                <code style={{ fontSize: 13 }}>{hint}</code>
                <button className="chip" type="button" onClick={() => void forget()} disabled={busy}>
                  {t("settings.remove", "Remove")}
                </button>
              </div>
            </div>
          )}

          <label style={{ display: "grid", gap: 4 }}>
            <span className="muted" style={{ fontSize: 12 }}>
              {hint ? t("settings.replace", "Replace with a different UPI ID") : t("settings.label", "UPI ID")}
            </span>
            <input
              className="input"
              inputMode="email"
              autoComplete="off"
              spellCheck={false}
              placeholder="name@bank"
              value={value}
              onChange={(e) => setValue(e.target.value)}
              aria-invalid={!looksValid}
            />
          </label>

          {!looksValid && (
            <span style={{ color: "var(--negative)", fontSize: 12 }}>
              {t("settings.invalid", "That doesn't look right — a UPI ID looks like name@bank.")}
            </span>
          )}
          {normalized.length > 0 && looksValid && (
            <span className="muted" style={{ fontSize: 12 }}>
              {t("settings.willShow", "Others will see {{masked}}", { masked: maskVpa(normalized) })}
            </span>
          )}

          {error && <div style={{ color: "var(--negative)", fontSize: 13 }}>{error}</div>}

          <div>
            <button className="btn" type="button" onClick={() => void save()} disabled={!canSubmit}>
              {busy ? <Spinner /> : null}
              {hint ? t("settings.update", "Update UPI ID") : t("settings.save", "Save UPI ID")}
            </button>
          </div>

          {/* The honest bit. */}
          <p className="muted" style={{ fontSize: 11.5, margin: 0 }}>
            {t(
              "settings.privacy",
              "Shared only with people you're in a group with and have a balance with — and only when they go to pay you. Unlike your passphrase-protected data, our server can read this, because it has to hand it to the payer.",
            )}
          </p>

          {disclosures.length > 0 && (
            <div style={{ display: "grid", gap: 6 }}>
              <button
                className="chip"
                type="button"
                aria-expanded={showLog}
                onClick={() => setShowLog((v) => !v)}
                style={{ justifySelf: "start", fontSize: 11.5 }}
              >
                {showLog
                  ? t("settings.hideLog", "Hide access log")
                  : t("settings.showLog", "Who's seen this ({{count}})", { count: disclosures.length })}
              </button>
              {showLog && (
                <ul style={{ margin: 0, paddingLeft: 18, fontSize: 12.5 }} className="muted">
                  {disclosures.map((d) => (
                    <li key={d.id}>
                      {profiles.get(d.viewer_user_id)?.name ?? t("settings.someone", "Someone")}
                      {" · "}
                      {new Date(d.created_at).toLocaleDateString(undefined, {
                        day: "numeric", month: "short", year: "2-digit",
                      })}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </>
      )}
    </section>
  );
}
