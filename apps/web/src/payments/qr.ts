"use client";

/**
 * QR rendering for the desktop pay flow.
 *
 * Lazy-loaded from a CDN at runtime, mirroring how `statements/parsePdf.ts`
 * pulls in pdf.js and `receipts/ocr.ts` pulls in tesseract: nothing is added to
 * the app bundle, and the asset is browser-cached after first use.
 *
 * Hand-rolling a QR encoder was the alternative and is a genuinely bad idea —
 * Reed-Solomon error correction and mask-pattern selection are exactly the kind
 * of thing that "works on my test string" and then fails on a real payload.
 */

const QR_VERSION = "1.5.4";
const QR_URL = `https://cdn.jsdelivr.net/npm/qrcode@${QR_VERSION}/build/qrcode.min.js`;

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
