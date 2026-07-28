"use client";

/**
 * Receipt image preprocessing — all on-device, canvas only, no dependencies.
 *
 * OCR quality on a phone photo of a thermal receipt is dominated by what you
 * feed the engine, not by the engine. Three things move the needle, in order:
 *   1. Sane resolution — too small loses strokes, too large is slow and adds
 *      sensor noise. ~1600px on the long edge is the sweet spot for receipts.
 *   2. Grayscale with the green channel weighted — matches luminance and kills
 *      the colour fringing that thermal paper photographs with.
 *   3. ADAPTIVE (local) thresholding — a receipt photo is almost never lit
 *      evenly; a single global cutoff blows out the bright half and drowns the
 *      shadowed half. Local mean-minus-C fixes exactly that.
 *
 * The blob produced here is passed to OCR and then dropped. It is never written
 * to IndexedDB, never uploaded, and only leaves the device if the user
 * explicitly taps "Improve with AI".
 */

/** Long-edge target. Big enough for small print, small enough to stay fast. */
export const TARGET_LONG_EDGE = 1600;
/** Anything under this is upscaled — OCR does better with a bit more to chew on. */
const MIN_LONG_EDGE = 900;
/** Local-threshold window as a fraction of the long edge. ~1 text line tall. */
const WINDOW_FRACTION = 1 / 24;
/** Mean-minus-C constant. Higher = more aggressive at dropping faint pixels. */
const THRESHOLD_C = 10;

export interface PreparedImage {
  /** Preprocessed, OCR-ready JPEG. */
  readonly blob: Blob;
  /** Data URL of the ORIGINAL (not thresholded) image, for the on-screen preview. */
  readonly previewUrl: string;
  /** Base64 (no data: prefix) of the original, for the AI fallback. */
  readonly base64: () => Promise<string>;
  readonly mediaType: string;
  readonly width: number;
  readonly height: number;
}

export class ImageDecodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImageDecodeError";
  }
}

/**
 * Decode a file to a bitmap, honouring EXIF orientation.
 *
 * `imageOrientation: "from-image"` is what stops portrait phone photos arriving
 * sideways — without it every iPhone receipt OCRs as gibberish.
 */
async function decode(file: Blob): Promise<ImageBitmap> {
  try {
    return await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch (e) {
    // HEIC/HEIF is the usual culprit: Safari decodes it, most others do not.
    throw new ImageDecodeError(
      `Could not read this image (${(e as Error).message}). Try a JPEG or PNG.`,
    );
  }
}

function scaleFor(w: number, h: number): number {
  const long = Math.max(w, h);
  if (long > TARGET_LONG_EDGE) return TARGET_LONG_EDGE / long;
  if (long < MIN_LONG_EDGE) return Math.min(2, MIN_LONG_EDGE / long);
  return 1;
}

function canvasOf(w: number, h: number): { canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D } {
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(w));
  canvas.height = Math.max(1, Math.round(h));
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new ImageDecodeError("Canvas is unavailable in this browser.");
  return { canvas, ctx };
}

/**
 * Grayscale in place, returning the luma plane.
 * Rec. 601 weights — closer to perceived brightness than a flat average, which
 * matters for the blue-ish ink some thermal printers use.
 */
function toGray(data: Uint8ClampedArray, w: number, h: number): Uint8Array {
  const gray = new Uint8Array(w * h);
  for (let i = 0, p = 0; i < data.length; i += 4, p++) {
    gray[p] = (data[i]! * 299 + data[i + 1]! * 587 + data[i + 2]! * 114) / 1000;
  }
  return gray;
}

/**
 * Stretch contrast to the 2nd–98th percentile.
 *
 * Clipping the tails first means one dark fold or one specular highlight can't
 * eat the whole dynamic range, which is the common failure on crumpled bills.
 */
function normalize(gray: Uint8Array): void {
  const hist = new Uint32Array(256);
  for (const v of gray) hist[v]!++;
  const total = gray.length;
  const lowCut = total * 0.02;
  const highCut = total * 0.98;
  let acc = 0, lo = 0, hi = 255;
  for (let v = 0; v < 256; v++) { acc += hist[v]!; if (acc >= lowCut) { lo = v; break; } }
  acc = 0;
  for (let v = 0; v < 256; v++) { acc += hist[v]!; if (acc >= highCut) { hi = v; break; } }
  if (hi <= lo) return;
  const span = hi - lo;
  for (let i = 0; i < gray.length; i++) {
    gray[i] = Math.max(0, Math.min(255, ((gray[i]! - lo) * 255) / span));
  }
}

