"use client";

/**
 * On-device speech-to-text for narrating to the assistant. Two engines:
 *  1. Whisper (transformers.js, lazy-loaded from a CDN) — record audio locally,
 *     transcribe fully on-device (audio never leaves the phone). Private default.
 *  2. Web Speech API — the browser's native dictation, used as a fallback when
 *     recording/Whisper isn't available. (On iOS/Android this is on-device too;
 *     on desktop Chrome it uses the browser's service.)
 * The assistant only replies in text for now.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

export const recordingSupported = () =>
  typeof navigator !== "undefined" && !!navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== "undefined" && typeof (window as any).OfflineAudioContext !== "undefined";

export const webSpeechSupported = () =>
  typeof window !== "undefined" && !!((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition);

export const voiceSupported = () => recordingSupported() || webSpeechSupported();

// --- Web Speech API (live dictation) ---------------------------------------
export interface LiveSession { stop: () => void; abort: () => void }
export function startWebSpeech(handlers: { onText: (t: string) => void; onEnd: (finalText: string) => void; onError?: (e: string) => void }): LiveSession {
  const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
  const rec = new SR();
  rec.lang = navigator.language || "en-IN";
  rec.interimResults = true;
  rec.continuous = false;
  let finalText = "";
  rec.onresult = (e: any) => {
    let interim = "";
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const r = e.results[i];
      if (r.isFinal) finalText += r[0].transcript; else interim += r[0].transcript;
    }
    handlers.onText((finalText + interim).trim());
  };
  rec.onerror = (e: any) => handlers.onError?.(String(e.error || "speech-error"));
  rec.onend = () => handlers.onEnd(finalText.trim());
  rec.start();
  return { stop: () => rec.stop(), abort: () => rec.abort() };
}

// --- Whisper (record → on-device transcribe) -------------------------------
const TRANSFORMERS_URL = "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.0.2";
let asrPipe: any = null;
async function getAsr(onProgress?: (p: number) => void) {
  if (asrPipe) return asrPipe;
  const t: any = await import(/* webpackIgnore: true */ TRANSFORMERS_URL);
  t.env.allowLocalModels = false;
  asrPipe = await t.pipeline("automatic-speech-recognition", "Xenova/whisper-tiny.en", {
    progress_callback: (e: any) => { if (e.status === "progress" && typeof e.progress === "number") onProgress?.(e.progress); },
  });
  return asrPipe;
}

export interface Recorder { stop: () => Promise<Blob>; cancel: () => void }
export async function startRecording(): Promise<Recorder> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const rec = new MediaRecorder(stream);
  const chunks: Blob[] = [];
  rec.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
  rec.start();
  const cleanup = () => stream.getTracks().forEach((t) => t.stop());
  return {
    stop: () => new Promise<Blob>((resolve) => { rec.onstop = () => { cleanup(); resolve(new Blob(chunks, { type: rec.mimeType || "audio/webm" })); }; rec.stop(); }),
    cancel: () => { try { rec.stop(); } catch { /* ignore */ } cleanup(); },
  };
}

/** Decode + resample an audio blob to 16 kHz mono Float32 (what Whisper wants). */
async function toMono16k(blob: Blob): Promise<Float32Array> {
  const ab = await blob.arrayBuffer();
  const AC = (window as any).AudioContext || (window as any).webkitAudioContext;
  const decoded = await new AC().decodeAudioData(ab);
  const offline = new (window as any).OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
  const src = offline.createBufferSource();
  src.buffer = decoded; src.connect(offline.destination); src.start();
  const rendered = await offline.startRendering();
  return rendered.getChannelData(0);
}

export async function transcribeWhisper(blob: Blob, onProgress?: (p: number) => void): Promise<string> {
  const asr = await getAsr(onProgress);
  const audio = await toMono16k(blob);
  const out = await asr(audio, { chunk_length_s: 30 });
  return String((Array.isArray(out) ? out[0]?.text : out?.text) || "").trim();
}
