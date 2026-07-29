"use client";

/**
 * Camera QR scanning for the pay-anyone flow.
 *
 * Two decoders, native first:
 *  1. `BarcodeDetector` — shipped in Chrome/Android, which is where UPI
 *     actually happens. Hardware-accelerated, nothing to download.
 *  2. `jsQR`, vendored at `public/vendor/jsQR.min.js` (Apache-2.0), lazily
 *     loaded only when the native API is missing (Safari/iOS, Firefox).
 *
 * It is NOT precached by the service worker, unlike the icon font and the QR
 * *encoder*: it's 128 KB that most users never need, and scanning requires a
 * camera and a deliberate tap. The browser caches it after first use.
 *
 * Decoding is the easy half. The hard half is that a QR is attacker-controlled
 * input — see `parseUpiTarget` in `@pocketcare/upi`. This module only returns
 * the decoded TEXT; it never decides anything about payment.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */
type AnyRec = Record<string, any>;

declare global {
  interface Window {
    jsQR?: (data: Uint8ClampedArray, width: number, height: number, opts?: AnyRec) => { data: string } | null;
    BarcodeDetector?: any;
  }
}

const JSQR_URL = "/vendor/jsQR.min.js";

export class ScanError extends Error {
  constructor(message: string, readonly kind: "permission" | "unsupported" | "load" | "other" = "other") {
    super(message);
    this.name = "ScanError";
  }
}

let jsqrLoading: Promise<NonNullable<Window["jsQR"]>> | null = null;

function loadJsQr(): Promise<NonNullable<Window["jsQR"]>> {
  if (window.jsQR) return Promise.resolve(window.jsQR);
  if (jsqrLoading) return jsqrLoading;
  jsqrLoading = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = JSQR_URL;
    s.async = true;
    s.onload = () => {
      if (window.jsQR) resolve(window.jsQR);
      else reject(new ScanError("The QR scanner failed to initialise.", "load"));
    };
    s.onerror = () => { jsqrLoading = null; reject(new ScanError("Couldn't load the QR scanner.", "load")); };
    document.head.appendChild(s);
  });
  return jsqrLoading;
}

export interface Scanner {
  /** Attach the camera stream to a <video> and begin decoding. */
  start(video: HTMLVideoElement, onResult: (text: string) => void): Promise<void>;
  /** Stop decoding and release the camera. Safe to call repeatedly. */
  stop(): void;
}

/**
 * A scanner bound to one <video>. Always `stop()` it — a live camera that
 * outlives its modal is both a battery drain and a privacy problem.
 */
export function createScanner(): Scanner {
  let stream: MediaStream | null = null;
  let raf = 0;
  let stopped = false;

  const stop = () => {
    stopped = true;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    stream?.getTracks().forEach((t) => t.stop());
    stream = null;
  };

  const start = async (video: HTMLVideoElement, onResult: (text: string) => void) => {
    stopped = false;
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new ScanError("This browser can't use the camera.", "unsupported");
    }
    try {
      // `environment` = rear camera, which is the one pointed at a QR.
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" } },
        audio: false,
      });
    } catch (e) {
      const name = (e as Error).name;
      throw new ScanError(
        name === "NotAllowedError" || name === "SecurityError"
          ? "Camera access was blocked. Allow it in your browser settings, or enter the UPI ID by hand."
          : "Couldn't open the camera.",
        name === "NotAllowedError" || name === "SecurityError" ? "permission" : "other",
      );
    }

    video.srcObject = stream;
    video.setAttribute("playsinline", "true"); // iOS: don't hijack into fullscreen
    await video.play().catch(() => { /* autoplay policies vary; the frames still arrive */ });

    const detector = window.BarcodeDetector
      ? new window.BarcodeDetector({ formats: ["qr_code"] })
      : null;
    const decodeFallback = detector ? null : await loadJsQr();

    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d", { willReadFrequently: true });

    const tick = async () => {
      if (stopped) return;
      if (video.readyState === video.HAVE_ENOUGH_DATA) {
        try {
          let text: string | null = null;
          if (detector) {
            const codes = await detector.detect(video);
            text = codes?.[0]?.rawValue ?? null;
          } else if (ctx && decodeFallback) {
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
            text = decodeFallback(img.data, img.width, img.height, { inversionAttempts: "dontInvert" })?.data ?? null;
          }
          if (text) {
            // One result is enough — the caller decides what to do next, and a
            // second callback mid-navigation causes double handling.
            stop();
            onResult(text);
            return;
          }
        } catch { /* a dropped frame is not an error worth surfacing */ }
      }
      raf = requestAnimationFrame(() => { void tick(); });
    };
    raf = requestAnimationFrame(() => { void tick(); });
  };

  return { start, stop };
}

/** Whether a camera scan is even worth offering on this device. */
export function canScan(): boolean {
  return typeof navigator !== "undefined" && !!navigator.mediaDevices?.getUserMedia;
}