/**
 * Adaptive threshold via a summed-area table (integral image).
 *
 * The integral image makes the local mean O(1) per pixel regardless of window
 * size, so a full-page window costs the same as a tiny one — without it this is
 * unusably slow on a phone.
 */
function adaptiveThreshold(gray: Uint8Array, w: number, h: number): void {
  const integral = new Float64Array((w + 1) * (h + 1));
  for (let y = 0; y < h; y++) {
    let rowSum = 0;
    for (let x = 0; x < w; x++) {
      rowSum += gray[y * w + x]!;
      integral[(y + 1) * (w + 1) + (x + 1)] = integral[y * (w + 1) + (x + 1)]! + rowSum;
    }
  }
  const radius = Math.max(8, Math.round((Math.max(w, h) * WINDOW_FRACTION) / 2));
  const out = new Uint8Array(gray.length);
  for (let y = 0; y < h; y++) {
    const y0 = Math.max(0, y - radius), y1 = Math.min(h - 1, y + radius);
    for (let x = 0; x < w; x++) {
      const x0 = Math.max(0, x - radius), x1 = Math.min(w - 1, x + radius);
      const area = (y1 - y0 + 1) * (x1 - x0 + 1);
      const sum =
        integral[(y1 + 1) * (w + 1) + (x1 + 1)]! -
        integral[y0 * (w + 1) + (x1 + 1)]! -
        integral[(y1 + 1) * (w + 1) + x0]! +
        integral[y0 * (w + 1) + x0]!;
      out[y * w + x] = gray[y * w + x]! * area > sum - THRESHOLD_C * area ? 255 : 0;
    }
  }
  gray.set(out);
}

function blobFrom(canvas: HTMLCanvasElement, type: string, quality?: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new ImageDecodeError("Could not encode the image."))),
      type,
      quality,
    );
  });
}

/**
 * Full preprocessing pass: decode → scale → grayscale → normalize → threshold.
 *
 * Returns both the binarized image (what OCR reads) and the untouched original
 * (what the user sees, and what the AI fallback would send — vision models do
 * markedly better on the original than on a hard-thresholded one).
 */
export async function prepareImage(file: Blob): Promise<PreparedImage> {
  const bitmap = await decode(file);
  const scale = scaleFor(bitmap.width, bitmap.height);
  const w = Math.round(bitmap.width * scale);
  const h = Math.round(bitmap.height * scale);

  // Pass 1 — the colour original, downscaled. Preview + AI fallback source.
  const original = canvasOf(w, h);
  original.ctx.drawImage(bitmap, 0, 0, w, h);
  const originalBlob = await blobFrom(original.canvas, "image/jpeg", 0.9);

  // Pass 2 — the binarized version OCR actually reads.
  const work = canvasOf(w, h);
  work.ctx.drawImage(bitmap, 0, 0, w, h);
  bitmap.close?.();
  const imageData = work.ctx.getImageData(0, 0, w, h);
  const gray = toGray(imageData.data, w, h);
  normalize(gray);
  adaptiveThreshold(gray, w, h);
  for (let i = 0, p = 0; i < imageData.data.length; i += 4, p++) {
    const v = gray[p]!;
    imageData.data[i] = v;
    imageData.data[i + 1] = v;
    imageData.data[i + 2] = v;
    imageData.data[i + 3] = 255;
  }
  work.ctx.putImageData(imageData, 0, 0);
  const ocrBlob = await blobFrom(work.canvas, "image/jpeg", 0.92);

  return {
    blob: ocrBlob,
    previewUrl: original.canvas.toDataURL("image/jpeg", 0.7),
    base64: async () => toBase64(originalBlob),
    mediaType: "image/jpeg",
    width: w,
    height: h,
  };
}

/** Strip the `data:...;base64,` prefix — the Anthropic API wants raw base64. */
export function toBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const s = String(reader.result);
      resolve(s.slice(s.indexOf(",") + 1));
    };
    reader.onerror = () => reject(new ImageDecodeError("Could not read the file."));
    reader.readAsDataURL(blob);
  });
}

/** Reject obviously-wrong input early with a message worth reading. */
export const MAX_UPLOAD_BYTES = 15 * 1024 * 1024;

export function validateFile(file: File): string | null {
  const isImage = file.type.startsWith("image/");
  const isPdf = file.type === "application/pdf";
  if (!isImage && !isPdf) return "Pick an image or a PDF of the receipt.";
  if (file.size > MAX_UPLOAD_BYTES) return "That file is over 15 MB — try a photo instead of a scan.";
  if (file.size === 0) return "That file is empty.";
  return null;
}
