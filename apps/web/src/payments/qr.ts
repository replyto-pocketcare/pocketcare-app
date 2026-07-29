"use client";

/**
 * QR rendering for the desktop pay flow.
 *
 * Lazy-loaded at runtime so nothing is added to the app bundle, mirroring how
 * `statements/parsePdf.ts` pulls in pdf.js and `receipts/ocr.ts` pulls in
 * tesseract. Hand-rolling a QR encoder was the alternative and is a genuinely
 * bad idea — Reed-Solomon error correction and mask-pattern selection are
 * exactly the kind of thing that "works on my test string" then fails on a real
 * payload.
 *
 * SELF-HOSTED, not CDN, for two reasons:
 *
 *  1. It was broken. This pointed at `qrcode@1.5.4/build/qrcode.min.js`, but
 *     the package STOPPED SHIPPING `build/` in 1.5.x — `files` still lists it,
 *     the directory isn't in the tarball. The request 404'd, `script.onerror`
 *     fired, and the QR never rendered for anyone. 1.4.4 is the last version
 *     with the UMD browser bundle that sets `window.QRCode`.
 *  2. A payment QR is exactly the thing you need in a restaurant with one bar
 *     of signal. The payload is built locally, so with the script self-hosted
 *     and precached by the service worker the whole flow works offline. The
 *     other CDN loads are megabyte-scale ML/PDF libraries where bundling isn't
 *     reasonable; this is 55 KB.
 *
 * Vendored file: `public/vendor/qrcode.min.js` (qrcode 1.4.4, MIT).
 */

const QR_URL = "/vendor/qrcode.min.js";

/* eslint-disable @typescript-eslint/no-explicit-any */
type AnyRec = Record<string, any>;

declare global {
  interface Window {
    QRCode?: AnyRec;
  }
}

export class QrError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QrError";
  }
}

let loading: Promise<AnyRec> | null = null;

function loadQrLib(): Promise<AnyRec> {
  if (window.QRCode) return Promise.resolve(window.QRCode);
  if (loading) return loading;
  loading = new Promise<AnyRec>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = QR_URL;
    script.async = true;
    script.onload = () => {
      if (window.QRCode) resolve(window.QRCode);
      else reject(new QrError("The QR library failed to initialise."));
    };
    script.onerror = () => {
      loading = null;
      reject(new QrError("Couldn't load the QR code library. Check your connection."));
    };
    document.head.appendChild(script);
  });
  return loading;
}

/**
 * Render a UPI intent string as a QR data URL.
 *
 * Error correction level M: enough redundancy to survive a phone camera at an
 * angle, without inflating the module count for a payload this size.
 */
export async function renderQrDataUrl(payload: string, size = 240): Promise<string> {
  const QRCode = await loadQrLib();
  try {
    return await QRCode.toDataURL(payload, {
      errorCorrectionLevel: "M",
      margin: 2,
      width: size,
      color: { dark: "#000000", light: "#ffffff" },
    });
  } catch (e) {
    throw new QrError(`Couldn't draw the QR code: ${(e as Error).message}`);
  }
}
