"use client";

/**
 * On-device OCR via tesseract.js.
 *
 * Loaded lazily from a CDN at runtime, mirroring how `src/statements/parsePdf.ts`
 * pulls in pdf.js: nothing is added to the app bundle, the assets are
 * browser-cached after first use, and the receipt image never leaves the device.
 * First scan needs a connection; every scan after that works offline.
 *
 * We keep WORD BOUNDING BOXES, not just the flattened text. That is the whole
 * game for receipts: "2  Cold Coffee  120.00" is only unambiguous if you know
 * which column each token sat in. `parse.ts` rebuilds lines from these boxes.
 */

const TESSERACT_VERSION = "5.1.1";
const TESSERACT_URL = `https://cdn.jsdelivr.net/npm/tesseract.js@${TESSERACT_VERSION}/dist/tesseract.min.js`;

export interface OcrWord {
  readonly text: string;
  readonly x0: number;
  readonly y0: number;
  readonly x1: number;
  readonly y1: number;
  /** 0-100 for this word. */
  readonly confidence: number;
}

export interface OcrResult {
  readonly text: string;
  /** Mean word confidence, 0-100. */
  readonly confidence: number;
  readonly words: readonly OcrWord[];
}

export type OcrProgress = (fraction: number) => void;

export class OcrError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OcrError";
  }
}

/* eslint-disable @typescript-eslint/no-explicit-any */
type AnyRec = Record<string, any>;

declare global {
  interface Window {
    Tesseract?: AnyRec;
  }
}

let loading: Promise<AnyRec> | null = null;

/**
 * Inject the UMD build once and hand back `window.Tesseract`.
 *
 * The UMD bundle rather than the ESM one on purpose: tesseract.js resolves its
 * worker and wasm relative to its own script URL, which is exactly what we want
 * from a CDN and exactly what breaks under a bundler-rewritten dynamic import.
 */
function loadTesseract(): Promise<AnyRec> {
  if (window.Tesseract) return Promise.resolve(window.Tesseract);
  if (loading) return loading;
  loading = new Promise<AnyRec>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = TESSERACT_URL;
    script.async = true;
    script.onload = () => {
      if (window.Tesseract) resolve(window.Tesseract);
      else reject(new OcrError("The text recognition library failed to initialise."));
    };
    script.onerror = () => {
      loading = null;
      reject(new OcrError("Couldn't download the text recognition library. Check your connection."));
    };
    document.head.appendChild(script);
  });
  return loading;
}

/**
 * Walk whichever shape this tesseract build returns.
 *
 * v5 moved word data behind the `blocks` output flag and nests it
 * block → paragraph → line → word, while older builds expose a flat
 * `data.words`. Handle both so a CDN patch bump can't silently strip our boxes.
 */
function collectWords(data: AnyRec): OcrWord[] {
  const out: OcrWord[] = [];
  const push = (w: AnyRec): void => {
    const bbox = w?.bbox ?? {};
    const text = String(w?.text ?? "").trim();
    if (!text) return;
    out.push({
      text,
      x0: Number(bbox.x0 ?? 0),
      y0: Number(bbox.y0 ?? 0),
      x1: Number(bbox.x1 ?? 0),
      y1: Number(bbox.y1 ?? 0),
      confidence: Number(w?.confidence ?? 0),
    });
  };

  if (Array.isArray(data?.words) && data.words.length > 0) {
    for (const w of data.words) push(w);
    return out;
  }
  for (const block of data?.blocks ?? []) {
    for (const para of block?.paragraphs ?? []) {
      for (const line of para?.lines ?? []) {
        for (const w of line?.words ?? []) push(w);
      }
    }
  }
  return out;
}

/**
 * Recognise text in a preprocessed receipt image.
 *
 * `onProgress` reports 0-1 so the capture screen can show real movement — OCR
 * on a phone takes several seconds and a spinner with no progress reads as a
 * hang.
 */
export async function runOcr(image: Blob, onProgress?: OcrProgress): Promise<OcrResult> {
  const Tesseract = await loadTesseract();

  let worker: AnyRec | null = null;
  try {
    worker = await Tesseract.createWorker("eng", 1, {
      logger: (m: AnyRec) => {
        if (m?.status === "recognizing text" && typeof m.progress === "number") {
          onProgress?.(m.progress);
        }
      },
    });

    await worker!.setParameters({
      // Receipts are one column of text at varying sizes.
      tessedit_pageseg_mode: "4",
      // Keep runs of spaces: they are the column gutters parse.ts leans on when
      // bounding boxes are unavailable.
      preserve_interword_spaces: "1",
    });

    const { data } = await worker!.recognize(image, {}, { text: true, blocks: true });
    const words = collectWords(data);
    const confidence =
      words.length > 0
        ? Math.round(words.reduce((s, w) => s + w.confidence, 0) / words.length)
        : Number(data?.confidence ?? 0);

    return { text: String(data?.text ?? ""), confidence, words };
  } catch (e) {
    if (e instanceof OcrError) throw e;
    throw new OcrError(`Text recognition failed: ${(e as Error).message}`);
  } finally {
    // Always tear the worker down — each one holds a wasm heap, and leaking one
    // per scan will OOM a phone after a handful of receipts.
    try {
      await worker?.terminate();
    } catch {
      /* already gone */
    }
  }
}
